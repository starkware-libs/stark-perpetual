from services.exchange.cairo.definitions.constants import VAULT_ID_UPPER_BOUND
from services.exchange.cairo.order import OrderBase
from services.exchange.cairo.signature_message_hashes import ExchangeLimitOrder
from services.exchange.cairo.signature_message_hashes import (
    limit_order_hash as exchange_limit_order_hash)
from services.perpetual.cairo.definitions.constants import POSITION_ID_UPPER_BOUND
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2

struct LimitOrder:
    member base : OrderBase*
    member amount_synthetic : felt
    member amount_collateral : felt
    member amount_fee : felt
    member asset_id_synthetic : felt
    member asset_id_collateral : felt
    member position_id : felt
    member is_buying_synthetic : felt
end

# limit_order_hash:
# Computes the hash of a limit order.
#
# The hash is defined as h(h(h(h(w1, w2), w3), w4), w5) where h is the
# starkware pedersen function and w1,...w5 are as follows:
# w1= token_sell
# w2= token_buy
# w3= token_fee
# w4= amount_sell (64 bit) || amount_buy (64 bit) || amount_fee (64 bit) || nonce (32 bit)
# w5= 0x3 (10 bit) || vault_fee_src (64 bit) || vault_sell (64 bit) || vault_buy (64 bit)
#    || expiration_timestamp (32 bit) || 0 (17 bit)
#
# Assumptions (bounds defined in services.perpetual.cairo.definitions.constants):
# amount_sell < AMOUNT_UPPER_BOUND
# amount_buy < AMOUNT_UPPER_BOUND
# amount_fee < AMOUNT_UPPER_BOUND
# nonce < NONCE_UPPER_BOUND
# position_id < POSITION_ID_UPPER_BOUND
# expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
func limit_order_hash{pedersen_ptr : HashBuiltin*}(limit_order : LimitOrder*) -> (limit_order_hash):
    alloc_locals
    static_assert POSITION_ID_UPPER_BOUND == VAULT_ID_UPPER_BOUND

    let (local exchange_limit_order : ExchangeLimitOrder*) = alloc()
    assert exchange_limit_order.base = limit_order.base
    assert exchange_limit_order.amount_fee = limit_order.amount_fee
    assert exchange_limit_order.asset_id_fee = limit_order.asset_id_collateral
    assert exchange_limit_order.vault_buy = limit_order.position_id
    assert exchange_limit_order.vault_sell = limit_order.position_id
    assert exchange_limit_order.vault_fee = limit_order.position_id

    if limit_order.is_buying_synthetic != 0:
        assert exchange_limit_order.asset_id_sell = limit_order.asset_id_collateral
        assert exchange_limit_order.asset_id_buy = limit_order.asset_id_synthetic
        assert exchange_limit_order.amount_sell = limit_order.amount_collateral
        assert exchange_limit_order.amount_buy = limit_order.amount_synthetic
    else:
        assert exchange_limit_order.asset_id_sell = limit_order.asset_id_synthetic
        assert exchange_limit_order.asset_id_buy = limit_order.asset_id_collateral
        assert exchange_limit_order.amount_sell = limit_order.amount_synthetic
        assert exchange_limit_order.amount_buy = limit_order.amount_collateral
    end

    let (limit_order_hash) = exchange_limit_order_hash(limit_order=exchange_limit_order)
    return (limit_order_hash=limit_order_hash)
end
