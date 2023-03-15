from services.exchange.cairo.signature_message_hashes import ExchangeTransfer, transfer_hash
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
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
    transfer_validate_fee,
    update_fee_vaults,
)
from starkware.cairo.dex.message_hashes import order_and_transfer_hash_31
from starkware.cairo.dex.vault_update import l2_vault_update_diff
from starkware.cairo.dex.verify_order_id import verify_order_id

// Executes a (conditional) transfer order.
// A (conditional) transfer order can be described by the following statement:
//   "I want to transfer exactly 'amount' tokens of type 'token' to user 'receiver_stark_key'
//   in vault 'target_vault' (only if the specified 'condition' is satisfied)".
//
// Assumptions:
// * 0 <= global_expiration_timestamp, and it has not expired yet.
func execute_transfer(
    hash_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    conditional_transfer_ptr: felt*,
    vault_dict: DictAccess*,
    order_dict: DictAccess*,
    dex_context_ptr: DexContext*,
) -> (
    hash_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    conditional_transfer_ptr: felt*,
    vault_dict: DictAccess*,
    order_dict: DictAccess*,
) {
    // Local variables.
    local transfer: ExchangeTransfer*;
    local order_id;
    local condition;
    local new_conditional_transfer_pointer: felt*;
    local with_fee;
    local range_check_ptr_before_signature;
    local final_vault_dict: DictAccess*;
    %{
        from common.objects.transaction.raw_transaction import ConditionalTransfer

        # Initialize fee related fields. Fee field is optional in transfers.
        if transfer.fee_info_user is None:
            user_fee_fields = [0, 0, 0]
            ids.with_fee = 0
        else:
            fee_info_user = transfer.fee_info_user
            user_fee_fields = [
                fee_info_user.source_vault_id, fee_info_user.token_id, fee_info_user.fee_limit]
            ids.with_fee = 1

        # Initialize transfer.
        order_base = segments.gen_arg([
            transfer.nonce, transfer.sender_public_key, transfer.expiration_timestamp,
            transfer.signature.r, transfer.signature.s
        ])
        ids.transfer = segments.gen_arg([
            order_base, transfer.sender_vault_id, transfer.receiver_public_key,
            transfer.receiver_vault_id, transfer.amount, transfer.token] + user_fee_fields)

        ids.order_id = transfer.order_id_b
        if isinstance(transfer, ConditionalTransfer):
          ids.condition = transfer.condition
        else:
          ids.condition = 0
    %}
    alloc_locals;

    let dex_context: DexContext* = dex_context_ptr;

    // Check that 0 <= amount < BALANCE_BOUND.
    tempvar inclusive_amount_bound = BALANCE_BOUND - 1;
    assert [range_check_ptr] = transfer.amount;
    // Guarantee that amount <= inclusive_amount_bound < BALANCE_BOUND.
    assert [range_check_ptr + 1] = inclusive_amount_bound - transfer.amount;

    // Check that 0 <= nonce < NONCE_BOUND.
    tempvar inclusive_nonce_bound = NONCE_BOUND - 1;
    assert [range_check_ptr + 2] = transfer.base.nonce;
    // Guarantee that nonce <= inclusive_nonce_bound < NONCE_BOUND.
    assert [range_check_ptr + 3] = inclusive_nonce_bound - transfer.base.nonce;

    // Check that the order has not expired yet.
    tempvar global_expiration_timestamp = dex_context.global_expiration_timestamp;
    // Guarantee that global_expiration_timestamp <= expiration_timestamp, which also implies that
    // 0 <= expiration_timestamp.
    assert [range_check_ptr + 4] = transfer.base.expiration_timestamp - global_expiration_timestamp;

    // Check that expiration_timestamp < EXPIRATION_TIMESTAMP_BOUND.
    tempvar inclusive_expiration_timestamp_bound = EXPIRATION_TIMESTAMP_BOUND - 1;
    // Guarantee that expiration_timestamp <= inclusive_expiration_timestamp_bound <
    // EXPIRATION_TIMESTAMP_BOUND.
    assert [range_check_ptr + 5] = (
        inclusive_expiration_timestamp_bound - transfer.base.expiration_timestamp);

    // Call vault_update for the sender.
    %{
        from starkware.cairo.dex.objects import FeeWitness, L2VaultUpdateWitness
        vault_update_witness = L2VaultUpdateWitness(
            balance_before=transfer_witness.vault_diffs[0].prev.balance)
    %}
    let sender_vault_update_ret = l2_vault_update_diff(
        range_check_ptr=range_check_ptr + 6,
        diff=transfer.amount * (-1),
        stark_key=transfer.base.public_key,
        token_id=transfer.asset_id,
        vault_index=transfer.sender_vault_id,
        vault_change_ptr=vault_dict,
    );

    // Call vault_update for the receiver.
    %{
        vault_update_witness = L2VaultUpdateWitness(
            balance_before=transfer_witness.vault_diffs[1].prev.balance)
    %}
    let (range_check_ptr) = l2_vault_update_diff(
        range_check_ptr=sender_vault_update_ret.range_check_ptr,
        diff=transfer.amount,
        stark_key=transfer.receiver_public_key,
        token_id=transfer.asset_id,
        vault_index=transfer.receiver_vault_id,
        vault_change_ptr=vault_dict + DictAccess.SIZE,
    );

    let vault_dict = vault_dict + 2 * DictAccess.SIZE;
    if (with_fee != 0) {
        // Validate fee taken and update matching vaults.
        let fee_info_user: FeeInfoUser* = alloc();
        assert fee_info_user.token_id = transfer.asset_id_fee;
        assert fee_info_user.fee_limit = transfer.max_amount_fee;
        assert fee_info_user.source_vault_id = transfer.src_fee_vault_id;

        local fee_info_exchange: FeeInfoExchange*;
        %{
            # Initialize fee_info_exchange.
            fee_info_exchange = transfer.fee_info_exchange
            ids.fee_info_exchange = segments.gen_arg([
                fee_info_exchange.fee_taken, fee_info_exchange.destination_vault_id,
                fee_info_exchange.destination_stark_key
            ])
            # Define a FeeWitness.
            fee_witness = FeeWitness(
                source_fee_witness=L2VaultUpdateWitness(
                    balance_before=transfer_witness.vault_diffs[2].prev.balance),
                destination_fee_witness=L2VaultUpdateWitness(
                    balance_before=transfer_witness.vault_diffs[3].prev.balance))
        %}
        transfer_validate_fee{range_check_ptr=range_check_ptr}(
            fee_taken=fee_info_exchange.fee_taken, fee_limit=fee_info_user.fee_limit
        );
        // The use of L1 vaults is only allowed in settlements.
        let illegal_address = cast(0, DictAccess*);
        update_fee_vaults{
            pedersen_ptr=hash_ptr,
            range_check_ptr=range_check_ptr,
            vault_dict=vault_dict,
            l1_vault_dict=illegal_address,
        }(
            user_public_key=transfer.base.public_key,
            fee_info_user=fee_info_user,
            fee_info_exchange=fee_info_exchange,
            use_l1_src_vault=0,
        );

        // Compute transfer hash (using 64 bit vault id format).
        assert range_check_ptr_before_signature = range_check_ptr;
        assert final_vault_dict = vault_dict;
        let (message_hash) = transfer_hash{pedersen_ptr=hash_ptr}(
            transfer=transfer, condition=condition
        );
    } else {
        // Assert that the correct order_type is given for transfer (condition == 0) and
        // conditional transfer (condition != 0).
        if (condition != 0) {
            // Conditional transfer.
            tempvar order_type = PackedOrderMsg.CONDITIONAL_TRANSFER_ORDER_TYPE;
        } else {
            // Normal transfer.
            tempvar order_type = PackedOrderMsg.TRANSFER_ORDER_TYPE;
        }

        // Compute transfer hash (using 31 bit vault id format).
        let (message_hash) = order_and_transfer_hash_31{hash_ptr=hash_ptr}(
            order_type=order_type,
            vault0=transfer.sender_vault_id,
            vault1=transfer.receiver_vault_id,
            amount0=transfer.amount,
            amount1=0,
            token0=transfer.asset_id,
            token1_or_pub_key=transfer.receiver_public_key,
            nonce=transfer.base.nonce,
            expiration_timestamp=transfer.base.expiration_timestamp,
            condition=condition,
        );

        assert range_check_ptr_before_signature = range_check_ptr;
        assert final_vault_dict = vault_dict;
    }

    %{
        # Assert previous hash computation.
        signature_message_hash = transfer.signature_message_hash()
        assert ids.message_hash == signature_message_hash, \
            f'Computed message hash, {ids.message_hash}, does not match the actual one: ' \
            f'{signature_message_hash}.'
    %}

    // Signature Verification.
    verify_ecdsa_signature{ecdsa_ptr=ecdsa_ptr}(
        message=message_hash,
        public_key=transfer.base.public_key,
        signature_r=transfer.base.signature_r,
        signature_s=transfer.base.signature_s,
    );

    // Order id verification.
    let range_check_ptr = range_check_ptr_before_signature;
    with range_check_ptr {
        verify_order_id(message_hash=message_hash, order_id=order_id);
    }

    // Update orders dict.
    let order_dict_access: DictAccess* = order_dict;
    order_id = order_dict_access.key;
    assert order_dict_access.prev_value = 0;
    assert order_dict_access.new_value = transfer.amount;

    // Update conditional transfer pointer.
    if (condition != 0) {
        // Conditional transfer.
        [conditional_transfer_ptr] = condition;
        new_conditional_transfer_pointer = conditional_transfer_ptr + 1;
    } else {
        // Normal transfer.
        new_conditional_transfer_pointer = conditional_transfer_ptr;
    }

    return (
        hash_ptr=hash_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        conditional_transfer_ptr=new_conditional_transfer_pointer,
        vault_dict=final_vault_dict,
        order_dict=order_dict + DictAccess.SIZE,
    );
}
