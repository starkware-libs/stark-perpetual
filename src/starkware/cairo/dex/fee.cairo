from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import assert_le, assert_nn_le
from starkware.cairo.dex.dex_constants import BALANCE_BOUND, RANGE_CHECK_BOUND
from starkware.cairo.dex.l1_vault_update import l1_vault_update_diff
from starkware.cairo.dex.vault_update import l2_vault_update_diff

// Fee information provided and signed by the user.
struct FeeInfoUser {
    token_id: felt,
    fee_limit: felt,
    source_vault_id: felt,
}

// Fee information provided by the exchange.
struct FeeInfoExchange {
    fee_taken: felt,
    destination_vault_id: felt,
    destination_stark_key: felt,
}

// Verify 0 <= fee_taken <= fee_limit < BALANCE_BOUND.
func transfer_validate_fee{range_check_ptr}(fee_taken, fee_limit) {
    assert_nn_le(fee_taken, fee_limit);
    assert_le(fee_limit, BALANCE_BOUND - 1);
    return ();
}

// Verify fee ratio is satisfied, i.e. 0 <= fee_taken * order_buy <= fee_limit * amount_bought.
// Note: if order_buy = 0, a valid fee_taken may be anywhere in [0, BALANCE_BOUND).
//
// Assumptions:
// 0 <= order_buy, amount_bought < BALANCE_BOUND.
func order_validate_fee{range_check_ptr}(fee_taken, fee_limit, amount_bought, order_buy) {
    static_assert BALANCE_BOUND * BALANCE_BOUND * 4 == RANGE_CHECK_BOUND;
    // Each element is < BALANCE_BOUND; thus both multiplications are < RANGE_CHECK_BOUND.
    assert_le(fee_taken, BALANCE_BOUND - 1);
    assert_le(fee_limit, BALANCE_BOUND - 1);
    assert_nn_le(fee_taken * order_buy, fee_limit * amount_bought);
    return ();
}

// Update the fee source vault. Might be an L1 or an L2 vault.
func update_fee_src_vault{
    pedersen_ptr: HashBuiltin*, range_check_ptr, vault_dict: DictAccess*, l1_vault_dict: DictAccess*
}(
    user_public_key,
    fee_info_user: FeeInfoUser*,
    fee_info_exchange: FeeInfoExchange*,
    use_l1_src_vault,
) {
    if (use_l1_src_vault != 0) {
        // Source vault is an L1 vault.
        l1_vault_update_diff(
            diff=-fee_info_exchange.fee_taken,
            eth_key=user_public_key,
            token_id=fee_info_user.token_id,
            vault_index=fee_info_user.source_vault_id,
        );
        return ();
    }

    // Source vault is an L2 vault.
    %{ vault_update_witness = fee_witness.source_fee_witness %}
    let (range_check_ptr) = l2_vault_update_diff(
        range_check_ptr=range_check_ptr,
        diff=-fee_info_exchange.fee_taken,
        stark_key=user_public_key,
        token_id=fee_info_user.token_id,
        vault_index=fee_info_user.source_vault_id,
        vault_change_ptr=vault_dict,
    );
    let vault_dict = vault_dict + DictAccess.SIZE;
    return ();
}

// Update the fee source and destination vaults.
//
// Hint arguments:
// fee_witness - a FeeWitness with the fee vaults data.
func update_fee_vaults{
    pedersen_ptr: HashBuiltin*, range_check_ptr, vault_dict: DictAccess*, l1_vault_dict: DictAccess*
}(
    user_public_key,
    fee_info_user: FeeInfoUser*,
    fee_info_exchange: FeeInfoExchange*,
    use_l1_src_vault,
) {
    update_fee_src_vault(
        user_public_key=user_public_key,
        fee_info_user=fee_info_user,
        fee_info_exchange=fee_info_exchange,
        use_l1_src_vault=use_l1_src_vault,
    );

    // Adding fee_info_exchange.fee_taken to fee destination vault (which is always an L2 vault).
    %{ vault_update_witness = fee_witness.destination_fee_witness %}
    let (range_check_ptr) = l2_vault_update_diff(
        range_check_ptr=range_check_ptr,
        diff=fee_info_exchange.fee_taken,
        stark_key=fee_info_exchange.destination_stark_key,
        token_id=fee_info_user.token_id,
        vault_index=fee_info_exchange.destination_vault_id,
        vault_change_ptr=vault_dict,
    );
    let vault_dict = vault_dict + DictAccess.SIZE;
    return ();
}
