from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.find_element import find_element
from starkware.cairo.common.math import assert_nn_le
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.dex.dex_constants import BALANCE_BOUND
from starkware.cairo.dex.vault_update import L2VaultState

const ONCHAIN_DATA_KEY_INDEX_BOUND = 2 ** 15;
const ONCHAIN_DATA_TOKEN_INDEX_BOUND = 2 ** 15;
const ONCHAIN_DATA_VAULT_ID_BOUND = 2 ** 31;
const VAULT_CHANGE_SHIFT = ONCHAIN_DATA_VAULT_ID_BOUND * BALANCE_BOUND *
    ONCHAIN_DATA_KEY_INDEX_BOUND * ONCHAIN_DATA_TOKEN_INDEX_BOUND;

// Represents two tables of keys and tokens, which will be written to the program output
// before the vault changes.
// The vault changes will contain pointers to these tables instead of explicitly stating
// the key/token. This allows reducing onchain-data in the case a key/token appears more than once.
struct EncodingTables {
    n_keys: felt,
    key_table_ptr: felt*,
    n_tokens: felt,
    token_table_ptr: felt*,
}

// Allocates a table for keys or tokens and writes it to output_ptr as follows:
//   * One field element with the size of the table.
//   * A field element for each entry in the table.
//
// Returns a pointer to the table and its size.
//
// Hint assumptions:
//   * A variable 'values' should be available with the values of the table.
func initialize_encoding_table(output_ptr: felt*) -> (
    output_ptr: felt*, table_ptr: felt*, table_size: felt
) {
    alloc_locals;
    local table_size;
    %{
        ids.table_size = len(values)
        for i, value in enumerate(values):
            memory[ids.output_ptr + 1 + i] = value
    %}
    assert [output_ptr] = table_size;
    return (
        output_ptr=output_ptr + 1 + table_size, table_ptr=output_ptr + 1, table_size=table_size
    );
}

// Returns a 124-bit integer encoding a single vault change.
// See output_volition_data() for more details.
func get_vault_change_encoding(
    range_check_ptr, vault_index, vault_state: L2VaultState*, encoding_tables: EncodingTables*
) -> (encoded_change: felt, range_check_ptr: felt) {
    alloc_locals;
    %{ __find_element_index = keys[ids.vault_state.stark_key] %}
    let (elm_ptr) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=encoding_tables.key_table_ptr,
        elm_size=1,
        n_elms=encoding_tables.n_keys,
        key=vault_state.stark_key,
    );
    local key_index = elm_ptr - encoding_tables.key_table_ptr;

    // Find the index for the token_id.
    %{ __find_element_index = tokens[ids.vault_state.token_id] %}
    let (elm_ptr) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=encoding_tables.token_table_ptr,
        elm_size=1,
        n_elms=encoding_tables.n_tokens,
        key=vault_state.token_id,
    );
    local token_index = elm_ptr - encoding_tables.token_table_ptr;

    let encoded_change = vault_index;
    let encoded_change = encoded_change * BALANCE_BOUND + vault_state.balance;
    let encoded_change = encoded_change * ONCHAIN_DATA_KEY_INDEX_BOUND + key_index;
    let encoded_change = encoded_change * ONCHAIN_DATA_TOKEN_INDEX_BOUND + token_index;

    return (encoded_change=encoded_change, range_check_ptr=range_check_ptr);
}

// Serializes a single vault change as a 124-bit integer.
// See output_volition_data() for more details.
func serialize_vault_change(output_ptr: felt*, partial_word, encoded_change) -> (
    output_ptr: felt*, partial_word: felt
) {
    // Check if there is a pending change (partial_word != -1).
    tempvar partial_word_plus_one = partial_word + 1;
    jmp serialize if partial_word_plus_one != 0;

    return (output_ptr=output_ptr, partial_word=encoded_change);

    serialize:
    assert [output_ptr] = partial_word * VAULT_CHANGE_SHIFT + encoded_change;
    return (output_ptr=output_ptr + 1, partial_word=-1);
}

