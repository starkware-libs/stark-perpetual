from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode, assert_success)
from services.perpetual.cairo.output.program_output import (
    Modification, PerpetualOutputs, perpetual_outputs_new)
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID, update_position_in_dict)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_nn_le

struct Deposit:
    member public_key : felt
    member position_id : felt
    member amount : felt
end

func execute_deposit(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : Deposit*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    # Check validity of deposit.
    # public_key has no constraints.
    # position_id is validated implicitly by update_position_in_dict().
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_AMOUNT %}
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount, AMOUNT_UPPER_BOUND - 1)

    %{ del error_code %}
    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.position_id,
        request_public_key=tx.public_key,
        collateral_delta=tx.amount,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=batch_config.general_config)
    assert_success(return_code)

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time)

    # Write to output.
    tempvar modification : Modification* = outputs.modifications_ptr
    assert modification.public_key = tx.public_key
    assert modification.position_id = tx.position_id
    # For explanation why we add AMOUNT_UPPER_BOUND, see Modification's documentation.
    assert modification.biased_delta = tx.amount + AMOUNT_UPPER_BOUND
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
