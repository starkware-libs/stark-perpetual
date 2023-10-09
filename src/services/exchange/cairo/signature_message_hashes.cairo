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
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.memcpy import memcpy

const ORDER_TYPE_UPPER_BOUND = 2 ** 10;
const LIMIT_ORDER_WITH_FEES = 3;
const TRANSFER_ORDER_TYPE = 4;
const CONDITIONAL_TRANSFER_ORDER_TYPE = 5;
const MULTI_ASSET_OFFCHAIN_ORDER_TYPE = 6;
const MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND = 2 ** 12;
const N_CONDITIONS_UPPER_BOUND = 2 ** 12;
const PADDING_NUMERATOR = 2 ** 251;

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
    const PADDING = PADDING_NUMERATOR / (
        ORDER_TYPE_UPPER_BOUND * VAULT_ID_UPPER_BOUND * VAULT_ID_UPPER_BOUND *
        VAULT_ID_UPPER_BOUND * EXPIRATION_TIMESTAMP_UPPER_BOUND
    );
    %{
        # If this changes update the function docstring.
        assert ids.PADDING == 2 ** 17
    %}
    let packed_message1 = packed_message1 * PADDING;

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
    const PADDING = PADDING_NUMERATOR / (
        ORDER_TYPE_UPPER_BOUND * AMOUNT_UPPER_BOUND * AMOUNT_UPPER_BOUND *
        EXPIRATION_TIMESTAMP_UPPER_BOUND
    );
    %{
        # If this changes update the function docstring.
        assert ids.PADDING == 2 ** 81
    %}
    let packed_message1 = packed_message1 * PADDING;
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

// Append `elem` to `output_array` and return a pointer 1 past `output_array`.
func append{output_array: felt*}(elem: felt) {
    assert output_array[0] = elem;
    let output_array = output_array + 1;
    return ();
}

// Copies `len` field elements from `src` to `output_array`. Returns a pointer to one past the last
// element in the updated array.
func append_all{output_array: felt*}(src: felt*, len) {
    memcpy(dst=output_array, src=src, len=len);
    let output_array = output_array + len;
    return ();
}

// Assumptions:
// * Each element of `indices` is 12b in size. Each element represents an index in
//     `MultiAssetOrder.receive`. `multi_asset_order_hash` assumes that `n_receive` is less than
//     2**12.
// * len <= 20: The maximum number of indices to pack is generated by `num_indices_to_pack`.
// * msg is initially set to 0.
// Altogether these 3 assumptions show that `msg` will not overflow a single felt.
func pack_third_party_indices_inner(indices: felt*, len, msg) -> (packed_message: felt) {
    if (len == 0) {
        return (packed_message=msg);
    }

    let msg1 = msg * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + indices[0];
    let (msg2) = pack_third_party_indices_inner(indices=indices + 1, len=len - 1, msg=msg1);
    return (packed_message=msg2);
}

// Used to pack a single felt with up to 20 indices.
func pack_third_party_indices(indices: felt*, len) -> (packed_message: felt) {
    let (packed_msg) = pack_third_party_indices_inner(indices=indices, len=len, msg=0);
    return (packed_message=packed_msg);
}

func num_indices_to_pack{range_check_ptr}(n_third_party) -> (pack_len: felt) {
    const MAX_INDICES_PACKED = 20;
    %{
        assert 2**12 == ids.MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND
        assert 251 // 12 == ids.MAX_INDICES_PACKED
    %}

    let small_arr = is_le(n_third_party, MAX_INDICES_PACKED);
    if (small_arr == TRUE) {
        return (pack_len=n_third_party);
    } else {
        return (pack_len=MAX_INDICES_PACKED);
    }
}

// Each index for receptions to third parties can be up to 12b. Therefore we can pack 20 of them
// per felt.
func append_third_party_indices{range_check_ptr, output_array: felt*}(
    len: felt, third_party_indices: felt*
) {
    if (len == 0) {
        return ();
    }

    alloc_locals;
    let (pack_len) = num_indices_to_pack(n_third_party=len);
    let remaining = len - pack_len;
    let (packed_indices) = pack_third_party_indices(indices=third_party_indices, len=pack_len);
    append(packed_indices);
    append_third_party_indices(len=remaining, third_party_indices=third_party_indices + pack_len);
    return ();
}

