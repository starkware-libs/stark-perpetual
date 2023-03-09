from services.perpetual.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND,
    POSITIVE_AMOUNT_LOWER_BOUND,
)
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode,
    assert_success,
)
from services.perpetual.cairo.order.limit_order import LimitOrder, limit_order_hash
from services.perpetual.cairo.order.order import validate_order_and_update_fulfillment
from services.perpetual.cairo.order.validate_limit_order import validate_limit_order_fairness
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID,
    update_position_in_dict,
)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_in_range, assert_le, assert_nn_le, assert_not_equal

// Executes a limit order of one party. Each trade will invoke this function twice, once per
// each party.
// A limit order is of the form:
//   "I want to buy/sell up to 'amount_synthetic' synthetic for 'amount_collateral' collateral in
//    the ratio amount_synthetic/amount_collateral (or better) and pay at most 'amount_fee' in
//    fees."
//
// The actual amounts moved in this order are actual_collateral, actual_synthetic, actual_fee.
// The function charges a fee and adds it to fee_position.
//
// Assumption (for validate_limit_order_fairness):
//   0 <= actual_collateral < AMOUNT_UPPER_BOUND
//   0 <= actual_fee < AMOUNT_UPPER_BOUND
//   AMOUNT_UPPER_BOUND**2 <= rc_bound.
//   Fee doesn't have synthetic assets and cannot participate in an order.
func execute_limit_order(
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    batch_config: BatchConfig*,
    limit_order: LimitOrder*,
    actual_collateral,
    actual_synthetic,
    actual_fee,
) -> (
    pedersen_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
) {
    alloc_locals;
    local general_config: GeneralConfig* = batch_config.general_config;

    assert_not_equal(limit_order.position_id, general_config.fee_position_info.position_id);

    // Check that asset_id_collateral is collateral.
    %{ error_code = ids.PerpetualErrorCode.INVALID_COLLATERAL_ASSET_ID %}
    assert limit_order.asset_id_collateral = general_config.collateral_asset_info.asset_id;
    // No need to delete error code because it is changed in the next line.

    // 0 < limit_order.amount_collateral < AMOUNT_UPPER_BOUND.
    // 0 <= limit_order.amount_fee < AMOUNT_UPPER_BOUND.
    // Note that limit_order.amount_synthetic is checked by validate_order_and_update_fulfillment.
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_POSITIVE_AMOUNT %}
    assert_in_range{range_check_ptr=range_check_ptr}(
        limit_order.amount_collateral, POSITIVE_AMOUNT_LOWER_BOUND, AMOUNT_UPPER_BOUND
    );
    %{ del error_code %}
    assert_nn_le{range_check_ptr=range_check_ptr}(limit_order.amount_fee, AMOUNT_UPPER_BOUND - 1);

    // actual_synthetic > 0. To prevent replay.
    // Note that actual_synthetic < AMOUNT_UPPER_BOUND is checked in
    // validate_order_and_update_fulfillment.
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_POSITIVE_AMOUNT %}
    assert_le{range_check_ptr=range_check_ptr}(POSITIVE_AMOUNT_LOWER_BOUND, actual_synthetic);
    %{ del error_code %}

    let (range_check_ptr) = validate_limit_order_fairness(
        range_check_ptr=range_check_ptr,
        limit_order=limit_order,
        actual_collateral=actual_collateral,
        actual_synthetic=actual_synthetic,
        actual_fee=actual_fee,
    );

    // Note by using update_position_in_dict with limit_order.position_id we check that
    // 0 <= limit_order.position_id < 2**POSITION_TREE_HEIGHT = POSITION_ID_UPPER_BOUND.
    // The expiration_timestamp and nonce are validate in validate_order_and_update_fulfillment.
    let (message_hash) = limit_order_hash{pedersen_ptr=pedersen_ptr}(limit_order=limit_order);

    let (range_check_ptr, ecdsa_ptr, orders_dict) = validate_order_and_update_fulfillment(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        orders_dict=carried_state.orders_dict,
        message_hash=message_hash,
        order=limit_order.base,
        min_expiration_timestamp=batch_config.min_expiration_timestamp,
        update_amount=actual_synthetic,
        full_amount=limit_order.amount_synthetic,
    );

    local collateral_delta;
    local synthetic_delta;
    if (limit_order.is_buying_synthetic != 0) {
        assert collateral_delta = (-actual_collateral) - actual_fee;
        assert synthetic_delta = actual_synthetic;
    } else {
        assert collateral_delta = actual_collateral - actual_fee;
        assert synthetic_delta = -actual_synthetic;
    }

    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=general_config.fee_position_info.position_id,
        request_public_key=general_config.fee_position_info.public_key,
        collateral_delta=actual_fee,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config,
    );
    assert_success(return_code);

    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=positions_dict,
        position_id=limit_order.position_id,
        request_public_key=limit_order.base.public_key,
        collateral_delta=collateral_delta,
        synthetic_asset_id=limit_order.asset_id_synthetic,
        synthetic_delta=synthetic_delta,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config,
    );
    assert_success(return_code);

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time,
    );

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
    );
}
