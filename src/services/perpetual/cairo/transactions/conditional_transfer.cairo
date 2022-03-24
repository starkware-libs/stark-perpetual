from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode, assert_success)
from services.perpetual.cairo.order.order import validate_order_and_update_fulfillment
from services.perpetual.cairo.output.program_output import PerpetualOutputs, perpetual_outputs_new
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID, update_position_in_dict)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from services.perpetual.cairo.transactions.transfer import Transfer, transfer_hash
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_not_equal

struct ConditionalTransfer:
    member transfer : Transfer*
    member condition : felt
end

func execute_conditional_transfer(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : ConditionalTransfer*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals
    %{ error_code = ids.PerpetualErrorCode.SAME_POSITION_ID %}
    assert_not_equal(tx.transfer.sender_position_id, tx.transfer.receiver_position_id)
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_AMOUNT %}
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.transfer.amount, AMOUNT_UPPER_BOUND - 1)
    %{ del error_code %}
    local range_check_ptr = range_check_ptr
    # expiration_timestamp and nonce will be validated in validate_order_and_update_fulfillment.
    # Asset id is in range because we check that it's equal to the collateral asset id.
    # Sender/Receiver's position id will be validated by update_position_in_dict.

    local general_config : GeneralConfig* = batch_config.general_config
    # Validate that asset is collateral.
    %{ error_code = ids.PerpetualErrorCode.INVALID_COLLATERAL_ASSET_ID %}
    assert tx.transfer.asset_id = general_config.collateral_asset_info.asset_id
    %{ del error_code %}

    let (local pedersen_ptr, message_hash) = transfer_hash(
        pedersen_ptr=pedersen_ptr, transfer=tx.transfer, condition=tx.condition)

    let (range_check_ptr, local ecdsa_ptr,
        local orders_dict) = validate_order_and_update_fulfillment(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        orders_dict=carried_state.orders_dict,
        message_hash=message_hash,
        order=tx.transfer.base,
        min_expiration_timestamp=batch_config.min_expiration_timestamp,
        update_amount=tx.transfer.amount,
        full_amount=tx.transfer.amount)

    # Update the sender position.
    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.transfer.sender_position_id,
        request_public_key=tx.transfer.base.public_key,
        collateral_delta=-tx.transfer.amount,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config)
    assert_success(return_code)

    # Update the receiver position.
    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=positions_dict,
        position_id=tx.transfer.receiver_position_id,
        request_public_key=tx.transfer.receiver_public_key,
        collateral_delta=tx.transfer.amount,
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

    # Output the condition.
    assert [outputs.conditions_ptr] = tx.condition
    let (outputs : PerpetualOutputs*) = perpetual_outputs_new(
        modifications_ptr=outputs.modifications_ptr,
        forced_actions_ptr=outputs.forced_actions_ptr,
        conditions_ptr=outputs.conditions_ptr + 1,
        funding_indices_table_ptr=outputs.funding_indices_table_ptr)

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
