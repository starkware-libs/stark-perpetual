from services.exchange.cairo.order import OrderBase
from services.perpetual.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND, EXPIRATION_TIMESTAMP_UPPER_BOUND, NONCE_UPPER_BOUND, ORDER_ID_UPPER_BOUND,
    RANGE_CHECK_BOUND, SIGNED_MESSAGE_BOUND)
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from starkware.cairo.common.cairo_builtins import SignatureBuiltin
from starkware.cairo.common.dict import dict_update
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_in_range, assert_le, assert_nn, assert_nn_le
from starkware.cairo.common.signature import verify_ecdsa_signature

# Extracts the order_id from the message_hash.
# The order_id is represented by the 64 most significant bits of the message_hash.
#
# Assumptions:
#   The caller checks that 0 <= order_id < ORDER_ID_UPPER_BOUND.
#   0 <= message_hash < SIGNED_MESSAGE_BOUND.
func extract_order_id(range_check_ptr, message_hash) -> (range_check_ptr, order_id):
    # The 251-bit message_hash can be viewed as a packing of three fields:
    # +----------------+--------------------+----------------LSB-+
    # | order_id (64b) | middle_field (59b) | right_field (128b) |
    # +----------------+--------------------+--------------------+
    # .
    const ORDER_ID_SHIFT = SIGNED_MESSAGE_BOUND / ORDER_ID_UPPER_BOUND
    const MIDDLE_FIELD_BOUND = ORDER_ID_SHIFT / RANGE_CHECK_BOUND

    # Local variables.
    local middle_field
    local right_field
    local order_id
    %{
        msg_hash = ids.message_hash
        ids.order_id = msg_hash // ids.ORDER_ID_SHIFT
        ids.right_field = msg_hash & (ids.RANGE_CHECK_BOUND - 1)
        ids.middle_field = (msg_hash // ids.RANGE_CHECK_BOUND) & (ids.MIDDLE_FIELD_BOUND - 1)
        assert ids.MIDDLE_FIELD_BOUND & (ids.MIDDLE_FIELD_BOUND - 1) == 0, \
            f'MIDDLE_FIELD_BOUND should be a power of 2'
    %}
    alloc_locals

    # Verify that the message_hash definition holds, i.e., that:
    assert message_hash = order_id * ORDER_ID_SHIFT + middle_field * RANGE_CHECK_BOUND + right_field

    # Verify the message_hash structure (i.e., the size of each field), to ensure unique unpacking.
    # Note that the size of order_id is verified by performing merkle_update on the order tree.
    # Check that 0 <= right_field < RANGE_CHECK_BOUND.
    assert_nn{range_check_ptr=range_check_ptr}(right_field)

    # Check that 0 <= middle_field < MIDDLE_FIELD_BOUND.
    assert_nn_le{range_check_ptr=range_check_ptr}(middle_field, MIDDLE_FIELD_BOUND - 1)

    return (range_check_ptr=range_check_ptr, order_id=order_id)
end

# Updates the fulfillment amount of a user order to prevent replays.
# Extracts the order_id from the message_hash.
# Checks that update_amount does not exceed the order_capacity (= full_amount - fulfilled_amount).
# And updates the fulfilled_amount to reflect that 'update_amount' units were consumed.
#
# Checks that update_amount and full_amount are in the range [0, AMOUNT_UPPER_BOUND)
# Checks that the new value written in the order_dict is in the range [0, AMOUNT_UPPER_BOUND) in
# order to maintain the assumption.
#
# Arguments:
# range_check_ptr - range check builtin pointer.
# orders_dict - a pointer to the orders dict.
# message_hash - The hash of the order.
# update_amount - The amount to add to the current amount in the order tree.
# full_amount - The full in the user order, the order may not exceed this amount.
#
# Assumption:
# The amounts in the orders_dict are in the range [0, AMOUNT_UPPER_BOUND).
func update_order_fulfillment(
        range_check_ptr, orders_dict : DictAccess*, message_hash, update_amount, full_amount) -> (
        range_check_ptr, orders_dict : DictAccess*):
    alloc_locals

    # Note that by using order_id to access the order_dict we check that
    # 0 <= order_id < 2**ORDER_TREE_HEIGHT = ORDER_ID_UPPER_BOUND.
    let (range_check_ptr, order_id) = extract_order_id(
        range_check_ptr=range_check_ptr, message_hash=message_hash)

    # The function's assumption means that 0 <= fulfilled_amount < AMOUNT_UPPER_BOUND.
    local fulfilled_amount
    %{
        ids.fulfilled_amount = __dict_manager.get_dict(ids.orders_dict)[ids.order_id]
        # Prepare error_code in case of error. This won't affect the cairo logic.
        if ids.update_amount > ids.full_amount - ids.fulfilled_amount:
            error_code = ids.PerpetualErrorCode.INVALID_FULFILLMENT_INFO
        else:
            # If there's an error in this case, then it's because update_amount is negative.
            error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_AMOUNT
    %}
    let remaining_capacity = full_amount - fulfilled_amount

    # Check that 0 <= update_amount <= full_amount - fulfilled_amount.
    # Note that we may have remaining_capacity < 0 in the case of a collision in the order_id.
    # The function assert_nn_le doesn't ensure the right argument is non-negative. Instead, it
    # ensures that it is in the range [0, 2**129). We can still consider it a positive small number
    # for all purposes.
    assert_nn_le{range_check_ptr=range_check_ptr}(update_amount, remaining_capacity)
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_AMOUNT %}

    # Check that full_amount < AMOUNT_UPPER_BOUND. We know that full_amount >= 0 because:
    #   full_amount = remaining_capacity + fulfilled_amount. Both those numbers are non-negative.
    #
    # After this check we can deduce that update_amount is in range because:
    # 0 <= update_amount <= remaining_capacity <= full_amount < AMOUNT_UPPER_BOUND.
    assert_le{range_check_ptr=range_check_ptr}(full_amount, AMOUNT_UPPER_BOUND - 1)
    %{ del error_code %}

    # new_value is in the range [0, AMOUNT_UPPER_BOUND) because:
    # 1. fulfilled_amount, update_amount are non-negative. Therefore, new_value is non-negative.
    # 2. new_value <= fulfilled_amount + remaining_capacity = full_amount < AMOUNT_UPPER_BOUND.
    dict_update{dict_ptr=orders_dict}(
        key=order_id, prev_value=fulfilled_amount, new_value=fulfilled_amount + update_amount)

    return (range_check_ptr=range_check_ptr, orders_dict=orders_dict)
