from services.exchange.cairo.order import OrderBase
from services.exchange.cairo.signature_message_hashes import ExchangeLimitOrder, limit_order_hash
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.set import set_add
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.dex.dex_constants import (
    BALANCE_BOUND,
    EXPIRATION_TIMESTAMP_BOUND,
    NONCE_BOUND,
    PackedOrderMsg,
)
from starkware.cairo.dex.dex_context import DexContext
from starkware.cairo.dex.fee import (
    FeeInfoExchange,
    FeeInfoUser,
    order_validate_fee,
    update_fee_vaults,
)
from starkware.cairo.dex.l1_vault_update import l1_vault_update_diff
from starkware.cairo.dex.message_hashes import order_and_transfer_hash_31
from starkware.cairo.dex.message_l1_order import L1OrderMessageOutput, serialize_l1_limit_order
from starkware.cairo.dex.vault_update import l2_vault_update_diff
from starkware.cairo.dex.verify_order_id import verify_order_id

// Compute the limit order message hash.
// A different message format is used to compute the hash depending on whether or not a fee object
// is part of the order.
func get_order_hash{pedersen_ptr: HashBuiltin*}(
    limit_order: ExchangeLimitOrder*, fee_info_exchange: FeeInfoExchange*
) -> (message_hash: felt) {
    if (fee_info_exchange != 0) {
        // Order with fee - compute limit order hash using 64 bit vault id format.
        let (message_hash_64) = limit_order_hash(limit_order=limit_order);
        return (message_hash=message_hash_64);
    }

    // Order without fee - compute limit order hash using 31 bit vault id format.
    let (message_hash_31) = order_and_transfer_hash_31{hash_ptr=pedersen_ptr}(
        order_type=PackedOrderMsg.SETTLEMENT_ORDER_TYPE,
        vault0=limit_order.vault_sell,
        vault1=limit_order.vault_buy,
        amount0=limit_order.amount_sell,
        amount1=limit_order.amount_buy,
        token0=limit_order.asset_id_sell,
        token1_or_pub_key=limit_order.asset_id_buy,
        nonce=limit_order.base.nonce,
        expiration_timestamp=limit_order.base.expiration_timestamp,
        condition=0,
    );
    return (message_hash=message_hash_31);
}

// Validate the fee taken and update the source and destination fee vaults of a limit order.
// Source vault may be an L1 or L2 vault, destination vault must be an L2 vault.
//
// Hint argument:
// fee_witness - the appropriate FeeWitness object (needed if fee_info_exchange != 0).
//   Used in update_fee_vaults.
func validate_and_update_fee_vaults{
    pedersen_ptr: HashBuiltin*, range_check_ptr, vault_dict: DictAccess*, l1_vault_dict: DictAccess*
}(
    fee_info_exchange: FeeInfoExchange*,
    use_l1_vaults,
    amount_bought,
    limit_order: ExchangeLimitOrder*,
) {
    if (fee_info_exchange == 0) {
        // When fee_info_exchange == 0 (no fee object in order), no fee is taken.
        return ();
    }

    let fee_info_user: FeeInfoUser* = alloc();
    assert fee_info_user.token_id = limit_order.asset_id_fee;
    assert fee_info_user.fee_limit = limit_order.amount_fee;
    assert fee_info_user.source_vault_id = limit_order.vault_fee;

    // Validate fee taken and update matching vaults.
    order_validate_fee(
        fee_taken=fee_info_exchange.fee_taken,
        fee_limit=fee_info_user.fee_limit,
        amount_bought=amount_bought,
        order_buy=limit_order.amount_buy,
    );
    update_fee_vaults(
        user_public_key=limit_order.base.public_key,
        fee_info_user=fee_info_user,
        fee_info_exchange=fee_info_exchange,
        use_l1_src_vault=use_l1_vaults,
    );
    return ();
}

