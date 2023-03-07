from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND, FXP_32_ONE
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.objects import FundingIndicesInfo, OraclePrices
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode,
    assert_success,
)
from services.perpetual.cairo.order.limit_order import LimitOrder
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.position.funding import position_apply_funding
from services.perpetual.cairo.position.position import Position, position_get_asset_balance
from services.perpetual.cairo.position.status import position_get_status
from services.perpetual.cairo.position.update_position import update_position
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from services.perpetual.cairo.transactions.execute_limit_order import execute_limit_order
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict import dict_update
from starkware.cairo.common.math import (
    assert_250_bit,
    assert_in_range,
    assert_nn_le,
    assert_not_equal,
)

struct Liquidate {
    liquidator_order: LimitOrder*,
    // liquidator_position_id = liquidator_order.position_id.
    liquidated_position_id: felt,
    actual_collateral: felt,
    actual_synthetic: felt,
    actual_liquidator_fee: felt,
}

func execute_liquidate(
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    batch_config: BatchConfig*,
    outputs: PerpetualOutputs*,
    tx: Liquidate*,
) -> (
    pedersen_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    outputs: PerpetualOutputs*,
) {
    alloc_locals;
    local limit_order: LimitOrder* = tx.liquidator_order;
    local general_config: GeneralConfig* = batch_config.general_config;
    local oracle_prices: OraclePrices* = carried_state.oracle_prices;
    local global_funding_indices: FundingIndicesInfo* = carried_state.global_funding_indices;
    local synthetic_asset_id = limit_order.asset_id_synthetic;

    local liquidated_position: Position*;

    local collateral_delta;
    local synthetic_delta;

    // Note that tx.actual_synthetic is checked in execute_limit_order.
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.actual_collateral, AMOUNT_UPPER_BOUND - 1);
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.actual_liquidator_fee, AMOUNT_UPPER_BOUND - 1);

    // Assert that the liquidator position and the liquidated position are distinct.
    assert_not_equal(tx.liquidator_order.position_id, tx.liquidated_position_id);

    if (limit_order.is_buying_synthetic == 0) {
        assert collateral_delta = -tx.actual_collateral;
        assert synthetic_delta = tx.actual_synthetic;
    } else {
        assert collateral_delta = tx.actual_collateral;
        assert synthetic_delta = -tx.actual_synthetic;
    }

    %{
        positions_dict = __dict_manager.get_dict(ids.carried_state.positions_dict)
        ids.liquidated_position = positions_dict[ids.tx.liquidated_position_id]
    %}

    let (range_check_ptr, liquidated_funded_position) = position_apply_funding(
        range_check_ptr=range_check_ptr,
        position=liquidated_position,
        global_funding_indices=global_funding_indices,
    );

    // Check that liquidated position is liquidatable.
    let (range_check_ptr, updated_tv, updated_tr, return_code) = position_get_status(
        range_check_ptr=range_check_ptr,
        position=liquidated_funded_position,
        oracle_prices=oracle_prices,
        general_config=general_config,
    );
    assert_success(return_code);

    // TR can be up to 2**128 and TV can be down to -2**95, Therefore we can't use assert_le.
    %{ error_code = ids.PerpetualErrorCode.UNLIQUIDATABLE_POSITION %}
    assert_250_bit{range_check_ptr=range_check_ptr}(updated_tr - (updated_tv * FXP_32_ONE + 1));
    %{ del error_code %}

    // We need to check that the synthetic balance in the liquidated position won't grow and will
    // keep the same sign.
    let (range_check_ptr, initial_liquidated_asset_balance) = position_get_asset_balance(
        range_check_ptr=range_check_ptr,
        position=liquidated_funded_position,
        asset_id=synthetic_asset_id,
    );

    %{
        error_code = \
            ids.PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_ENLARGING_SYNTHETIC_HOLDINGS
    %}
    if (limit_order.is_buying_synthetic == 0) {
        // Initial_liquidated_asset_balance <= -synthetic_delta <= 0.
        assert_nn_le{range_check_ptr=range_check_ptr}(
            synthetic_delta, -initial_liquidated_asset_balance
        );
    } else {
        // 0 <= -synthetic_delta <= initial_liquidated_asset_balance.
        assert_nn_le{range_check_ptr=range_check_ptr}(
            -synthetic_delta, initial_liquidated_asset_balance
        );
    }
    %{ del error_code %}

    // Updating the liquidated position.
    let (range_check_ptr, liquidated_updated_position, _, return_code) = update_position(
        range_check_ptr=range_check_ptr,
        position=liquidated_funded_position,
        request_public_key=liquidated_funded_position.public_key,
        collateral_delta=collateral_delta,
        synthetic_asset_id=synthetic_asset_id,
        synthetic_delta=synthetic_delta,
        global_funding_indices=global_funding_indices,
        oracle_prices=oracle_prices,
        general_config=general_config,
    );
    assert_success(return_code);

    let positions_dict = carried_state.positions_dict;
    dict_update{dict_ptr=positions_dict}(
        key=tx.liquidated_position_id,
        prev_value=cast(liquidated_position, felt),
        new_value=cast(liquidated_updated_position, felt),
    );

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=global_funding_indices,
        oracle_prices=oracle_prices,
        system_time=carried_state.system_time,
    );

    let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state) = execute_limit_order(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        batch_config=batch_config,
        limit_order=limit_order,
        actual_collateral=tx.actual_collateral,
        actual_synthetic=tx.actual_synthetic,
        actual_fee=tx.actual_liquidator_fee,
    );

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
    );
}
