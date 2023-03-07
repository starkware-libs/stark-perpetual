from services.exchange.cairo.definitions.constants import VAULT_ID_UPPER_BOUND
from services.exchange.cairo.order import OrderBase
from services.exchange.cairo.signature_message_hashes import ExchangeLimitOrder
from services.exchange.cairo.signature_message_hashes import (
    limit_order_hash as exchange_limit_order_hash,
)
from services.perpetual.cairo.definitions.constants import POSITION_ID_UPPER_BOUND
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin

struct LimitOrder {
    base: OrderBase*,
    amount_synthetic: felt,
    amount_collateral: felt,
    amount_fee: felt,
    asset_id_synthetic: felt,
    asset_id_collateral: felt,
    position_id: felt,
    is_buying_synthetic: felt,
}

// Computes the hash of a limit order.
// See limit_order_hash in services/exchange/cairo/signature_message_hashes for the hash definition.
func limit_order_hash{pedersen_ptr: HashBuiltin*}(limit_order: LimitOrder*) -> (
    limit_order_hash: felt
) {
    alloc_locals;
    static_assert POSITION_ID_UPPER_BOUND == VAULT_ID_UPPER_BOUND;

    let (local exchange_limit_order: ExchangeLimitOrder*) = alloc();
    assert exchange_limit_order.base = limit_order.base;
    assert exchange_limit_order.amount_fee = limit_order.amount_fee;
    assert exchange_limit_order.asset_id_fee = limit_order.asset_id_collateral;
    assert exchange_limit_order.vault_buy = limit_order.position_id;
    assert exchange_limit_order.vault_sell = limit_order.position_id;
    assert exchange_limit_order.vault_fee = limit_order.position_id;

    if (limit_order.is_buying_synthetic != 0) {
        assert exchange_limit_order.asset_id_sell = limit_order.asset_id_collateral;
        assert exchange_limit_order.asset_id_buy = limit_order.asset_id_synthetic;
        assert exchange_limit_order.amount_sell = limit_order.amount_collateral;
        assert exchange_limit_order.amount_buy = limit_order.amount_synthetic;
    } else {
        assert exchange_limit_order.asset_id_sell = limit_order.asset_id_synthetic;
        assert exchange_limit_order.asset_id_buy = limit_order.asset_id_collateral;
        assert exchange_limit_order.amount_sell = limit_order.amount_synthetic;
        assert exchange_limit_order.amount_buy = limit_order.amount_collateral;
    }

    let (limit_order_hash) = exchange_limit_order_hash(limit_order=exchange_limit_order);
    return (limit_order_hash=limit_order_hash);
}