// Update the source and destination vaults of a limit order and handles the signature verification.
// Vaults may be L1 or L2 vaults (for L1 and L2 orders respectively). In case of an L2 order the
// Signature is verified here. In case of an L1 order, the order message is written to the output
// for L1 validation.
//
// Hint argument:
// order_witness - the witness for the executed order.
func update_vaults_and_verify_signature{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    l1_order_message_ptr: L1OrderMessageOutput*,
}(
    is_l1_order,
    amount_sold,
    amount_bought,
    limit_order: ExchangeLimitOrder*,
    l1_order_message_start_ptr: L1OrderMessageOutput*,
    message_hash,
) {
    alloc_locals;
    if (is_l1_order != 0) {
        // Add the L1 order message to the messages output set. The verification of the message is
        // done in the main contract.
        let (current_order_message_ptr) = serialize_l1_limit_order(limit_order);
        let set_end_ptr: felt* = cast(l1_order_message_ptr, felt*);
        set_add{set_end_ptr=set_end_ptr}(
            set_ptr=l1_order_message_start_ptr,
            elm_size=L1OrderMessageOutput.SIZE,
            elm_ptr=current_order_message_ptr,
        );
        local l1_order_message_ptr: L1OrderMessageOutput* = cast(
            set_end_ptr, L1OrderMessageOutput*
        );

        // Update the L1 sell vault with the sold amount.
        l1_vault_update_diff(
            diff=-amount_sold,
            eth_key=limit_order.base.public_key,
            token_id=limit_order.asset_id_sell,
            vault_index=limit_order.vault_sell,
        );

        // Update the L1 buy vault with the bought amount.
        l1_vault_update_diff(
            diff=amount_bought,
            eth_key=limit_order.base.public_key,
            token_id=limit_order.asset_id_buy,
            vault_index=limit_order.vault_buy,
        );
        return ();
    }

    // L2 Order.

    // Update the vault tree with the new balance of the L2 sell vault.
    %{ vault_update_witness = order_witness.sell_witness %}
    let (range_check_ptr) = l2_vault_update_diff(
        range_check_ptr=range_check_ptr,
        diff=-amount_sold,
        stark_key=limit_order.base.public_key,
        token_id=limit_order.asset_id_sell,
        vault_index=limit_order.vault_sell,
        vault_change_ptr=vault_dict,
    );

    // Update the vault tree with the new balance of the L2 buy vault.
    %{ vault_update_witness = order_witness.buy_witness %}
    let (range_check_ptr) = l2_vault_update_diff(
        range_check_ptr=range_check_ptr,
        diff=amount_bought,
        stark_key=limit_order.base.public_key,
        token_id=limit_order.asset_id_buy,
        vault_index=limit_order.vault_buy,
        vault_change_ptr=vault_dict + DictAccess.SIZE,
    );
    let vault_dict = vault_dict + 2 * DictAccess.SIZE;

    // Signature verification.
    verify_ecdsa_signature(
        message=message_hash,
        public_key=limit_order.base.public_key,
        signature_r=limit_order.base.signature_r,
        signature_s=limit_order.base.signature_s,
    );
    return ();
}

