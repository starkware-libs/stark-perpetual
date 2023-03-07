from services.exchange.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND,
    EXPIRATION_TIMESTAMP_UPPER_BOUND,
    NONCE_UPPER_BOUND,
    SYSTEM_ID_UPPER_BOUND,
    VAULT_ID_UPPER_BOUND,
)
from services.exchange.cairo.order import OrderBase
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.hash_state import hash_felts_no_padding
from starkware.cairo.common.memcpy import memcpy

const LIMIT_ORDER_WITH_FEES = 3;
const TRANSFER_ORDER_TYPE = 4;
const CONDITIONAL_TRANSFER_ORDER_TYPE = 5;
const MULTI_ASSET_OFFCHAIN_ORDER_TYPE = 6;
const MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND = 2 ** 8;

struct ExchangeLimitOrder {
    base: OrderBase*,
    amount_buy: felt,
    amount_sell: felt,
    amount_fee: felt,
    asset_id_buy: felt,
    asset_id_sell: felt,
    asset_id_fee: felt,
    vault_buy: felt,
    vault_sell: felt,
    vault_fee: felt,
}

// limit_order_hash:
// Computes the hash of a limit order.
//
// The hash is defined as h(h(h(h(w1, w2), w3), w4), w5) where h is
// Starkware's Pedersen hash function and w1,...w5 are as follows:
// w1= token_sell
// w2= token_buy
// w3= token_fee
// w4= amount_sell (64 bit) || amount_buy (64 bit) || amount_fee (64 bit) || nonce (32 bit)
// w5= 0x3 (10 bit) || vault_fee (64 bit) || vault_sell (64 bit) || vault_buy (64 bit)
//    || expiration_timestamp (32 bit) || 0 (17 bit)
//
// Assumptions:
// amount_sell, amount_buy, amount_fee < AMOUNT_UPPER_BOUND
// nonce < NONCE_UPPER_BOUND
// vault_sell, vault_buy, vault_fee < VAULT_ID_UPPER_BOUND
// expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
func limit_order_hash{pedersen_ptr: HashBuiltin*}(limit_order: ExchangeLimitOrder*) -> (
    limit_order_hash: felt
) {
    let (msg) = hash2{hash_ptr=pedersen_ptr}(
        x=limit_order.asset_id_sell, y=limit_order.asset_id_buy
    );

    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=limit_order.asset_id_fee);

    let packed_message0 = limit_order.amount_sell;
    let packed_message0 = packed_message0 * AMOUNT_UPPER_BOUND + limit_order.amount_buy;
    let packed_message0 = packed_message0 * AMOUNT_UPPER_BOUND + limit_order.amount_fee;

    let packed_message0 = packed_message0 * NONCE_UPPER_BOUND + limit_order.base.nonce;
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message0);

    let packed_message1 = LIMIT_ORDER_WITH_FEES;
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_fee;
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_sell;
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_buy;
    let packed_message1 = packed_message1 * EXPIRATION_TIMESTAMP_UPPER_BOUND +
        limit_order.base.expiration_timestamp;
    let packed_message1 = packed_message1 * (2 ** 17);  // Padding.

    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message1);

    return (limit_order_hash=msg);
}

struct ExchangeTransfer {
    base: OrderBase*,
    // sender_public_key = base.public_key.
    sender_vault_id: felt,
    receiver_public_key: felt,
    receiver_vault_id: felt,
    amount: felt,
    asset_id: felt,
    src_fee_vault_id: felt,
    asset_id_fee: felt,
    max_amount_fee: felt,
}

