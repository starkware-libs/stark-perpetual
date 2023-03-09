from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.dex.vault_update import L2VaultState, compute_vault_hash

// Gets a single pointer to a vault state and outputs the hash of that vault.
func hash_vault_state_ptr(hash_ptr: HashBuiltin*, vault_state_ptr: L2VaultState*) -> (
    vault_hash: felt, hash_ptr: HashBuiltin*
) {
    let hash_builtin: HashBuiltin* = hash_ptr;
    let vault_state: L2VaultState* = vault_state_ptr;

    assert hash_builtin.x = vault_state.stark_key;
    assert hash_builtin.y = vault_state.token_id;

    // Compute new hash.
    return compute_vault_hash(
        hash_ptr=hash_ptr + HashBuiltin.SIZE,
        key_token_hash=hash_builtin.result,
        amount=vault_state.balance,
    );
}

// Takes a vault_ptr_dict with pointers to vault states, and writes a new adjusted_vault_dict where
// the felt `key_subtrahend` is subtracted from each key.
func adjust_vault_dict_keys(
    vault_ptr_dict: DictAccess*, n_entries, adjusted_vault_dict: DictAccess*, key_subtrahend: felt
) {
    if (n_entries == 0) {
        return ();
    }

    // Set the values of the new dict to be the same as the old dict, and adjust the key.
    assert [adjusted_vault_dict] = DictAccess(
        key=vault_ptr_dict.key - key_subtrahend,
        prev_value=vault_ptr_dict.prev_value,
        new_value=vault_ptr_dict.new_value);

    // Tail call.
    return adjust_vault_dict_keys(
        vault_ptr_dict=&vault_ptr_dict[1],
        n_entries=n_entries - 1,
        adjusted_vault_dict=&adjusted_vault_dict[1],
        key_subtrahend=key_subtrahend,
    );
}

// Takes a vault_ptr_dict with pointers to vault states and writes a new vault_hash_dict with
// hashed vaults instead of pointers.
// The size of the vault_hash_dict is the same as the original dict and the DictAccess keys are
// copied as is.
func hash_vault_ptr_dict(
    hash_ptr: HashBuiltin*, vault_ptr_dict: DictAccess*, n_entries, vault_hash_dict: DictAccess*
) -> (hash_ptr: HashBuiltin*) {
    if (n_entries == 0) {
        return (hash_ptr=hash_ptr);
    }

    let hash_builtin: HashBuiltin* = hash_ptr;
    let vault_access: DictAccess* = vault_ptr_dict;
    let hashed_vault_access: DictAccess* = vault_hash_dict;

    // Copy the key.
    assert hashed_vault_access.key = vault_access.key;
    let prev_hash_res = hash_vault_state_ptr(
        hash_ptr=hash_ptr, vault_state_ptr=cast(vault_access.prev_value, L2VaultState*)
    );
    hashed_vault_access.prev_value = prev_hash_res.vault_hash;

    let new_hash_res = hash_vault_state_ptr(
        hash_ptr=prev_hash_res.hash_ptr, vault_state_ptr=cast(vault_access.new_value, L2VaultState*)
    );
    hashed_vault_access.new_value = new_hash_res.vault_hash;

    // Tail call.
    return hash_vault_ptr_dict(
        hash_ptr=new_hash_res.hash_ptr,
        vault_ptr_dict=vault_ptr_dict + DictAccess.SIZE,
        n_entries=n_entries - 1,
        vault_hash_dict=vault_hash_dict + DictAccess.SIZE,
    );
}
