from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.dex.dex_constants import BALANCE_BOUND as GLOBAL_BALANCE_BOUND
from starkware.cairo.dex.dex_context import DexContext
from starkware.cairo.dex.execute_modification import ModificationConstants, ModificationOutput
from starkware.cairo.dex.vault_update import l2_vault_update_balances

// Executes a false full withdrawal.
// Validates that the requester_stark_key from the hint is not the stark key in the vault
// and writes the requester_stark_key to the program output.
// Assumptions: keys in the vault_dict are range-checked to be < VAULT_SHIFT.
func execute_false_full_withdrawal(
    modification_ptr: ModificationOutput*, dex_context_ptr: DexContext*, vault_dict: DictAccess*
) -> (vault_dict: DictAccess*, modification_ptr: ModificationOutput*) {
    let dex_context: DexContext* = dex_context_ptr;
    let output: ModificationOutput* = modification_ptr;

    // Copy constants to allow overriding them in the tests.
    const BALANCE_BOUND = GLOBAL_BALANCE_BOUND;
    const FULL_WITHDRAWAL_SHIFT = ModificationConstants.FULL_WITHDRAWAL_SHIFT;
    const BALANCE_SHIFT = ModificationConstants.BALANCE_SHIFT;

    alloc_locals;
    local stark_key;
    local balance_before;
    local token_id;
    local vault_index;
    %{
        ids.vault_index = modification.vault_id
        ids.output.stark_key = modification.requester_stark_key

        vault_state = modification_witness.vault_diffs[0].prev
        ids.balance_before = vault_state.balance
        ids.stark_key = vault_state.stark_key
        ids.token_id = vault_state.token
    %}

    assert output.token_id = 0;

    // Note that we assume vault_index is range-checked during the merkle_multi_update,
    // which will force the full withdrawal bit to be 1.
    assert output.action = vault_index * BALANCE_SHIFT + BALANCE_BOUND + FULL_WITHDRAWAL_SHIFT;

    // In false full withdrawal balance_before must be equal to balance_after.
    l2_vault_update_balances(
        balance_before=balance_before,
        balance_after=balance_before,
        stark_key=stark_key,
        token_id=token_id,
        vault_index=vault_index,
        vault_change_ptr=vault_dict,
    );

    // Guess the requester_stark_key, write it to the output and make sure it's not the same as the
    // stark_key.
    let requester_stark_key = output.stark_key;
    tempvar key_diff = requester_stark_key - stark_key;
    if (key_diff == 0) {
        // Add an unsatisfiable assertion when key_diff == 0.
        key_diff = 1;
    }

    return (
        vault_dict=vault_dict + DictAccess.SIZE,
        modification_ptr=modification_ptr + ModificationOutput.SIZE,
    );
}
