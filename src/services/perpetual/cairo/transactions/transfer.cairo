from services.exchange.cairo.definitions.constants import VAULT_ID_UPPER_BOUND
from services.exchange.cairo.order import OrderBase
from services.exchange.cairo.signature_message_hashes import ExchangeTransfer
from services.exchange.cairo.signature_message_hashes import transfer_hash as exchange_transfer_hash
from services.perpetual.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND, POSITION_ID_UPPER_BOUND)
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode, assert_success)
from services.perpetual.cairo.order.order import validate_order_and_update_fulfillment
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID, update_position_in_dict)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_nn_le, assert_not_equal

struct Transfer:
    member base : OrderBase*
    member nonce : felt
    # sender_public_key is the base's public_key.
    member sender_position_id : felt
    member receiver_public_key : felt
    member receiver_position_id : felt
    member amount : felt
    member asset_id : felt
    member expiration_timestamp : felt
end

# See the documentation of transfer_hash under exchange/signature_message_hashes.cairo.
# Since there are currently no fees in transfer, max_amount_fee and asset_id_fee are zero.
#
# Assumptions:
# 0 <= nonce < NONCE_UPPER_BOUND
# 0 <= sender_position_id, receiver_position_id, src_fee_position_id < POSITION_ID_UPPER_BOUND
# 0 <= amount, max_amount_fee < AMOUNT_UPPER_BOUND
# 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
func transfer_hash(pedersen_ptr : HashBuiltin*, transfer : Transfer*, condition : felt) -> (
        pedersen_ptr : HashBuiltin*, message):
    alloc_locals
    static_assert POSITION_ID_UPPER_BOUND == VAULT_ID_UPPER_BOUND

    let (local exchange_transfer : ExchangeTransfer*) = alloc()
    assert exchange_transfer.base = transfer.base
    assert exchange_transfer.sender_vault_id = transfer.sender_position_id
    assert exchange_transfer.receiver_public_key = transfer.receiver_public_key
    assert exchange_transfer.receiver_vault_id = transfer.receiver_position_id
    assert exchange_transfer.amount = transfer.amount
    assert exchange_transfer.asset_id = transfer.asset_id
    # The sender is the one that pays the fee.
    assert exchange_transfer.src_fee_vault_id = transfer.sender_position_id
    assert exchange_transfer.asset_id_fee = 0
    assert exchange_transfer.max_amount_fee = 0

    let (transfer_hash) = exchange_transfer_hash{pedersen_ptr=pedersen_ptr}(
        transfer=exchange_transfer, condition=condition)
    return (pedersen_ptr=pedersen_ptr, message=transfer_hash)
end

func execute_transfer(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : Transfer*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals
    %{ error_code = ids.PerpetualErrorCode.SAME_POSITION_ID %}
    assert_not_equal(tx.sender_position_id, tx.receiver_position_id)
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_AMOUNT %}
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount, AMOUNT_UPPER_BOUND - 1)
    %{ del error_code %}
    local range_check_ptr = range_check_ptr
    # expiration_timestamp and nonce will be validated in validate_order_and_update_fulfillment.
    # Asset id is in range because we check that it's equal to the collateral asset id.
    # Sender/Reciever's position id will be validated by update_position_in_dict.

    local general_config : GeneralConfig* = batch_config.general_config
    # Validate that asset is collateral.
    %{ error_code = ids.PerpetualErrorCode.INVALID_COLLATERAL_ASSET_ID %}
    assert tx.asset_id = general_config.collateral_asset_info.asset_id
    %{ del error_code %}

    let (local pedersen_ptr, message_hash) = transfer_hash(
        pedersen_ptr=pedersen_ptr, transfer=tx, condition=0)

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

    # Update the sender's position.
    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.sender_position_id,
        request_public_key=tx.base.public_key,
        collateral_delta=-tx.amount,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config)
    assert_success(return_code)

    # Update the receiver's position.
    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=positions_dict,
        position_id=tx.receiver_position_id,
        request_public_key=tx.receiver_public_key,
        collateral_delta=tx.amount,
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

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