// Vault ID and amount are fields of size 64b, which means we can pack up to 3 into a single felt.
func append_vaults_and_amounts{output_array: felt*}(
    vaults_and_amounts_len: felt, vaults_and_amounts: felt*
) {
    static_assert AMOUNT_UPPER_BOUND == 2 ** 64;
    static_assert VAULT_ID_UPPER_BOUND == 2 ** 64;

    if (vaults_and_amounts_len == 0) {
        return ();
    }
    if (vaults_and_amounts_len == 1) {
        return append(elem=vaults_and_amounts[0]);
    }
    if (vaults_and_amounts_len == 2) {
        let packed_message = vaults_and_amounts[0];
        let packed_message = packed_message * AMOUNT_UPPER_BOUND + vaults_and_amounts[1];
        return append(elem=packed_message);
    }

    let packed_message = vaults_and_amounts[0];
    let packed_message = packed_message * AMOUNT_UPPER_BOUND + vaults_and_amounts[1];
    let packed_message = packed_message * AMOUNT_UPPER_BOUND + vaults_and_amounts[2];
    append(elem=packed_message);

    append_vaults_and_amounts(
        vaults_and_amounts_len=vaults_and_amounts_len - 3, vaults_and_amounts=vaults_and_amounts + 3
    );
    return ();
}

func vault_info_to_arrays_inner{
    vaults_and_amounts: felt*, assets: felt*, third_party_keys: felt*, third_party_indices: felt*
}(signer_key: felt, index: felt, n_vault_info: felt, vault_info: VaultInfo*) {
    alloc_locals;
    if (n_vault_info == index) {
        return ();
    }

    let info: VaultInfo = vault_info[index];
    append{output_array=assets}(elem=info.asset_id);
    append{output_array=vaults_and_amounts}(elem=info.vault_id);
    append{output_array=vaults_and_amounts}(elem=info.amount);
    if (info.public_key != signer_key) {
        append{output_array=third_party_indices}(elem=index);
        append{output_array=third_party_keys}(elem=info.public_key);
        vault_info_to_arrays_inner(
            signer_key=signer_key, index=index + 1, n_vault_info=n_vault_info, vault_info=vault_info
        );
        return ();
    }

    vault_info_to_arrays_inner(
        signer_key=signer_key, index=index + 1, n_vault_info=n_vault_info, vault_info=vault_info
    );
    return ();
}

// Take all entries in `vault_info` and group the fields into:
// - vaults_and_amounts - fields of size 64b.
// - assets - fields that require a full felt each.
// - third_party_keys - keys from VaultInfos that target a vault not owned by `signer_key`.
//     Requires a full felt.
// - third_party_indices - indices in `vault_info` that third party vaults are found at. 12b each.
func vault_info_to_arrays{
    vaults_and_amounts: felt*, assets: felt*, third_party_keys: felt*, third_party_indices: felt*
}(signer_key: felt, n_vault_info: felt, vault_info: VaultInfo*) {
    vault_info_to_arrays_inner(
        signer_key=signer_key, index=0, n_vault_info=n_vault_info, vault_info=vault_info
    );
    return ();
}

