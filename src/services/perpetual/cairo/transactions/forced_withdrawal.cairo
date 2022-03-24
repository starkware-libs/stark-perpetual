from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode, assert_success)
from services.perpetual.cairo.output.forced import (
    ForcedAction, ForcedActionType, forced_withdrawal_action_new)
from services.perpetual.cairo.output.program_output import (
    Modification, PerpetualOutputs, perpetual_outputs_new)
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID, update_position_in_dict)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_not_equal

struct ForcedWithdrawal:
    member public_key : felt
    member position_id : felt
    member amount : felt
    member is_valid : felt
end

func execute_forced_withdrawal(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : ForcedWithdrawal*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals

    # Check fields.
    # public_key is valid since it comes from the previous position.
    # position_id is verified by being a dict key.
    # Note: We don't mind failing here even when is_valid is 0, since the amount and the position_id
    # should be verified on-chain when a user makes the forced action request.
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_AMOUNT %}
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount, AMOUNT_UPPER_BOUND - 1)
    %{ del error_code %}

    # Try to update the position. update_position_in_dict will not update the position if it fails.
    let (local range_check_ptr, local positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.position_id,
        request_public_key=tx.public_key,
        collateral_delta=-tx.amount,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=batch_config.general_config)
    if tx.is_valid != 0:
        assert_success(return_code)
    else:
        # Validate that the transition could not be completed. The types of failures that
        # update_position_in_dict fails on are the types of failures that an invalid forced action
        # can fail on.
        assert_not_equal(return_code, PerpetualErrorCode.SUCCESS)
    end

    let (local carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time)

    # Write the forced action to output.
    let forced_action : ForcedAction* = outputs.forced_actions_ptr
    assert forced_action.forced_type = ForcedActionType.FORCED_WITHDRAWAL
    let (forced_withdrawal_action) = forced_withdrawal_action_new(
        public_key=tx.public_key, position_id=tx.position_id, amount=tx.amount)
    assert forced_action.forced_action = cast(forced_withdrawal_action, felt*)

    if tx.is_valid != 0:
        # Also output a modification.
        tempvar modification : Modification* = outputs.modifications_ptr
        assert modification.public_key = tx.public_key
        assert modification.position_id = tx.position_id
        assert modification.biased_delta = AMOUNT_UPPER_BOUND - tx.amount
        tempvar modifications_ptr = modification + Modification.SIZE
    else:
        tempvar modifications_ptr = outputs.modifications_ptr
    end

    let (outputs) = perpetual_outputs_new(
        modifications_ptr=modifications_ptr,
        forced_actions_ptr=outputs.forced_actions_ptr + ForcedAction.SIZE,
        conditions_ptr=outputs.conditions_ptr,
        funding_indices_table_ptr=outputs.funding_indices_table_ptr)
    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
