from services.exchange.cairo.order import OrderBase
from services.perpetual.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND, EXPIRATION_TIMESTAMP_UPPER_BOUND, NONCE_UPPER_BOUND, ORDER_ID_UPPER_BOUND,
    POSITION_ID_UPPER_BOUND)
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.perpetual_error_code import assert_success
from services.perpetual.cairo.order.order import validate_order_and_update_fulfillment
from services.perpetual.cairo.output.program_output import (
    Modification, PerpetualOutputs, perpetual_outputs_new)
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID, update_position_in_dict)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_nn_le

struct Withdrawal:
    member base : OrderBase*
    member position_id : felt
    member amount : felt
end

# withdrawal_hash:
# Computes the hash of withdrawal request.
#
# The hash is defined as h(w1, w2) where h is the starkware pedersen function and w1, w2 are as
# follows:
#   w1= asset_id_collateral
#   w2= 0x6 (10 bit) || vault_from (64 bit) || nonce (32 bit) || amount (64 bit)
#    || expiration_timestamp (32 bit) ||  0 (49 bit)
#
# Assumptions:
# 0 <= nonce < NONCE_UPPER_BOUND
# 0 <= position_id < POSITION_ID_UPPER_BOUND
# 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND
# 0 <= amount < AMOUNT_UPPER_BOUND.
func withdrawal_hash(
        pedersen_ptr : HashBuiltin*, withdrawal : Withdrawal*, asset_id_collateral) -> (
        pedersen_ptr : HashBuiltin*, message):
    const WITHDRAWAL = 6
    let packed_message = WITHDRAWAL
    let packed_message = packed_message * POSITION_ID_UPPER_BOUND + withdrawal.position_id
    let packed_message = packed_message * NONCE_UPPER_BOUND + withdrawal.base.nonce
    let packed_message = packed_message * AMOUNT_UPPER_BOUND + withdrawal.amount
    let expiration_timestamp = withdrawal.base.expiration_timestamp
    let packed_message = packed_message * EXPIRATION_TIMESTAMP_UPPER_BOUND + expiration_timestamp
    let packed_message = packed_message * %[2**49%]  # Padding.

    let (message) = hash2{hash_ptr=pedersen_ptr}(x=asset_id_collateral, y=packed_message)
    return (pedersen_ptr=pedersen_ptr, message=message)
end

func execute_withdrawal(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : Withdrawal*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals
    local general_config : GeneralConfig* = batch_config.general_config

    # The amount, nonce and expiration_timestamp are range checked in
    # validate_order_and_update_fulfillment.
    # By using update_position_in_dict with tx.position_id we check that
    # 0 <= tx.position_id < 2**POSITION_TREE_HEIGHT = POSITION_ID_UPPER_BOUND.
    let (local pedersen_ptr, message_hash) = withdrawal_hash(
        pedersen_ptr=pedersen_ptr,
        withdrawal=tx,
        asset_id_collateral=general_config.collateral_asset_info.asset_id)

    let (range_check_ptr, local ecdsa_ptr,
        local orders_dict) = validate_order_and_update_fulfillment(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        orders_dict=carried_state.orders_dict,
        message_hash=message_hash,
        order=tx.base,
        min_expiration_timestamp=batch_config.min_expiration_timestamp,
        update_amount=tx.amount,
        full_amount=tx.amount)

    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.position_id,
        request_public_key=tx.base.public_key,
        collateral_delta=-tx.amount,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config)
    assert_success(return_code)

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time)

    # Write to output.
    tempvar modification : Modification* = outputs.modifications_ptr
    assert modification.public_key = tx.base.public_key
    assert modification.position_id = tx.position_id
    # For explanation why we add AMOUNT_UPPER_BOUND, see Modification's documentation.
    assert modification.biased_delta = AMOUNT_UPPER_BOUND - tx.amount
    let (outputs : PerpetualOutputs*) = perpetual_outputs_new(
        modifications_ptr=modification + Modification.SIZE,
        forced_actions_ptr=outputs.forced_actions_ptr,
        conditions_ptr=outputs.conditions_ptr,
        funding_indices_table_ptr=outputs.funding_indices_table_ptr)

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