// transfer_hash:
// Computes the hash of (possibly conditional) transfer request.
//
// The hash is defined as h(h(h(h(w1, w2), w3), w4), w5) for a normal transfer,
// where h is Starkware's Pedersen hash function and:
//   w1 = asset_id
//   w2 = asset_id_fee
//   w3 = receiver_public_key
//   w4 = sender_vault_id (64 bit) || receiver_vault_id (64 bit)
//       || src_fee_vault_id (64 bit) || nonce (32 bit)
//   w5 = 0x4 (10 bit) || amount (64 bit) || max_amount_fee (64 bit)
//       || expiration_timestamp (32 bit) || 0 (81 bit)
//  where nonce and expiration_timestamp are under ExchangeTransfer.base.
//
// In case of a conditional transfer the hash is defined as h(h(h(w1, condition), w2), w3*) where
// w3* is the same as w3 except for the first element replaced with 0x5 (instead of 0x4).
//
// Assumptions:
// 0 <= nonce < NONCE_UPPER_BOUND
// 0 <= sender_vault_id, receiver_vault_id, src_fee_vault_id < VAULT_ID_UPPER_BOUND
// 0 <= amount, max_amount_fee < AMOUNT_UPPER_BOUND
// 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
func transfer_hash{pedersen_ptr: HashBuiltin*}(transfer: ExchangeTransfer*, condition: felt) -> (
    transfer_hash: felt
) {
    alloc_locals;
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=transfer.asset_id, y=transfer.asset_id_fee);
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=transfer.receiver_public_key);

    // Add condition to the signature hash if exists.
    if (condition != 0) {
        let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=condition);
    }

    let packed_message0 = transfer.sender_vault_id;
    let packed_message0 = packed_message0 * VAULT_ID_UPPER_BOUND + transfer.receiver_vault_id;
    let packed_message0 = packed_message0 * VAULT_ID_UPPER_BOUND + transfer.src_fee_vault_id;
    let packed_message0 = packed_message0 * NONCE_UPPER_BOUND + transfer.base.nonce;

    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message0);

    if (condition == 0) {
        // Normal Transfer.
        tempvar packed_message1 = TRANSFER_ORDER_TYPE;
    } else {
        // Conditional transfer.
        tempvar packed_message1 = CONDITIONAL_TRANSFER_ORDER_TYPE;
    }
    let packed_message1 = packed_message1 * AMOUNT_UPPER_BOUND + transfer.amount;
    let packed_message1 = packed_message1 * AMOUNT_UPPER_BOUND + transfer.max_amount_fee;
    let packed_message1 = (
        packed_message1 * EXPIRATION_TIMESTAMP_UPPER_BOUND + transfer.base.expiration_timestamp
    );
    let packed_message1 = packed_message1 * (2 ** 81);  // Padding.
    let (msg) = hash2{hash_ptr=pedersen_ptr}(x=msg, y=packed_message1);
    return (transfer_hash=msg);
}

// Order of fields matters for validations (find_element).
struct VaultInfo {
    vault_id: felt,
    public_key: felt,
    asset_id: felt,
    amount: felt,
}

struct MultiAssetOrder {
    base: OrderBase*,
    system_id: felt,
    n_give: felt,
    give: VaultInfo*,
    n_receive: felt,
    receive: VaultInfo*,
    n_conditions: felt,
    conditions: felt*,
}

// Append `elem` to `array` and return a pointer 1 past `array`.
func append(array: felt*, elem: felt) -> (end: felt*) {
    assert array[0] = elem;
    return (end=array + 1);
}

// Copies len field elements from src to dst. Returns a pointer to one past the last element in the
// updated dst array.
func append_all(dst: felt*, src: felt*, len) -> (dst_end: felt*) {
    memcpy(dst=dst, src=src, len=len);
    return (dst_end=dst + len);
}

