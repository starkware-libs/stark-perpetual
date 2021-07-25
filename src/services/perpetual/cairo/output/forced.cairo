from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.serialize import serialize_word

namespace ForcedActionType:
    const FORCED_WITHDRAWAL = 0
    const FORCED_TRADE = 1
end

# The parameters of any forced action that are registered onchain.
# A forced action is a transaction that is registered onchain and once it is registered it must be
# fulfilled in a set amount of time.
struct ForcedAction:
    member forced_type : felt
    member forced_action : felt*
end

# A forced action of withdrawal.
struct ForcedWithdrawalAction:
    member public_key : felt
    member position_id : felt
    member amount : felt
end

func forced_withdrawal_action_new(public_key, position_id, amount) -> (
        forced_withdrawal_action : ForcedWithdrawalAction*):
    let (fp_val, pc_val) = get_fp_and_pc()
    return (
        forced_withdrawal_action=cast(fp_val - 2 - ForcedWithdrawalAction.SIZE, ForcedWithdrawalAction*))
end

func forced_withdrawal_action_serialize{output_ptr : felt*}(
        forced_withdrawal_action : ForcedWithdrawalAction*):
    serialize_word(forced_withdrawal_action.public_key)
    serialize_word(forced_withdrawal_action.position_id)
    serialize_word(forced_withdrawal_action.amount)
    return ()
end

# A forced action of trade.
struct ForcedTradeAction:
    member public_key_a : felt
    member public_key_b : felt
    member position_id_a : felt
    member position_id_b : felt
    member synthetic_asset_id : felt
    member amount_collateral : felt
    member amount_synthetic : felt
    member is_party_a_buying_synthetic : felt
    member nonce : felt
end

func forced_trade_action_new(
        public_key_a, public_key_b, position_id_a, position_id_b, synthetic_asset_id,
        amount_collateral, amount_synthetic, is_party_a_buying_synthetic, nonce) -> (
        forced_trade_action : ForcedTradeAction*):
    let (fp_val, pc_val) = get_fp_and_pc()
    return (forced_trade_action=cast(fp_val - 2 - ForcedTradeAction.SIZE, ForcedTradeAction*))
end

func forced_trade_action_serialize{output_ptr : felt*}(forced_trade_action : ForcedTradeAction*):
    serialize_word(forced_trade_action.public_key_a)
    serialize_word(forced_trade_action.public_key_b)
    serialize_word(forced_trade_action.position_id_a)
    serialize_word(forced_trade_action.position_id_b)
    serialize_word(forced_trade_action.synthetic_asset_id)
    serialize_word(forced_trade_action.amount_collateral)
    serialize_word(forced_trade_action.amount_synthetic)
    serialize_word(forced_trade_action.is_party_a_buying_synthetic)
    serialize_word(forced_trade_action.nonce)
    return ()
end

func forced_action_serialize{output_ptr : felt*}(forced_action : ForcedAction*):
    let forced_type = forced_action.forced_type
    serialize_word(forced_type)
    if forced_type == ForcedActionType.FORCED_WITHDRAWAL:
        return forced_withdrawal_action_serialize(
            cast(forced_action.forced_action, ForcedWithdrawalAction*))
    end
    if forced_type == ForcedActionType.FORCED_TRADE:
        return forced_trade_action_serialize(cast(forced_action.forced_action, ForcedTradeAction*))
    end

    assert 1 = 0
    jmp rel 0
end
