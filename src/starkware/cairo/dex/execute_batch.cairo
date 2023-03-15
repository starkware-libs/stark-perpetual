from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.dex.dex_context import DexContext
from starkware.cairo.dex.execute_false_full_withdrawal import execute_false_full_withdrawal
from starkware.cairo.dex.execute_modification import ModificationOutput, execute_modification
from starkware.cairo.dex.execute_offchain_minting import execute_offchain_minting
from starkware.cairo.dex.execute_settlement import execute_settlement
from starkware.cairo.dex.execute_transfer import execute_transfer
from starkware.cairo.dex.message_l1_order import L1OrderMessageOutput

// Executes a batch of transactions (settlements, transfers, offchain-minting, modifications).
//
// Hint arguments:
// * transactions - a list of the remaining transactions in the batch.
// * transaction_witnesses - a list of the matching TransactionWitness objects.
func execute_batch(
    modification_ptr: ModificationOutput*,
    conditional_transfer_ptr: felt*,
    l1_order_message_ptr: L1OrderMessageOutput*,
    l1_order_message_start_ptr: L1OrderMessageOutput*,
    hash_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    order_dict: DictAccess*,
    dex_context_ptr: DexContext*,
) -> (
    modification_ptr: ModificationOutput*,
    conditional_transfer_ptr: felt*,
    l1_order_message_ptr: L1OrderMessageOutput*,
    hash_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    order_dict: DictAccess*,
) {
    // Guess non deterministically whether iteration should stop.
    if (nondet %{ len(transactions) == 0 %} != 0) {
        return (
            modification_ptr=modification_ptr,
            conditional_transfer_ptr=conditional_transfer_ptr,
            l1_order_message_ptr=l1_order_message_ptr,
            hash_ptr=hash_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            vault_dict=vault_dict,
            l1_vault_dict=l1_vault_dict,
            order_dict=order_dict,
        );
    }

    %{
        first_transaction = transactions.pop(0)
        from common.objects.transaction.raw_transaction import (
            FalseFullWithdrawal,
            Mint,
            Modification,
            Settlement,
            Transfer,
        )
    %}
    if (nondet %{ isinstance(first_transaction, Settlement) %} != 0) {
        // Call execute_settlement.
        %{
            settlement = first_transaction
            settlement_witness = transaction_witnesses.pop(0)
        %}
        let settlement_res = execute_settlement(
            hash_ptr=hash_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            l1_order_message_ptr=l1_order_message_ptr,
            l1_order_message_start_ptr=l1_order_message_start_ptr,
            vault_dict=vault_dict,
            l1_vault_dict=l1_vault_dict,
            order_dict=order_dict,
            dex_context_ptr=dex_context_ptr,
        );

        // Call execute_batch recursively.
        return execute_batch(
            modification_ptr=modification_ptr,
            conditional_transfer_ptr=conditional_transfer_ptr,
            l1_order_message_ptr=settlement_res.l1_order_message_ptr,
            l1_order_message_start_ptr=l1_order_message_start_ptr,
            hash_ptr=settlement_res.hash_ptr,
            range_check_ptr=settlement_res.range_check_ptr,
            ecdsa_ptr=settlement_res.ecdsa_ptr,
            vault_dict=settlement_res.vault_dict,
            l1_vault_dict=settlement_res.l1_vault_dict,
            order_dict=settlement_res.order_dict,
            dex_context_ptr=dex_context_ptr,
        );
    }

    if (nondet %{ isinstance(first_transaction, Transfer) %} != 0) {
        // Call execute_transfer.
        %{
            transfer = first_transaction
            transfer_witness = transaction_witnesses.pop(0)
        %}
        let transfer_res = execute_transfer(
            hash_ptr=hash_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            conditional_transfer_ptr=conditional_transfer_ptr,
            vault_dict=vault_dict,
            order_dict=order_dict,
            dex_context_ptr=dex_context_ptr,
        );

        // Call execute_batch recursively.
        return execute_batch(
            modification_ptr=modification_ptr,
            conditional_transfer_ptr=transfer_res.conditional_transfer_ptr,
            l1_order_message_ptr=l1_order_message_ptr,
            l1_order_message_start_ptr=l1_order_message_start_ptr,
            hash_ptr=transfer_res.hash_ptr,
            range_check_ptr=transfer_res.range_check_ptr,
            ecdsa_ptr=transfer_res.ecdsa_ptr,
            vault_dict=transfer_res.vault_dict,
            l1_vault_dict=l1_vault_dict,
            order_dict=transfer_res.order_dict,
            dex_context_ptr=dex_context_ptr,
        );
    }

    if (nondet %{ isinstance(first_transaction, Mint) %} != 0) {
        %{
            mint_tx = first_transaction
            mint_tx_witness = transaction_witnesses.pop(0)
        %}
        // Call execute_offchain_minting.
        let offchain_minting_res = execute_offchain_minting(
            range_check_ptr=range_check_ptr,
            hash_ptr=hash_ptr,
            dex_context_ptr=dex_context_ptr,
            vault_dict=vault_dict,
            order_dict=order_dict,
        );

        // Call execute_batch recursively.
        return execute_batch(
            modification_ptr=modification_ptr,
            conditional_transfer_ptr=conditional_transfer_ptr,
            l1_order_message_ptr=l1_order_message_ptr,
            l1_order_message_start_ptr=l1_order_message_start_ptr,
            hash_ptr=offchain_minting_res.hash_ptr,
            range_check_ptr=offchain_minting_res.range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            vault_dict=offchain_minting_res.vault_dict,
            l1_vault_dict=l1_vault_dict,
            order_dict=offchain_minting_res.order_dict,
            dex_context_ptr=dex_context_ptr,
        );
    }

    if (nondet %{ first_transaction.is_modification %} != 0) {
        // Guess if the first modification is a false full withdrawal.
        %{
            modification = first_transaction
            modification_witness = transaction_witnesses.pop(0)
        %}
        if (nondet %{ isinstance(first_transaction, FalseFullWithdrawal) %} != 0) {
            // Call execute_false_full_withdrawal.
            let (vault_dict, modification_ptr) = execute_false_full_withdrawal(
                modification_ptr=modification_ptr,
                dex_context_ptr=dex_context_ptr,
                vault_dict=vault_dict,
            );

            // Call execute_batch recursively.
            return execute_batch(
                modification_ptr=modification_ptr,
                conditional_transfer_ptr=conditional_transfer_ptr,
                l1_order_message_ptr=l1_order_message_ptr,
                l1_order_message_start_ptr=l1_order_message_start_ptr,
                hash_ptr=hash_ptr,
                range_check_ptr=range_check_ptr,
                ecdsa_ptr=ecdsa_ptr,
                vault_dict=vault_dict,
                l1_vault_dict=l1_vault_dict,
                order_dict=order_dict,
                dex_context_ptr=dex_context_ptr,
            );
        }

        // Call execute_modification.
        let (range_check_ptr, modification_ptr, vault_dict) = execute_modification(
            range_check_ptr=range_check_ptr,
            modification_ptr=modification_ptr,
            dex_context_ptr=dex_context_ptr,
            vault_dict=vault_dict,
        );

        // Call execute_batch recursively.
        return execute_batch(
            modification_ptr=modification_ptr,
            conditional_transfer_ptr=conditional_transfer_ptr,
            l1_order_message_ptr=l1_order_message_ptr,
            l1_order_message_start_ptr=l1_order_message_start_ptr,
            hash_ptr=hash_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            vault_dict=vault_dict,
            l1_vault_dict=l1_vault_dict,
            order_dict=order_dict,
            dex_context_ptr=dex_context_ptr,
        );
    }

    %{ assert len(transactions) == 0, f'Could not handle transaction: {first_transaction}.' %}
    jmp rel 0;
}