// Vault ID and amount are fields of size 64b, which means we can pack up to 3 into a single felt.
func pack_and_append_vaults_and_amounts(
    dst: felt*, vaults_and_amounts_len: felt, vaults_and_amounts: felt*
) -> (dst_end: felt*) {
    static_assert AMOUNT_UPPER_BOUND == 2 ** 64;
    static_assert VAULT_ID_UPPER_BOUND == 2 ** 64;

    if (vaults_and_amounts_len == 0) {
        return (dst_end=dst);
    }
    if (vaults_and_amounts_len == 1) {
        let (end) = append(array=dst, elem=vaults_and_amounts[0]);
        return (dst_end=end);
    }
    if (vaults_and_amounts_len == 2) {
        let packed_message = vaults_and_amounts[0];
        let packed_message = packed_message * AMOUNT_UPPER_BOUND + vaults_and_amounts[1];
        let (end) = append(array=dst, elem=packed_message);
        return (dst_end=end);
    }

    let packed_message = vaults_and_amounts[0];
    let packed_message = packed_message * AMOUNT_UPPER_BOUND + vaults_and_amounts[1];
    let packed_message = packed_message * AMOUNT_UPPER_BOUND + vaults_and_amounts[2];
    let (end) = append(array=dst, elem=packed_message);

    let (end) = pack_and_append_vaults_and_amounts(
        dst=end,
        vaults_and_amounts_len=vaults_and_amounts_len - 3,
        vaults_and_amounts=vaults_and_amounts + 3,
    );
    return (dst_end=end);
}

// Take all entries in `vault_info` and group the fields into either:
// - vaults_and_amounts - fields of size 64b.
// - assets_and_keys - fields which require a full felt each.
//
// Returns pointers to the end of the output arrays.
func vault_info_to_arrays(
    n_vault_info: felt,
    vault_info: VaultInfo*,
    vaults_and_amounts: felt*,
    assets_and_keys: felt*,
    include_key: felt,
) -> (vaults_and_amounts_end: felt*, assets_and_keys_end: felt*) {
    alloc_locals;
    if (n_vault_info == 0) {
        return (vaults_and_amounts_end=vaults_and_amounts, assets_and_keys_end=assets_and_keys);
    }

    let info: VaultInfo = vault_info[0];
    if (include_key == TRUE) {
        let (end) = append(array=assets_and_keys, elem=info.public_key);
        tempvar assets_and_keys_end = end;
    } else {
        tempvar assets_and_keys_end = assets_and_keys;
    }
    let (assets_and_keys_end) = append(array=assets_and_keys_end, elem=info.asset_id);
    let (vaults_and_amounts_end) = append(array=vaults_and_amounts, elem=info.vault_id);
    let (vaults_and_amounts_end) = append(array=vaults_and_amounts_end, elem=info.amount);

    let (vaults_and_amounts_end, assets_and_keys_end) = vault_info_to_arrays(
        n_vault_info=n_vault_info - 1,
        vault_info=vault_info + VaultInfo.SIZE,
        vaults_and_amounts=vaults_and_amounts_end,
        assets_and_keys=assets_and_keys_end,
        include_key=include_key,
    );

    return (vaults_and_amounts_end=vaults_and_amounts_end, assets_and_keys_end=assets_and_keys_end);
}

