from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.dex.dex_constants import BALANCE_BOUND, ZERO_VAULT_HASH

struct L2VaultState {
    stark_key: felt,
    token_id: felt,
    balance: felt,
}

// Retrieves a pointer to a L2VaultState with the corresponding vault.
// Returns an empty vault if balance == 0 (stark_key and token_id are ignored).
func get_vault_state(stark_key, token_id, balance) -> (vault_state_ptr: L2VaultState*) {
    let vault_state_ptr = cast([ap], L2VaultState*);
    %{ ids.vault_state_ptr = vault_state_mgr.get_ptr(ids.stark_key, ids.token_id, ids.balance) %}

    // Allocate 1 slot for our local which is also the return value.
    vault_state_ptr.balance = balance, ap++;

    if (balance == 0) {
        // Balance is 0 here, use it for initialization.
        let zero = balance;
        vault_state_ptr.stark_key = zero;
        vault_state_ptr.token_id = zero;
        return (vault_state_ptr=vault_state_ptr);
    }

    vault_state_ptr.stark_key = stark_key;
    vault_state_ptr.token_id = token_id;
    return (vault_state_ptr=vault_state_ptr);
}

// Computes the hash h(key_token_hash, amount), where key_token_hash := h(stark_key, token_id).
func compute_vault_hash(hash_ptr: HashBuiltin*, key_token_hash, amount) -> (
    vault_hash: felt, hash_ptr: HashBuiltin*
) {
    if (amount == 0) {
        return (vault_hash=ZERO_VAULT_HASH, hash_ptr=hash_ptr);
    }

    key_token_hash = hash_ptr.x;
    amount = hash_ptr.y;
    return (vault_hash=hash_ptr.result, hash_ptr=hash_ptr + HashBuiltin.SIZE);
}

// Updates the balance in the vault (leaf in the vault tree) corresponding to vault_index,
// by writing the change to vault_change_ptr.
// May also by used to verify the values in a certain vault.
func l2_vault_update_balances(
    balance_before, balance_after, stark_key, token_id, vault_index, vault_change_ptr: DictAccess*
) {
    let vault_access: DictAccess* = vault_change_ptr;
    vault_access.key = vault_index;
    let (prev_vault_state_ptr) = get_vault_state(
        stark_key=stark_key, token_id=token_id, balance=balance_before
    );
    vault_access.prev_value = prev_vault_state_ptr;
    let (new_vault_state_ptr) = get_vault_state(
        stark_key=stark_key, token_id=token_id, balance=balance_after
    );
    vault_access.new_value = new_vault_state_ptr;
    return ();
}

// Similar to l2_vault_update_balances, except that the expected difference
// (balance_after - balance_before) is given and a range-check is performed on balance_after.
//
// Hint arguments:
// vault_update_witness - L2VaultUpdateWitness containing the balance_before of the updated vault.
func l2_vault_update_diff(
    range_check_ptr, diff, stark_key, token_id, vault_index, vault_change_ptr: DictAccess*
) -> (range_check_ptr: felt) {
    // Local variables.
    alloc_locals;
    local balance_before;
    local balance_after;

    %{ ids.balance_before = vault_update_witness.balance_before %}
    balance_after = balance_before + diff;

    // Check that 0 <= balance_after < BALANCE_BOUND.
    assert [range_check_ptr] = balance_after;
    // Apply the range check builtin on (BALANCE_BOUND - 1 - balance_after), which guarantees that
    // balance_after < BALANCE_BOUND.
    assert [range_check_ptr + 1] = (BALANCE_BOUND - 1) - balance_after;

    // Call l2_vault_update_balances.
    l2_vault_update_balances(
        balance_before=balance_before,
        balance_after=balance_after,
        stark_key=stark_key,
        token_id=token_id,
        vault_index=vault_index,
        vault_change_ptr=vault_change_ptr,
    );

    return (range_check_ptr=range_check_ptr + 2);
}
