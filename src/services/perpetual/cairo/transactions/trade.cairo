from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.order.limit_order import LimitOrder
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.state.state import CarriedState
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from services.perpetual.cairo.transactions.execute_limit_order import execute_limit_order
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_nn_le, assert_not_equal

struct Trade {
    // Party A is the party that buys synthetic and party B is the party that sells synthetic.
    party_a_order: LimitOrder*,
    party_b_order: LimitOrder*,
    actual_collateral: felt,
    actual_synthetic: felt,
    actual_a_fee: felt,
    actual_b_fee: felt,
}

// Executes a trade between two parties, where both parties agree to a limit order
// and those orders match.
func execute_trade(
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    batch_config: BatchConfig*,
    outputs: PerpetualOutputs*,
    tx: Trade*,
) -> (
    pedersen_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    outputs: PerpetualOutputs*,
) {
    alloc_locals;

    let trade: Trade* = tx;

    // 0 <= trade.actual_collateral, trade.actual_a_fee, trade.actual_b_fee < AMOUNT_UPPER_BOUND.
    // Note that actual_synthetic is checked in execute_limit_order.
    assert_nn_le{range_check_ptr=range_check_ptr}(trade.actual_collateral, AMOUNT_UPPER_BOUND - 1);
    assert_nn_le{range_check_ptr=range_check_ptr}(trade.actual_a_fee, AMOUNT_UPPER_BOUND - 1);
    assert_nn_le{range_check_ptr=range_check_ptr}(trade.actual_b_fee, AMOUNT_UPPER_BOUND - 1);

    // Check that party A is buying synthetic and party B is selling synthetic.
    local buy_order: LimitOrder* = trade.party_a_order;
    assert buy_order.is_buying_synthetic = 1;

    local sell_order: LimitOrder* = trade.party_b_order;
    assert sell_order.is_buying_synthetic = 0;

    // Execute_limit_order will verify that A and B are not the fee position.
    let (
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr: SignatureBuiltin*,
        carried_state: CarriedState*,
    ) = execute_limit_order(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        batch_config=batch_config,
        limit_order=buy_order,
        actual_collateral=trade.actual_collateral,
        actual_synthetic=trade.actual_synthetic,
        actual_fee=trade.actual_a_fee,
    );

    // Check that orders match in asset id.
    assert buy_order.asset_id_synthetic = sell_order.asset_id_synthetic;

    // Check that orders' positions are distinct.
    %{ error_code = ids.PerpetualErrorCode.SAME_POSITION_ID %}
    assert_not_equal(buy_order.position_id, sell_order.position_id);
    %{ del error_code %}

    let (
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr: SignatureBuiltin*,
        carried_state: CarriedState*,
    ) = execute_limit_order(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        batch_config=batch_config,
        limit_order=sell_order,
        actual_collateral=trade.actual_collateral,
        actual_synthetic=trade.actual_synthetic,
        actual_fee=trade.actual_b_fee,
    );

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
    );
}