// Helper function for output_volition_data().
func output_volition_data_inner(
    output_ptr: felt*,
    range_check_ptr,
    encoding_tables: EncodingTables*,
    squashed_vault_dict: DictAccess*,
    n_updates,
    partial_word,
) -> (output_ptr: felt*, range_check_ptr: felt) {
    jmp body if n_updates != 0;
    // Call serialize_vault_change one additional time to make sure that if we have an odd number
    // of changes, the last one will be recorded.
    let (output_ptr_ret, _) = serialize_vault_change(
        output_ptr=output_ptr, partial_word=partial_word, encoded_change=partial_word
    );
    return (output_ptr=output_ptr_ret, range_check_ptr=range_check_ptr);

    body:
    alloc_locals;
    local prev_vault: L2VaultState* = cast(squashed_vault_dict.prev_value, L2VaultState*);
    local new_vault: L2VaultState* = cast(squashed_vault_dict.new_value, L2VaultState*);
    local tmp_range_check_ptr;

    // Check balance diff.
    tempvar balance_diff = new_vault.balance - prev_vault.balance;
    jmp full_update if balance_diff != 0;

    // Check balance stark key.
    tempvar stark_key_diff = new_vault.stark_key - prev_vault.stark_key;
    jmp full_update if stark_key_diff != 0;

    // Check token id.
    tempvar token_id_diff = new_vault.token_id - prev_vault.token_id;
    jmp full_update if token_id_diff != 0;

    no_update:
    // Touch tmp_range_check_ptr so it will be used.
    tmp_range_check_ptr = 0;
    // Call output_volition_data_inner recursively.
    return output_volition_data_inner(
        output_ptr=output_ptr,
        range_check_ptr=range_check_ptr,
        encoding_tables=encoding_tables,
        squashed_vault_dict=squashed_vault_dict + DictAccess.SIZE,
        n_updates=n_updates - 1,
        partial_word=partial_word,
    );

    full_update:
    let (encoded_change, range_check_ptr) = get_vault_change_encoding(
        range_check_ptr=range_check_ptr,
        vault_index=squashed_vault_dict.key,
        vault_state=new_vault,
        encoding_tables=encoding_tables,
    );
    tmp_range_check_ptr = range_check_ptr;
    let (output_ptr, partial_word) = serialize_vault_change(
        output_ptr=output_ptr, partial_word=partial_word, encoded_change=encoded_change
    );

    // Call output_volition_data_inner recursively.
    return output_volition_data_inner(
        output_ptr=output_ptr,
        range_check_ptr=tmp_range_check_ptr,
        encoding_tables=encoding_tables,
        squashed_vault_dict=squashed_vault_dict + DictAccess.SIZE,
        n_updates=n_updates - 1,
        partial_word=partial_word,
    );
}

// Outputs onchain data for the given changes in the vaults.
// squashed_vault_dict is a squashed dict of changes to L2VaultState entries.
//
// The header of the data consists of a table of keys and a table of tokens.
// All keys and tokens are given as indices to the corresponding table (at most 15 bits).
// For every change, the new status of the vault is written to output_ptr as a 124-bit integer:
//   +------------------+----------------+----------------------+-----------------LSB-+
//   | vault_index (31) |  balance  (63) | stark_key index (15) | token_id index (15) |
//   +------------------+----------------+----------------------+---------------------+
//
// Each output word contains 2 changes. If the total number of updates is odd, the last word
// will contain the same update twice.
func output_volition_data(
    output_ptr: felt*, range_check_ptr, squashed_vault_dict: DictAccess*, n_updates
) -> (output_ptr: felt*, range_check_ptr: felt) {
    alloc_locals;
    local encoding_tables: EncodingTables;

    %{
        keys = set()
        tokens = set()
        for i in range(ids.n_updates):
            vault_before_ptr = memory[
                ids.squashed_vault_dict.address_ + i * ids.DictAccess.SIZE +
                ids.DictAccess.prev_value]
            vault_after_ptr = memory[
                ids.squashed_vault_dict.address_ + i * ids.DictAccess.SIZE +
                ids.DictAccess.new_value]

            vault_before = [memory[vault_before_ptr + i] for i in range(ids.L2VaultState.SIZE)]
            vault_after = [memory[vault_after_ptr + i] for i in range(ids.L2VaultState.SIZE)]

            if vault_before != vault_after:
                keys.add(vault_after[ids.L2VaultState.stark_key])
                tokens.add(vault_after[ids.L2VaultState.token_id])

        vm_enter_scope({'values': sorted(keys)})
    %}
    let (output_ptr, key_ptr, key_size) = initialize_encoding_table(output_ptr=output_ptr);
    %{ vm_exit_scope() %}
    assert_nn_le{range_check_ptr=range_check_ptr}(key_size, ONCHAIN_DATA_KEY_INDEX_BOUND - 1);
    encoding_tables.key_table_ptr = key_ptr;
    encoding_tables.n_keys = key_size;

    %{ vm_enter_scope({'values': sorted(tokens)}) %}
    let (output_ptr, token_ptr, token_size) = initialize_encoding_table(output_ptr=output_ptr);
    %{ vm_exit_scope() %}
    assert_nn_le{range_check_ptr=range_check_ptr}(token_size, ONCHAIN_DATA_TOKEN_INDEX_BOUND - 1);
    encoding_tables.token_table_ptr = token_ptr;
    encoding_tables.n_tokens = token_size;

    let (__fp__, _) = get_fp_and_pc();
    %{
        vm_enter_scope({
            'keys': {key: i for i, key in enumerate(sorted(keys))},
            'tokens': {token: i for i, token in enumerate(sorted(tokens))},
        })
    %}
    let (output_ptr, range_check_ptr) = output_volition_data_inner(
        output_ptr=output_ptr,
        range_check_ptr=range_check_ptr,
        encoding_tables=&encoding_tables,
        squashed_vault_dict=squashed_vault_dict,
        n_updates=n_updates,
        partial_word=-1,
    );
    %{ vm_exit_scope() %}
    return (output_ptr=output_ptr, range_check_ptr=range_check_ptr);
}
