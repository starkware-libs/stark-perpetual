from services.exchange.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND, EXPIRATION_TIMESTAMP_UPPER_BOUND, NONCE_UPPER_BOUND, VAULT_ID_UPPER_BOUND)
from services.exchange.cairo.order import OrderBase
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2

const LIMIT_ORDER_WITH_FEES = 3
const TRANSFER_ORDER_TYPE = 4
const CONDITIONAL_TRANSFER_ORDER_TYPE = 5

struct ExchangeLimitOrder:
    member base : OrderBase*
    member amount_buy : felt
    member amount_sell : felt
    member amount_fee : felt
    member asset_id_buy : felt
    member asset_id_sell : felt
    member asset_id_fee : felt
    member vault_buy : felt
    member vault_sell : felt
    member vault_fee : felt
end

# limit_order_hash:
# Computes the hash of a limit order.
#
# The hash is defined as h(h(h(h(w1, w2), w3), w4), w5) where h is
# Starkware's Pedersen hash function and w1,...w5 are as follows:
# w1= token_sell
# w2= token_buy
# w3= token_fee
# w4= amount_sell (64 bit) || amount_buy (64 bit) || amount_fee (64 bit) || nonce (32 bit)
# w5= 0x3 (10 bit) || vault_fee (64 bit) || vault_sell (64 bit) || vault_buy (64 bit)
#    || expiration_timestamp (32 bit) || 0 (17 bit)
#
# Assumptions:
# amount_sell, amount_buy, amount_fee < AMOUNT_UPPER_BOUND
# nonce < NONCE_UPPER_BOUND
# vault_sell, vault_buy, vault_fee < VAULT_ID_UPPER_BOUND
# expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND
func limit_order_hash{pedersen_ptr : HashBuiltin*}(limit_order : ExchangeLimitOrder*) -> (
        limit_order_hash):
    let (msg) = hash2{hash_ptr=pedersen_ptr}(
        x=limit_order.asset_id_sell, y=limit_order.asset_id_buy)

    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=limit_order.asset_id_fee)

    let packed_message0 = limit_order.amount_sell
    let packed_message0 = packed_message0 * AMOUNT_UPPER_BOUND + limit_order.amount_buy
    let packed_message0 = packed_message0 * AMOUNT_UPPER_BOUND + limit_order.amount_fee

    let packed_message0 = packed_message0 * NONCE_UPPER_BOUND + limit_order.base.nonce
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message0)

    let packed_message1 = LIMIT_ORDER_WITH_FEES
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_fee
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_sell
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_buy
    let packed_message1 = packed_message1 * EXPIRATION_TIMESTAMP_UPPER_BOUND +
        limit_order.base.expiration_timestamp
    let packed_message1 = packed_message1 * %[2**17%]  # Padding.

    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message1)

    return (limit_order_hash=msg)
end

struct ExchangeTransfer:
    member base : OrderBase*
    # sender_public_key = base.public_key.
    member sender_vault_id : felt
    member receiver_public_key : felt
    member receiver_vault_id : felt
    member amount : felt
    member asset_id : felt
    member src_fee_vault_id : felt
    member asset_id_fee : felt
    member max_amount_fee : felt
end

# transfer_hash:
# Computes the hash of (possibly conditional) transfer request.
#
# The hash is defined as h(h(h(h(w1, w2), w3), w4), w5) for a normal transfer,
# where h is Starkware's Pedersen hash function and:
#   w1 = asset_id
#   w2 = asset_id_fee
#   w3 = receiver_public_key
#   w4 = sender_vault_id (64 bit) || receiver_vault_id (64 bit)
#       || src_fee_vault_id (64 bit) || nonce (32 bit)
#   w5 = 0x4 (10 bit) || amount (64 bit) || max_amount_fee (64 bit) || expiration_timestamp (32 bit)
#       || 0 (81 bit)
#  where nonce and expiration_timestamp are under ExchangeTransfer.base.
#
# In case of a conditional transfer the hash is defined as h(h(h(w1, condition), w2), w3*) where
# w3* is the same as w3 except for the first element replaced with 0x5 (instead of 0x4).
#
# Assumptions:
# 0 <= nonce < NONCE_UPPER_BOUND
# 0 <= sender_vault_id, receiver_vault_id, src_fee_vault_id < VAULT_ID_UPPER_BOUND
# 0 <= amount, max_amount_fee < AMOUNT_UPPER_BOUND
# 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
func transfer_hash{pedersen_ptr : HashBuiltin*}(transfer : ExchangeTransfer*, condition : felt) -> (
        transfer_hash):
    alloc_locals
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=transfer.asset_id, y=transfer.asset_id_fee)
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=transfer.receiver_public_key)

    # Add condition to the signature hash if exists.
    if condition != 0:
        let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=condition)
    end

    # The sender is the one that pays the fee.
    let src_fee_vault_id = transfer.sender_vault_id
    let packed_message0 = transfer.sender_vault_id
    let packed_message0 = packed_message0 * VAULT_ID_UPPER_BOUND + transfer.receiver_vault_id
    let packed_message0 = packed_message0 * VAULT_ID_UPPER_BOUND + src_fee_vault_id
    let packed_message0 = packed_message0 * NONCE_UPPER_BOUND + transfer.base.nonce

    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message0)

    if condition == 0:
        # Normal Transfer.
        tempvar packed_message1 = TRANSFER_ORDER_TYPE
    else:
        # Conditional transfer.
        tempvar packed_message1 = CONDITIONAL_TRANSFER_ORDER_TYPE
    end
    let packed_message1 = packed_message1 * AMOUNT_UPPER_BOUND + transfer.amount
    let packed_message1 = packed_message1 * AMOUNT_UPPER_BOUND + transfer.max_amount_fee
    let packed_message1 = (
        packed_message1 * EXPIRATION_TIMESTAMP_UPPER_BOUND + transfer.base.expiration_timestamp)
    let packed_message1 = packed_message1 * %[2**81%]  # Padding.
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message1)
    return (transfer_hash=msg)
end
