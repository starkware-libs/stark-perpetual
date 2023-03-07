from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.serialize import serialize_word

namespace ForcedActionType {
    const FORCED_WITHDRAWAL = 0;
    const FORCED_TRADE = 1;
}

// The parameters of any forced action that are registered onchain.
// A forced action is a transaction that is registered onchain and once it is registered it must be
// fulfilled in a set amount of time.
struct ForcedAction {
    forced_type: felt,
    forced_action: felt*,
}

// A forced action of withdrawal.
struct ForcedWithdrawalAction {
    public_key: felt,
    position_id: felt,
    amount: felt,
}

func forced_withdrawal_action_new(public_key, position_id, amount) -> (
    forced_withdrawal_action: ForcedWithdrawalAction*
) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as a ForcedWithdrawalAction object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (
        forced_withdrawal_action=cast(
            fp_val - 2 - ForcedWithdrawalAction.SIZE, ForcedWithdrawalAction*
        ),
    );
}

func forced_withdrawal_action_serialize{output_ptr: felt*}(
    forced_withdrawal_action: ForcedWithdrawalAction*
) {
    serialize_word(forced_withdrawal_action.public_key);
    serialize_word(forced_withdrawal_action.position_id);
    serialize_word(forced_withdrawal_action.amount);
    return ();
}

// A forced action of trade.
struct ForcedTradeAction {
    public_key_a: felt,
    public_key_b: felt,
    position_id_a: felt,
    position_id_b: felt,
    synthetic_asset_id: felt,
    amount_collateral: felt,
    amount_synthetic: felt,
    is_party_a_buying_synthetic: felt,
    nonce: felt,
}

func forced_trade_action_new(
    public_key_a,
    public_key_b,
    position_id_a,
    position_id_b,
    synthetic_asset_id,
    amount_collateral,
    amount_synthetic,
    is_party_a_buying_synthetic,
    nonce,
) -> (forced_trade_action: ForcedTradeAction*) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as a ForcedTradeAction object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (forced_trade_action=cast(fp_val - 2 - ForcedTradeAction.SIZE, ForcedTradeAction*));
}

func forced_trade_action_serialize{output_ptr: felt*}(forced_trade_action: ForcedTradeAction*) {
    serialize_word(forced_trade_action.public_key_a);
    serialize_word(forced_trade_action.public_key_b);
    serialize_word(forced_trade_action.position_id_a);
    serialize_word(forced_trade_action.position_id_b);
    serialize_word(forced_trade_action.synthetic_asset_id);
    serialize_word(forced_trade_action.amount_collateral);
    serialize_word(forced_trade_action.amount_synthetic);
    serialize_word(forced_trade_action.is_party_a_buying_synthetic);
    serialize_word(forced_trade_action.nonce);
    return ();
}

func forced_action_serialize{output_ptr: felt*}(forced_action: ForcedAction*) {
    let forced_type = forced_action.forced_type;
    serialize_word(forced_type);
    if (forced_type == ForcedActionType.FORCED_WITHDRAWAL) {
        return forced_withdrawal_action_serialize(
            cast(forced_action.forced_action, ForcedWithdrawalAction*)
        );
    }
    if (forced_type == ForcedActionType.FORCED_TRADE) {
        return forced_trade_action_serialize(cast(forced_action.forced_action, ForcedTradeAction*));
    }

    assert 1 = 0;
    jmp rel 0;
}