// multi_asset_order_hash:
// Computes the hash of a multi asset order request.
//
// All of the static size fields can be packed together into a single felt:
// packed_message = order_type 0x6 (10b) || nonce (32b) || expiration_timestamp (32b) || n_give (8b)
//      || n_receive (8b) || n_conditions (8b) || system_id (126b) || padding (27b)
//
// The other fields have variable lengths: give, receive, conditions.
//
// Relevant field sizes:
// 1. condition - 251b
// 2. public_key - 251b
// 3. asset_id - 251b
// 4. vault_id - 64b
// 5. amount - 64b
//
// We linearize the `give` and `receive` fields into arrays of felts as follows:
// 1. Create 2 arrays, `vaults_and_amounts` and `assets_and_keys`.
// 2. Iterate through `receive` appending `vault_id` then `amount` to `vaults_and_amounts` and
//    `public_key` then `asset_id` to `assets_and_keys`.
// 3. Iterate through `give` appending `vault_id` then `amount` to `vaults_and_amounts` and
//    `asset_id` to `assets_and_keys`.
// 4. Due to the size of `vault_id` and `amount` we can pack them 3 per felt. This creates
//    `packed_vaults_and_amounts`.
//
// Hashing:
// w1 = h(h(h(condition[0], condition[1]), ...), condition[N])
// w2 = h(h(h(w1, assets_and_keys[0]), ...), assets_and_keys[N])
// w3 = h(h(h(w2, packed_vaults_and_amounts[0]), ...), packed_vaults_and_amounts[N])
// w4 = h(w3, packed_message)
//
// Assumptions:
// 0 <= nonce < NONCE_UPPER_BOUND
// 0 <= vault_ids < VAULT_ID_UPPER_BOUND
// 0 <= amounts < AMOUNT_UPPER_BOUND
// 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
func multi_asset_order_hash{hash_ptr: HashBuiltin*}(order: MultiAssetOrder*) -> (order_hash: felt) {
    alloc_locals;
    let packed_message = MULTI_ASSET_OFFCHAIN_ORDER_TYPE;
    let packed_message = packed_message * NONCE_UPPER_BOUND + order.base.nonce;
    let packed_message = (
        packed_message * EXPIRATION_TIMESTAMP_UPPER_BOUND + order.base.expiration_timestamp
    );
    let packed_message = (
        packed_message * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + order.n_give
    );
    let packed_message = (
        packed_message * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + order.n_receive
    );
    let packed_message = (
        packed_message * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + order.n_conditions
    );
    let packed_message = packed_message * SYSTEM_ID_UPPER_BOUND + order.system_id;
    let packed_message = packed_message * (2 ** 27);  // Padding.

    let (vaults_and_amounts: felt*) = alloc();
    let (assets_and_keys: felt*) = alloc();
    let (vaults_and_amounts_end, assets_and_keys_end) = vault_info_to_arrays(
        n_vault_info=order.n_receive,
        vault_info=order.receive,
        vaults_and_amounts=vaults_and_amounts,
        assets_and_keys=assets_and_keys,
        include_key=TRUE,
    );
    // All give keys are the same and are included once in the `packed_message`.
    let (vaults_and_amounts_end, assets_and_keys_end) = vault_info_to_arrays(
        n_vault_info=order.n_give,
        vault_info=order.give,
        vaults_and_amounts=vaults_and_amounts_end,
        assets_and_keys=assets_and_keys_end,
        include_key=FALSE,
    );
    assert (assets_and_keys_end - assets_and_keys) = 2 * order.n_receive + order.n_give;
    assert (vaults_and_amounts_end - vaults_and_amounts) = 2 * order.n_receive + 2 * order.n_give;

    // Convert into a single array of felts to hash.
    let (felts_to_hash: felt*) = alloc();
    let (felts_to_hash_end) = append_all(
        dst=felts_to_hash, src=order.conditions, len=order.n_conditions
    );
    let (felts_to_hash_end) = append_all(
        dst=felts_to_hash_end, src=assets_and_keys, len=2 * order.n_receive + order.n_give
    );
    let (felts_to_hash_end) = pack_and_append_vaults_and_amounts(
        dst=felts_to_hash_end,
        vaults_and_amounts_len=2 * order.n_receive + 2 * order.n_give,
        vaults_and_amounts=vaults_and_amounts,
    );

    // Since we use `hash_felts_no_padding` we need to put the `packed_message` field, which
    // includes the lengths of the variable size fields, as the end of the hash_chain.
    let (felts_to_hash_end) = append(array=felts_to_hash_end, elem=packed_message);
    let n_felts = felts_to_hash_end - felts_to_hash;
    let (msg) = hash_felts_no_padding(
        data_ptr=felts_to_hash + 1, data_length=n_felts - 1, initial_hash=felts_to_hash[0]
    );
    return (order_hash=msg);
}
