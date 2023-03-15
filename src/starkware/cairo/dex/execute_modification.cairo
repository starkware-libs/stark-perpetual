from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.dex.dex_constants import BALANCE_BOUND as GLOBAL_BALANCE_BOUND
from starkware.cairo.dex.dex_context import DexContext
from starkware.cairo.dex.vault_update import l2_vault_update_balances

namespace ModificationConstants {
    const BALANCE_SHIFT = 2 ** 64;
    const VAULT_SHIFT = 2 ** 64;
    const FULL_WITHDRAWAL_SHIFT = BALANCE_SHIFT * VAULT_SHIFT;
}

// Represents the struct of data written to the program output for each modification.
struct ModificationOutput {
    // The stark_key of the changed vault.
    stark_key: felt,
    // The token_id of the token which was deposited or withdrawn.
    token_id: felt,
    // A packed field that consists of the balances and vault_id.
    // The format is as follows:
    // +--------------------+------------------+----------------LSB-+
    // | full_withdraw (1b) |  vault_idx (64b) | balance_diff (64b) |
    // +--------------------+------------------+--------------------+
    // where balance_diff is represented using a 2**63 biased-notation.
    action: felt,
}

// Executes a modification (deposit or withdrawal) which changes the balance in a single vault
// and writes the details of that change to the program output, so that the inverse operation
// may be performed by the solidity contract on the on-chain deposit/withdrawal vaults.
func execute_modification(
    range_check_ptr,
    modification_ptr: ModificationOutput*,
    dex_context_ptr: DexContext*,
    vault_dict: DictAccess*,
) -> (range_check_ptr: felt, modification_ptr: ModificationOutput*, vault_dict: DictAccess*) {
    // Local variables.
    local balance_before;
    local balance_after;
    local vault_index;
    local is_full_withdrawal;
    %{
        ids.balance_before = modification_witness.vault_diffs[0].prev.balance
        ids.balance_after = modification_witness.vault_diffs[0].new.balance
        ids.vault_index = modification.vault_id

        from common.objects.transaction.raw_transaction import FullWithdrawal
        ids.is_full_withdrawal = isinstance(modification, FullWithdrawal)
    %}
    alloc_locals;

    let dex_context: DexContext* = dex_context_ptr;
    let output: ModificationOutput* = modification_ptr;

    // Copy constants to allow overriding them in the tests.
    const BALANCE_BOUND = GLOBAL_BALANCE_BOUND;
    const BALANCE_SHIFT = ModificationConstants.BALANCE_SHIFT;
    const VAULT_SHIFT = ModificationConstants.VAULT_SHIFT;

    // Perform range checks on balance_before, balance_after and vault_index to make sure
    // their values are valid, and that they do not overlap in the modification action field.
    %{
        # Sanity check: make sure BALANCE_BOUND <= BALANCE_SHIFT.
        # Note that this is checked only by the prover.
        assert ids.BALANCE_BOUND <= ids.BALANCE_SHIFT
    %}
    tempvar inclusive_balance_bound = BALANCE_BOUND - 1;

    // Check that 0 <= balance_before < BALANCE_BOUND.
    assert [range_check_ptr] = balance_before;
    // Guarantee that balance_before <= inclusive_balance_bound < BALANCE_BOUND.
    assert [range_check_ptr + 1] = inclusive_balance_bound - balance_before;

    // Check that 0 <= balance_after < BALANCE_BOUND.
    assert [range_check_ptr + 2] = balance_after;
    // Guarantee that balance_after <= inclusive_balance_bound < BALANCE_BOUND.
    assert [range_check_ptr + 3] = inclusive_balance_bound - balance_after;

    // Note: This range-check is redundant as it is also checked in l2_vault_update_balances.
    // We keep it here for consistency with the other fields and to avoid the unnecessary dependency
    // on the guarantees of l2_vault_update_balances().
    assert [range_check_ptr + 4] = vault_index;
    // Guarantee that vault_index < VAULT_SHIFT.
    assert [range_check_ptr + 5] = (VAULT_SHIFT - 1) - vault_index;

    // Assert that is_full_withdrawal is a bit.
    is_full_withdrawal = is_full_withdrawal * is_full_withdrawal;

    // If is_full_withdrawal is set, balance_after must be 0.
    assert is_full_withdrawal * balance_after = 0;

    // balance_before and balance_after were range checked and are guaranteed to be in the range
    // [0, BALANCE_BOUND) => diff is in the range (-BALANCE_BOUND, BALANCE_BOUND)
    // => biased_diff is in the range [1, 2*BALANCE_BOUND).
    tempvar diff = balance_after - balance_before;
    tempvar biased_diff = diff + BALANCE_BOUND;
    assert output.action = ((is_full_withdrawal * VAULT_SHIFT) + vault_index) * BALANCE_SHIFT +
        biased_diff;

    %{
        vault_update_data = modification.get_modification_vault_change(
            modification_witness.vault_diffs[0].prev)
        ids.output.stark_key = vault_update_data.stark_key
        ids.output.token_id = vault_update_data.token
    %}
    l2_vault_update_balances(
        balance_before=balance_before,
        balance_after=balance_after,
        stark_key=output.stark_key,
        token_id=output.token_id,
        vault_index=vault_index,
        vault_change_ptr=vault_dict,
    );

    return (
        range_check_ptr=range_check_ptr + 6,
        modification_ptr=modification_ptr + ModificationOutput.SIZE,
        vault_dict=vault_dict + DictAccess.SIZE,
    );
}
