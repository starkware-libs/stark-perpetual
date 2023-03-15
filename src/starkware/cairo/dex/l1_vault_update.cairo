from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict import dict_update
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_nn, assert_nn_le
from starkware.cairo.dex.dex_constants import BALANCE_BOUND, ETH_ADDRESS_SHIFT, L1_VAULT_INDEX_BOUND
from starkware.cairo.dex.execute_modification import ModificationConstants

// Represents the struct of data written to the program output for each L1 vault update.
struct L1VaultOutput {
    // The Ethereum key of the changed vault.
    eth_key: felt,
    // The token_id of the asset that was bought or sold.
    token_id: felt,
    // A packed field that consists of:
    // vault_index - the L1 vault index amongst the vaults with the above eth_key and token_id.
    // minimal_initial_balance - the minimal balance the L1 vault must have prior to the execution
    //   of the batch, in order to prevent a temporary negative balance during the execution.
    //   Possible values are in [0, 2**63).
    // balance_diff - the accumulated diff for this vault, which is the result of executing all of
    //   the transactions in the batch, represented using a 2**63 biased-notation.
    // The format is as follows:
    // +---------------------+---+--------------------------------+----------------LSB-+
    // |  vault_index (31b)  | 0 | minimal_initial_balance (63b)  | balance_diff (64b) |
    // +---------------------+---+--------------------------------+--------------------+ .
    action: felt,
}

// Computes the dict key for the L1 vault updates, that equals: hash(vault_index|eth_key, token_id).
func get_l1_vault_hash_key{pedersen_ptr: HashBuiltin*}(eth_key, token_id, vault_index) -> (
    key: felt
) {
    let (hash) = hash2{hash_ptr=pedersen_ptr}(
        x=vault_index * ETH_ADDRESS_SHIFT + eth_key, y=token_id
    );
    return (key=hash);
}

// Outputs L1 vaults update data stored in squashed_dict, as L1VaultOutput structs.
// For each squash_dict DictAccess:
//   1. key is the hash key of an L1 vault (see get_l1_vault_hash_key).
//   2. prev_value is the minimal initial balance needed to prevent a negative balance throughout
//      the execution of the batch.
//   3. new_value is the final balance after applying the batch, assuming the vault's initial
//      balance is the mentioned minimal initial balance.
//
// Hint arguments:
// l1_vault_hash_key_to_explicit - a dictionary from the L1 vaults hash keys to the original
//   L1VaultKey object (that holds the explicit keys, i.e., (eth_key, token_id, vault_index)).
func output_l1_vault_update_data{
    range_check_ptr, pedersen_ptr: HashBuiltin*, l1_vault_ptr: L1VaultOutput*
}(squashed_dict: DictAccess*, squashed_dict_end_ptr: DictAccess*) -> () {
    alloc_locals;
    if (squashed_dict_end_ptr == squashed_dict) {
        return ();
    }

    const BALANCE_SHIFT = ModificationConstants.BALANCE_SHIFT;

    // The first element in the squashed dict represents the current L1 vault to output.

    // Asserts that the minimal (initial) balance, and final balance are in [0, BALANCE_BOUND).
    let minimal_balance = squashed_dict.prev_value;
    assert_nn_le(minimal_balance, BALANCE_BOUND - 1);
    let final_balance = squashed_dict.new_value;
    assert_nn_le(final_balance, BALANCE_BOUND - 1);

    local vault_index;
    %{
        # Get this L1 vault explicit keys (eth_key, token_id, vault_index) from the hash key.
        # Output the first two of three directly.
        ids.l1_vault_ptr.eth_key, ids.l1_vault_ptr.token_id, ids.vault_index = \
            l1_vault_hash_key_to_explicit[ids.squashed_dict.key].to_tuple()
    %}
    assert_nn_le(vault_index, L1_VAULT_INDEX_BOUND - 1);
    // Asserts that the L1 vault keys in the output match the hash key in the squashed dict.
    let (vault_key) = get_l1_vault_hash_key(
        eth_key=l1_vault_ptr.eth_key, token_id=l1_vault_ptr.token_id, vault_index=vault_index
    );
    assert vault_key = squashed_dict.key;

    // minimal_balance and final_balance were range checked and are guaranteed to be in the range
    // [0, BALANCE_BOUND) => diff is in the range (-BALANCE_BOUND, BALANCE_BOUND)
    // => biased_diff is in the range [1, 2*BALANCE_BOUND).
    let diff = final_balance - minimal_balance;
    tempvar biased_diff = diff + BALANCE_BOUND;
    static_assert BALANCE_SHIFT == 2 * BALANCE_BOUND;

    // Output this L1 vault action data: (vault_index | minimal_balance | diff).
    assert l1_vault_ptr.action = (vault_index * BALANCE_SHIFT + minimal_balance) *
        BALANCE_SHIFT + biased_diff;
    tempvar range_check_ptr = range_check_ptr;
    tempvar l1_vault_ptr = l1_vault_ptr + L1VaultOutput.SIZE;
    tempvar pedersen_ptr = pedersen_ptr;

    output_l1_vault_update_data(
        squashed_dict=squashed_dict + DictAccess.SIZE, squashed_dict_end_ptr=squashed_dict_end_ptr
    );
    return ();
}

// Updates the diff in the L1 vault corresponding to the given keys, by writing the new balance to
// l1_vault_dict.
func l1_vault_update_diff{pedersen_ptr: HashBuiltin*, range_check_ptr, l1_vault_dict: DictAccess*}(
    diff, eth_key, token_id, vault_index
) -> () {
    alloc_locals;
    local balance_before;
    let (vault_hash_key) = get_l1_vault_hash_key(
        eth_key=eth_key, token_id=token_id, vault_index=vault_index
    );

    %{
        from starkware.cairo.dex.main_hint_functions import L1VaultKey
        vault_key = L1VaultKey(
            eth_key=ids.eth_key, token_id=ids.token_id, vault_index=ids.vault_index)
        ids.balance_before = \
            __dict_manager.get_dict(ids.l1_vault_dict)[ids.vault_hash_key]
    %}
    // Assert that 0 <= balance_before < BALANCE_BOUND.
    assert_nn_le(balance_before, BALANCE_BOUND - 1);
    let balance_after = balance_before + diff;
    // Assert that 0 <= balance_after < BALANCE_BOUND. Note that the first balance_before value of
    // this vault is checked after the l1_vault_dict dict squash and all following balance_before
    // values are implicitly checked in the balance_after assertion (as the balance_after of the
    // previous call to l1_vault_update_diff equals the balance_before of this call).
    assert_nn_le(balance_after, BALANCE_BOUND - 1);

    dict_update{dict_ptr=l1_vault_dict}(
        key=vault_hash_key, prev_value=balance_before, new_value=balance_after
    );
    return ();
}