end

# Does the generic book keeping for a user signed order (limit_order, withdrawal, transfer, etc.).
# Checks the signature, the expiration_timestamp and calls update_order_fulfillment.
# The caller is responsible for the order specific logic. I.e., updating the positions dict.
func validate_order_and_update_fulfillment(
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, orders_dict : DictAccess*, message_hash,
        order : OrderBase*, min_expiration_timestamp, update_amount, full_amount) -> (
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, orders_dict : DictAccess*):
    %{ error_code = ids.PerpetualErrorCode.INVALID_SIGNATURE %}
    with ecdsa_ptr:
        verify_ecdsa_signature(
            message=message_hash,
            public_key=order.public_key,
            signature_r=order.signature_r,
            signature_s=order.signature_s)
    end
    %{ del error_code %}
    assert_in_range{range_check_ptr=range_check_ptr}(
        order.expiration_timestamp, min_expiration_timestamp, EXPIRATION_TIMESTAMP_UPPER_BOUND)
    assert_nn_le{range_check_ptr=range_check_ptr}(order.nonce, NONCE_UPPER_BOUND - 1)

    let (range_check_ptr, orders_dict : DictAccess*) = update_order_fulfillment(
        range_check_ptr=range_check_ptr,
        orders_dict=orders_dict,
        message_hash=message_hash,
        update_amount=update_amount,
        full_amount=full_amount)

    return (range_check_ptr=range_check_ptr, ecdsa_ptr=ecdsa_ptr, orders_dict=orders_dict)
end