// Executes a limit order of a single party. Each settlement will invoke this function twice, once
// per each party.
// A limit order can be described by the following statement:
//   "I want to sell a maximum of amount_sell tokens of type token_sell, and in return I expect
//   to receive at least amount_buy tokens of type token_buy (relative to the actual number of
//   tokens sold). I am willing to pay amount_fee (relative to the actual number of tokens bought)
//   for the above to be executed."
//
// The actual amounts that were transferred are amount_sold, amount_bought. The actual fee that is
// paid is fee_info_exchange.fee_taken or 0 if fee_info_exchange == 0.
//
// Hint arguments:
// * order - the order to execute.
// * order_witness - the matching OrderWitness.
// * fee_witness - a FeeWitness, required if the order includes a fee.
//
// Assumptions:
// * 0 <= amount_sold, amount_bought < BALANCE_BOUND.
// * 0 <= global_expiration_timestamp, and it has not expired yet.
func execute_limit_order(
    hash_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    limit_order: ExchangeLimitOrder*,
    l1_order_message_ptr: L1OrderMessageOutput*,
    l1_order_message_start_ptr: L1OrderMessageOutput*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    order_dict: DictAccess*,
    amount_sold,
    amount_bought,
    fee_info_exchange: FeeInfoExchange*,
    dex_context_ptr: DexContext*,
) -> (
    hash_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    l1_order_message_ptr: L1OrderMessageOutput*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    order_dict: DictAccess*,
) {
    // Local variables.
    local order_id;
    local prev_fulfilled_amount;
    local new_fulfilled_amount;
    // Indicates whether this order is an L1 order or an L2 order.
    local is_l1_order;
    %{
        from common.objects.transaction.common_transaction import OrderL1, OrderL2

        if isinstance(order, OrderL1):
            ids.is_l1_order = 1
        else:
            assert isinstance(order, OrderL2), f"Unsupported order type"
            ids.is_l1_order = 0

        ids.order_id = order.order_id
        ids.prev_fulfilled_amount = order_witness.prev_fulfilled_amount
    %}
    alloc_locals;

    let dex_context: DexContext* = dex_context_ptr;

    // Define an inclusive amount bound reference for amount range-checks.
    tempvar inclusive_amount_bound = BALANCE_BOUND - 1;

    // Check that 0 <= amount_sell < BALANCE_BOUND.
    assert [range_check_ptr] = limit_order.amount_sell;
    // Guarantee that amount_sell <= inclusive_amount_bound < BALANCE_BOUND.
    assert [range_check_ptr + 1] = inclusive_amount_bound - limit_order.amount_sell;

    // Check that 0 <= amount_buy < BALANCE_BOUND.
    assert [range_check_ptr + 2] = limit_order.amount_buy;
    // Guarantee that amount_buy <= inclusive_amount_bound < BALANCE_BOUND.
    assert [range_check_ptr + 3] = inclusive_amount_bound - limit_order.amount_buy;

    // Check that the party has not sold more than the sell amount limit specified in their order.
    new_fulfilled_amount = prev_fulfilled_amount + amount_sold;
    // Guarantee that new_fulfilled_amount <= amount_sell, which also implies that
    // amount_sold <= amount_sell.
    assert [range_check_ptr + 4] = limit_order.amount_sell - new_fulfilled_amount;

    // Check that 0 <= nonce < NONCE_BOUND.
    tempvar inclusive_nonce_bound = NONCE_BOUND - 1;
    assert [range_check_ptr + 5] = limit_order.base.nonce;
    // Guarantee that nonce <= inclusive_nonce_bound < NONCE_BOUND.
    assert [range_check_ptr + 6] = inclusive_nonce_bound - limit_order.base.nonce;

    // Check that the order has not expired yet.
    tempvar global_expiration_timestamp = dex_context.global_expiration_timestamp;
    // Guarantee that global_expiration_timestamp <= expiration_timestamp, which also implies that
    // 0 <= expiration_timestamp.
    assert [range_check_ptr + 7] = (
        limit_order.base.expiration_timestamp - global_expiration_timestamp);

    // Check that expiration_timestamp < EXPIRATION_TIMESTAMP_BOUND.
    tempvar inclusive_expiration_timestamp_bound = EXPIRATION_TIMESTAMP_BOUND - 1;
    // Guarantee that expiration_timestamp <= inclusive_expiration_timestamp_bound <
    // EXPIRATION_TIMESTAMP_BOUND.
    assert [range_check_ptr + 8] = (
        inclusive_expiration_timestamp_bound - limit_order.base.expiration_timestamp);

    // Check that the actual ratio (amount_bought / amount_sold) is better than (or equal to) the
    // requested ratio (amount_buy / amount_sell) by checking that
    // amount_sell * amount_bought >= amount_sold * amount_buy.
    assert [range_check_ptr + 9] = (
        limit_order.amount_sell * amount_bought - amount_sold * limit_order.amount_buy);

    // Update orders dict.
    let order_dict_access: DictAccess* = order_dict;
    order_id = order_dict_access.key;
    prev_fulfilled_amount = order_dict_access.prev_value;
    new_fulfilled_amount = order_dict_access.new_value;

    let range_check_ptr = range_check_ptr + 10;
    let (local message_hash) = get_order_hash{pedersen_ptr=hash_ptr}(
        limit_order=limit_order, fee_info_exchange=fee_info_exchange
    );

    %{
        # Assert previous hash computation.
        signature_message_hash = order.signature_message_hash()
        assert ids.message_hash == signature_message_hash, \
            f'Computed message hash, {ids.message_hash}, does not match the actual one: ' \
            f'{signature_message_hash}.'
    %}

    // Update sell and buy vaults and verify signature.
    update_vaults_and_verify_signature{
        pedersen_ptr=hash_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        vault_dict=vault_dict,
        l1_vault_dict=l1_vault_dict,
        l1_order_message_ptr=l1_order_message_ptr,
    }(
        is_l1_order=is_l1_order,
        amount_sold=amount_sold,
        amount_bought=amount_bought,
        limit_order=limit_order,
        l1_order_message_start_ptr=l1_order_message_start_ptr,
        message_hash=message_hash,
    );
    local ecdsa_ptr_end: SignatureBuiltin* = ecdsa_ptr;
    local l1_order_message_ptr_end: L1OrderMessageOutput* = l1_order_message_ptr;

    // Update fee vaults.
    validate_and_update_fee_vaults{
        pedersen_ptr=hash_ptr,
        range_check_ptr=range_check_ptr,
        vault_dict=vault_dict,
        l1_vault_dict=l1_vault_dict,
    }(
        fee_info_exchange=fee_info_exchange,
        use_l1_vaults=is_l1_order,
        amount_bought=amount_bought,
        limit_order=limit_order,
    );

    // Verify order id.
    verify_order_id{range_check_ptr=range_check_ptr}(message_hash=message_hash, order_id=order_id);

    return (
        hash_ptr=hash_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr_end,
        l1_order_message_ptr=l1_order_message_ptr_end,
        vault_dict=vault_dict,
        l1_vault_dict=l1_vault_dict,
        order_dict=order_dict + DictAccess.SIZE,
    );
}
