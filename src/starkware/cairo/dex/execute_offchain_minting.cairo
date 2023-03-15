from services.exchange.cairo.definitions.constants import MINT_TREE_INDEX_SALT
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import assert_lt_felt
from starkware.cairo.dex.dex_constants import MINTABLE_ASSET_ID_BOUND, MINTING_BIT
from starkware.cairo.dex.dex_context import DexContext
from starkware.cairo.dex.vault_update import l2_vault_update_diff

// Compute the tree index of a mint transaction.
func mint_index{hash_ptr: HashBuiltin*}(asset_id: felt) -> (index: felt) {
    let (hash) = hash2(x=MINT_TREE_INDEX_SALT, y=asset_id);
    return (index=hash);
}

// Executes an offchain minting which adds to the balance in a single vault.
// Asserts that the corresponding token is mintable - the minting bit is on.
func execute_offchain_minting(
    range_check_ptr,
    hash_ptr: HashBuiltin*,
    dex_context_ptr: DexContext*,
    vault_dict: DictAccess*,
    order_dict: DictAccess*,
) -> (
    range_check_ptr: felt, hash_ptr: HashBuiltin*, vault_dict: DictAccess*, order_dict: DictAccess*
) {
    local token_id;
    alloc_locals;

    %{
        ids.token_id = mint_tx.token_id
        assert mint_tx.diff == 1, f"Illegal mint amount requested: {mint_tx.diff}."
    %}

    // Validate that the minting bit is on in the token_id, that the token_id without the mint bit
    // is in the valid range, and that the control bits are zero.
    // If we write the token id as a 251 bit number we get:
    // +-----------------+----------------------------+-----LSB----+
    // | mint_bit (1b)   | zeros (control bits) (10b) |   (240b)   |
    // +-----------------+----------------------------+------------+
    // It is enough to subtract the minting bit from the token_id and assert the result is less than
    // 2^240.
    let token_id_without_minting_bit = token_id - MINTING_BIT;
    with range_check_ptr {
        assert_lt_felt(token_id_without_minting_bit, MINTABLE_ASSET_ID_BOUND);
    }

    // The minted amount must be 1.
    local minted_amount = 1;

    // Update orders dict if unique minting is enforced.
    local order_dict_offset: felt;
    if (dex_context_ptr.general_config.unique_minting_enforced == 1) {
        with hash_ptr {
            let (index: felt) = mint_index(asset_id=token_id);
        }
        assert order_dict.key = index;
        assert order_dict.prev_value = 0;
        assert order_dict.new_value = minted_amount;
        assert order_dict_offset = DictAccess.SIZE;
        tempvar hash_ptr = hash_ptr;
    } else {
        assert order_dict_offset = 0;
        tempvar hash_ptr = hash_ptr;
    }

    // Validate the vault change.
    local vault_id;
    local stark_key;
    %{
        ids.vault_id = mint_tx.vault_id
        ids.stark_key = mint_tx.stark_key

        from starkware.cairo.dex.objects import L2VaultUpdateWitness
        vault_update_witness = L2VaultUpdateWitness(
            balance_before = mint_tx_witness.vault_diffs[0].prev.balance)
    %}

    let (range_check_ptr) = l2_vault_update_diff(
        range_check_ptr=range_check_ptr,
        diff=minted_amount,
        stark_key=stark_key,
        token_id=token_id,
        vault_index=vault_id,
        vault_change_ptr=vault_dict,
    );

    return (
        range_check_ptr=range_check_ptr,
        hash_ptr=hash_ptr,
        vault_dict=vault_dict + DictAccess.SIZE,
        order_dict=order_dict + order_dict_offset,
    );
}