// multi_asset_order_hash:
// Computes the hash of a multi asset order request.
//
// Relevant field sizes:
// 1. condition - 251b
// 2. public_key - 251b
// 3. asset_id - 251b
// 4. vault_id - 64b
// 5. amount - 64b
// 6. n_give, n_receive, n_conditions - 12b
//
// Fields with variable lengths: give, receive, conditions.
//
// We linearize the `give` and `receive` fields into arrays of felts as follows:
// 1. Create 4 arrays: `vaults_and_amounts`, `assets`, `third_party_keys`, and
//    `third_party_indices`.
// 2. Iterate through `receive` appending `vault_id` then `amount` to `vaults_and_amounts` and
//    `asset_id` to `assets`. If a reception is sent to a vault that is not owned by the signer of
//    this order, then add this public key to `third_party_keys` and its index in the `receive`
//    array to `third_party_indices`.
// 3. Iterate through `give`, appending `vault_id` and `amount` to `vaults_and_amounts` and
//    `asset_id` to `assets`. Note that all give elements must be sent from vaults owned by the
//    order's `public_key` and so a valid order will not have any third party keys in the give list.
// 4. Due to the size of `vault_id` and `amount` we can pack them 3 per felt. This creates
//    `packed_vaults_and_amounts`.
// 5. Due to the maximum length of `receive`, we can pack 20 indices per felt from
//    `third_party_indices`.
//
// Hashing:
// w1 = h(h(h(condition[0], condition[1]), ...), condition[N])
// w2 = h(h(h(w1, assets[0]), ...), assets[N])
// w3 = h(h(h(w2, third_party_keys[0]), ...), third_party_keys[N])
// w4 = h(h(h(w3, packed_vaults_and_amounts[0]), ...), packed_vaults_and_amounts[N])
// w5 = h(h(h(w4, packed_third_party_indices[0]), ...), packed_third_party_indices[N])
// w6 = h(w5, packed_metadata)
//
// All of the static size fields can be packed together into a single felt:
// packed_metadata = order_type 0x6 (10b) || nonce (32b) || expiration_timestamp (32b)
//      || n_give (12b) || n_receive (12b) || n_third_party_receive (12b) || n_conditions (12b)
//      || system_id (126b) || padding (3)
// The packed_metada describes the length of all arrays in the hash chain:
// - condition: n_conditions
// - assets: n_receive + n_give
// - third_party_keys: n_third_party_receive
// - packed_vaults_and_amounts: 2 * n_receive + 2 * n_give
// - packed_third_party_indices: ceil(n_third_party_receive / 20)
//
// Assumptions:
// * 0 <= nonce < NONCE_UPPER_BOUND
// * 0 <= vault_ids < VAULT_ID_UPPER_BOUND
// * 0 <= amounts < AMOUNT_UPPER_BOUND
// * 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND.
// * All public_keys in `order.give` match `order.base.public_key`.
func multi_asset_order_hash{range_check_ptr, hash_ptr: HashBuiltin*}(order: MultiAssetOrder*) -> (
    order_hash: felt
) {
    alloc_locals;

    // Arrays which hold the values taken from the give/receive arrays.
    let (vaults_and_amounts_start: felt*) = alloc();
    let vaults_and_amounts = vaults_and_amounts_start;
    let (assets_start: felt*) = alloc();
    let assets = assets_start;
    let (third_party_keys_start: felt*) = alloc();
    let third_party_keys = third_party_keys_start;
    let (third_party_indices_start: felt*) = alloc();
    let third_party_indices = third_party_indices_start;

    vault_info_to_arrays{
        vaults_and_amounts=vaults_and_amounts,
        assets=assets,
        third_party_keys=third_party_keys,
        third_party_indices=third_party_indices,
    }(signer_key=order.base.public_key, n_vault_info=order.n_receive, vault_info=order.receive);
    vault_info_to_arrays{
        vaults_and_amounts=vaults_and_amounts,
        assets=assets,
        third_party_keys=third_party_keys,
        third_party_indices=third_party_indices,
    }(signer_key=order.base.public_key, n_vault_info=order.n_give, vault_info=order.give);
    let n_third_party = third_party_indices - third_party_indices_start;

    // Convert into a single array of felts to hash.
    let (felts_to_hash_start: felt*) = alloc();
    let felts_to_hash = felts_to_hash_start;
    append_all{output_array=felts_to_hash}(src=order.conditions, len=order.n_conditions);
    append_all{output_array=felts_to_hash}(src=assets_start, len=order.n_receive + order.n_give);
    append_all{output_array=felts_to_hash}(src=third_party_keys_start, len=n_third_party);
    append_vaults_and_amounts{output_array=felts_to_hash}(
        vaults_and_amounts_len=2 * order.n_receive + 2 * order.n_give,
        vaults_and_amounts=vaults_and_amounts_start,
    );
    append_third_party_indices{output_array=felts_to_hash}(
        len=n_third_party, third_party_indices=third_party_indices_start
    );

    let packed_metadata = MULTI_ASSET_OFFCHAIN_ORDER_TYPE;
    let packed_metadata = packed_metadata * NONCE_UPPER_BOUND + order.base.nonce;
    let packed_metadata = (
        packed_metadata * EXPIRATION_TIMESTAMP_UPPER_BOUND + order.base.expiration_timestamp
    );
    let packed_metadata = (
        packed_metadata * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + order.n_give
    );
    let packed_metadata = (
        packed_metadata * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + order.n_receive
    );
    let packed_metadata = (
        packed_metadata * MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND + n_third_party
    );
    let packed_metadata = (packed_metadata * N_CONDITIONS_UPPER_BOUND + order.n_conditions);
    let packed_metadata = packed_metadata * SYSTEM_ID_UPPER_BOUND + order.system_id;
    const PADDING = PADDING_NUMERATOR / (
        ORDER_TYPE_UPPER_BOUND * NONCE_UPPER_BOUND * EXPIRATION_TIMESTAMP_UPPER_BOUND *
        MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND *
        MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND *
        MULTI_ASSET_ORDER_LIST_FIELD_SIZE_UPPER_BOUND * N_CONDITIONS_UPPER_BOUND *
        SYSTEM_ID_UPPER_BOUND
    );
    %{
        # If this changes update the function docstring.
        assert ids.PADDING == 2 ** 3
    %}
    let packed_metadata = packed_metadata * PADDING;

    // Since we use `hash_felts_no_padding` we need to put the `packed_metadata` field, which
    // includes the lengths of the variable size fields, at the end of the hash_chain.
    //
    // See hash_state.hash_felts for why `packed_metadata` must be the outermost value.
    append{output_array=felts_to_hash}(elem=packed_metadata);
    let n_felts = felts_to_hash - felts_to_hash_start;
    let (msg) = hash_felts_no_padding(
        data_ptr=felts_to_hash_start + 1,
        data_length=n_felts - 1,
        initial_hash=felts_to_hash_start[0],
    );
    return (order_hash=msg);
}
