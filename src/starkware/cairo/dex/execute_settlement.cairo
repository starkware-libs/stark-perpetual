from services.exchange.cairo.signature_message_hashes import ExchangeLimitOrder
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.dex.dex_constants import BALANCE_BOUND
from starkware.cairo.dex.dex_context import DexContext
from starkware.cairo.dex.execute_limit_order import execute_limit_order
from starkware.cairo.dex.fee import FeeInfoExchange
from starkware.cairo.dex.message_l1_order import L1OrderMessageOutput

// Executes a settlement between two parties, where each party signed an appropriate limit order
// and those orders match.
//
// Hint arguments:
// * settlement - the settlement to execute.
// * settlement_witness - the matching SettlementWitness.
func execute_settlement(
    hash_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    l1_order_message_ptr: L1OrderMessageOutput*,
    l1_order_message_start_ptr: L1OrderMessageOutput*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    order_dict: DictAccess*,
    dex_context_ptr: DexContext*,
) -> (
    hash_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    l1_order_message_ptr: L1OrderMessageOutput*,
    vault_dict: DictAccess*,
    l1_vault_dict: DictAccess*,
    order_dict: DictAccess*,
) {
    // Local variables.
    alloc_locals;
    local party_a_order: ExchangeLimitOrder*;
    local party_b_order: ExchangeLimitOrder*;

    local party_a_sold;
    local party_b_sold;

    // Define an inclusive amount bound reference for amount range-checks.
    tempvar inclusive_amount_bound = BALANCE_BOUND - 1;

    %{
        from starkware.cairo.dex.settlement_hint_functions import (
            get_fee_info_struct,
            get_fee_witness,
            get_limit_order_struct,
            get_order_witness,
        )

        ids.party_a_order = get_limit_order_struct(
          order=settlement.party_a_order, segments=segments, identifiers=ids._context.identifiers)
        ids.party_b_order = get_limit_order_struct(
          order=settlement.party_b_order, segments=segments, identifiers=ids._context.identifiers)

        ids.party_a_sold = settlement.settlement_info.party_a_sold
        ids.party_b_sold = settlement.settlement_info.party_b_sold
    %}

    // Check that 0 <= party_a_sold < BALANCE_BOUND.
    assert [range_check_ptr] = party_a_sold;
    // Guarantee that party_a_sold <= inclusive_amount_bound < BALANCE_BOUND.
    assert [range_check_ptr + 1] = inclusive_amount_bound - party_a_sold;

    // Check that 0 <= party_b_sold < BALANCE_BOUND.
    assert [range_check_ptr + 2] = party_b_sold;
    // Guarantee that party_b_sold <= inclusive_amount_bound < BALANCE_BOUND.
    assert [range_check_ptr + 3] = inclusive_amount_bound - party_b_sold;

    // Verify that token_buy (asset_id_buy) of one party equals the token_sell (asset_id_sell) of
    // the other party.
    assert party_a_order.asset_id_buy = party_b_order.asset_id_sell;
    assert party_b_order.asset_id_buy = party_a_order.asset_id_sell;

    // Call execute_limit_order for party a:
    local fee_info_exchange_party_a: FeeInfoExchange*;
    %{
        from common.objects.transaction.common_transaction import Party

        # Set order, order_witness and fee_witness - the required hint arguments for
        # execute_limit_order.
        order = settlement.party_a_order
        order_witness, vault_diff_idx = get_order_witness(
          order=order, settlement_witness=settlement_witness, party=Party.A, vault_diff_idx=0)

        a_fee_info_exchange = settlement.settlement_info.party_a_fee_info
        fee_witness, vault_diff_idx = get_fee_witness(
          order=order, settlement_witness=settlement_witness,
          fee_info_exchange=a_fee_info_exchange, vault_diff_idx=vault_diff_idx)

        ids.fee_info_exchange_party_a = get_fee_info_struct(
          fee_info_exchange=a_fee_info_exchange, segments=segments)
    %}
    let limit_order_a_ret = execute_limit_order(
        hash_ptr=hash_ptr,
        range_check_ptr=range_check_ptr + 4,
        ecdsa_ptr=ecdsa_ptr,
        limit_order=party_a_order,
        l1_order_message_ptr=l1_order_message_ptr,
        l1_order_message_start_ptr=l1_order_message_start_ptr,
        vault_dict=vault_dict,
        l1_vault_dict=l1_vault_dict,
        order_dict=order_dict,
        amount_sold=party_a_sold,
        amount_bought=party_b_sold,
        fee_info_exchange=fee_info_exchange_party_a,
        dex_context_ptr=dex_context_ptr,
    );

    // Call execute_limit_order for party b.
    local fee_info_exchange_party_b: FeeInfoExchange*;
    %{
        # Set order, order_witness and fee_witness - the required hint arguments for
        # execute_limit_order.
        order = settlement.party_b_order
        order_witness, vault_diff_idx = get_order_witness(
          order=order, settlement_witness=settlement_witness, party=Party.B,
          vault_diff_idx=vault_diff_idx)

        b_fee_info_exchange = settlement.settlement_info.party_b_fee_info
        fee_witness, vault_diff_idx = get_fee_witness(
          order=order, settlement_witness=settlement_witness,
          fee_info_exchange=b_fee_info_exchange, vault_diff_idx=vault_diff_idx)

        ids.fee_info_exchange_party_b = get_fee_info_struct(
          fee_info_exchange=b_fee_info_exchange, segments=segments)
    %}
    let limit_order_b_ret = execute_limit_order(
        hash_ptr=limit_order_a_ret.hash_ptr,
        range_check_ptr=limit_order_a_ret.range_check_ptr,
        ecdsa_ptr=limit_order_a_ret.ecdsa_ptr,
        limit_order=party_b_order,
        l1_order_message_ptr=limit_order_a_ret.l1_order_message_ptr,
        l1_order_message_start_ptr=l1_order_message_start_ptr,
        vault_dict=limit_order_a_ret.vault_dict,
        l1_vault_dict=limit_order_a_ret.l1_vault_dict,
        order_dict=limit_order_a_ret.order_dict,
        amount_sold=party_b_sold,
        amount_bought=party_a_sold,
        fee_info_exchange=fee_info_exchange_party_b,
        dex_context_ptr=dex_context_ptr,
    );

    return (
        hash_ptr=limit_order_b_ret.hash_ptr,
        range_check_ptr=limit_order_b_ret.range_check_ptr,
        ecdsa_ptr=limit_order_b_ret.ecdsa_ptr,
        l1_order_message_ptr=limit_order_b_ret.l1_order_message_ptr,
        vault_dict=limit_order_b_ret.vault_dict,
        l1_vault_dict=limit_order_b_ret.l1_vault_dict,
        order_dict=limit_order_b_ret.order_dict,
    );
}
