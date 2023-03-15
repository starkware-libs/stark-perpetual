from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND, FXP_32_ONE
from services.perpetual.cairo.definitions.objects import FundingIndicesInfo
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode,
    assert_success,
)
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.position.position import Position, position_get_asset_balance
from services.perpetual.cairo.position.status import position_get_status
from services.perpetual.cairo.position.update_position import update_position_in_dict
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_250_bit, assert_lt, assert_nn_le, assert_not_equal

struct Deleverage {
    deleveragable_position_id: felt,
    deleverager_position_id: felt,
    synthetic_asset_id: felt,
    amount_synthetic: felt,
    amount_collateral: felt,
    deleverager_is_buying_synthetic: felt,
}

func execute_deleverage(
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    batch_config: BatchConfig*,
    outputs: PerpetualOutputs*,
    tx: Deleverage*,
) -> (
    pedersen_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    outputs: PerpetualOutputs*,
) {
    alloc_locals;

    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount_synthetic, AMOUNT_UPPER_BOUND - 1);
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount_collateral, AMOUNT_UPPER_BOUND - 1);

    %{ error_code = ids.PerpetualErrorCode.SAME_POSITION_ID %}
    // Assert that the deleverager position and the deleveragable position are distinct.
    assert_not_equal(tx.deleverager_position_id, tx.deleveragable_position_id);
    %{ del error_code %}

    local global_funding_indices: FundingIndicesInfo* = carried_state.global_funding_indices;

    local deleverager_synthetic_delta;
    local deleveragable_synthetic_delta;
    local deleverager_collateral_delta;
    local deleveragable_collateral_delta;

    if (tx.deleverager_is_buying_synthetic != 0) {
        assert deleverager_synthetic_delta = tx.amount_synthetic;
        assert deleveragable_synthetic_delta = -tx.amount_synthetic;
        assert deleverager_collateral_delta = -tx.amount_collateral;
        assert deleveragable_collateral_delta = tx.amount_collateral;
    } else {
        assert deleverager_synthetic_delta = -tx.amount_synthetic;
        assert deleveragable_synthetic_delta = tx.amount_synthetic;
        assert deleverager_collateral_delta = tx.amount_collateral;
        assert deleveragable_collateral_delta = -tx.amount_collateral;
    }

    // Performing the transaction on both positions first to get the funded positions.
    let (
        range_check_ptr,
        positions_dict: DictAccess*,
        deleveragable_funded_position,
        deleveragable_updated_position,
        return_code,
    ) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.deleveragable_position_id,
        request_public_key=0,
        collateral_delta=deleveragable_collateral_delta,
        synthetic_asset_id=tx.synthetic_asset_id,
        synthetic_delta=deleveragable_synthetic_delta,
        global_funding_indices=global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=batch_config.general_config,
    );
    assert_success(return_code);

    let (
        range_check_ptr, positions_dict, deleverager_funded_position: Position*, _, return_code
    ) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=positions_dict,
        position_id=tx.deleverager_position_id,
        request_public_key=0,
        collateral_delta=deleverager_collateral_delta,
        synthetic_asset_id=tx.synthetic_asset_id,
        synthetic_delta=deleverager_synthetic_delta,
        global_funding_indices=global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=batch_config.general_config,
    );
    assert_success(return_code);

    // Validating that deleverager has enough synthetic (or minus synthetic) for the transaction.
    let (range_check_ptr, deleverager_synthetic_balance) = position_get_asset_balance(
        range_check_ptr=range_check_ptr,
        position=deleverager_funded_position,
        asset_id=tx.synthetic_asset_id,
    );

    %{
        error_code = \
            ids.PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_ENLARGING_SYNTHETIC_HOLDINGS
    %}
    if (tx.deleverager_is_buying_synthetic != 0) {
        assert_nn_le{range_check_ptr=range_check_ptr}(
            tx.amount_synthetic, -deleverager_synthetic_balance
        );
    } else {
        assert_nn_le{range_check_ptr=range_check_ptr}(
            tx.amount_synthetic, deleverager_synthetic_balance
        );
    }
    %{ del error_code %}

    // Check that deleveragable position is deleveragable.
    let (range_check_ptr, initial_tv, initial_tr, return_code) = position_get_status(
        range_check_ptr=range_check_ptr,
        position=deleveragable_funded_position,
        oracle_prices=carried_state.oracle_prices,
        general_config=batch_config.general_config,
    );
    assert_success(return_code);
    %{ error_code = ids.PerpetualErrorCode.UNDELEVERAGABLE_POSITION %}
    assert_lt{range_check_ptr=range_check_ptr}(initial_tv, 0);
    %{ del error_code %}

    // Validates that deleverage ratio for the deleverager is the maximal it can be while being
    // valid for the deleveragable. In other words, validates that if we reduce the collateral the
    // deleveragable gets from the transaction by 1, the transaction is invalid.
    // The validation that the transaction is currently valid is done in update_position_in_dict.
    let (range_check_ptr, updated_tv, updated_tr, return_code) = position_get_status(
        range_check_ptr=range_check_ptr,
        position=deleveragable_updated_position,
        oracle_prices=carried_state.oracle_prices,
        general_config=batch_config.general_config,
    );
    assert_success(return_code);
    // We want to check that (updated_tv - FXP_32_ONE) / updated_tr < initial_tv / initial_tr.
    // This condition is equivalent to the condition checked by the code below.

    // We check that updated_tv / updated_tr >= initial_tv / initial_tr in update_position_in_dict.

    // tv0 / tr0 > tv1 / tr1 <=> tv0 * tr1 > tv1 * tr0.
    // tv is 96 bit.
    // tr is 128 bit.
    // tv*tr fits in 224 bits.
    // Since tv can be negative, adding 2**224 to each side.
    %{ error_code = ids.PerpetualErrorCode.UNFAIR_DELEVERAGE %}
    assert_250_bit{range_check_ptr=range_check_ptr}(
        (initial_tv * updated_tr) - ((updated_tv - FXP_32_ONE) * initial_tr + 1)
    );
    %{ del error_code %}

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time,
    );

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
    );
}
