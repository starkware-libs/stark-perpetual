from typing import Optional, Tuple

from common.objects.prover_input.prover_input import TransactionWitness
from common.objects.transaction.common_transaction import (
    FeeInfoExchange,
    Order,
    OrderL1,
    OrderL2,
    Party,
)
from starkware.cairo.common.structs import CairoStructFactory
from starkware.cairo.dex.objects import FeeWitness, L2VaultUpdateWitness, OrderWitness
from starkware.cairo.lang.compiler.identifier_manager import IdentifierManager
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable


def get_order_witness(
    order: Order, settlement_witness: TransactionWitness, party: Party, vault_diff_idx: int
) -> Tuple[OrderWitness, int]:
    """
    Returns an OrderWitness and an updated vault_diff index, for the given order.
    vault_diff_idx is an index to the L2 vault changes list in the wrapping settlement
    (settlement_witness.vault_diffs). The list holds the changes for both parties, and the given
    index should point to where the current party (the owner of the given order) vault changes
    start.
    Note that the vault updates in OrderWitness are only used in L2 Orders.
    """
    order_party_id = 0 if party is Party.A else 1
    prev_fulfilled_amount = settlement_witness.order_diffs[order_party_id].prev.fulfilled_amount

    # Set vaults witnesses (only for L2 vaults).
    if isinstance(order, OrderL1):
        sell_witness = buy_witness = None
    else:
        assert isinstance(order, OrderL2)
        sell_witness = L2VaultUpdateWitness(
            balance_before=settlement_witness.vault_diffs[vault_diff_idx].prev.balance
        )
        buy_witness = L2VaultUpdateWitness(
            balance_before=settlement_witness.vault_diffs[vault_diff_idx + 1].prev.balance
        )
        vault_diff_idx += 2

    return (
        OrderWitness(
            sell_witness=sell_witness,
            buy_witness=buy_witness,
            prev_fulfilled_amount=prev_fulfilled_amount,
        ),
        vault_diff_idx,
    )


def get_fee_witness(
    order: Order,
    settlement_witness: TransactionWitness,
    fee_info_exchange: FeeInfoExchange,
    vault_diff_idx: int,
) -> Tuple[Optional[FeeWitness], int]:
    """
    Returns a FeeWitness and an updated vault_diff index, for the given order.
    vault_diff_idx is an index to the L2 vault changes list in the wrapping settlement
    (settlement_witness.vault_diffs). The list holds the changes for both parties, and the given
    index should point to where the current party (the owner of the given order) vault changes
    start.
    If order has no fees, returns None as the FeeWitness.
    Note that the vaults in FeeWitness are L2 vaults.
    """
    if fee_info_exchange is None:
        # OrderL2 with no fees.
        assert not isinstance(order, OrderL1), "OrderL1 must have fee objects."
        return None, vault_diff_idx
    # Set source fee witness (may be an L1 or L2 vault).
    elif isinstance(order, OrderL1):
        source_fee_witness = None
    else:
        assert isinstance(order, OrderL2)
        source_fee_witness = L2VaultUpdateWitness(
            balance_before=settlement_witness.vault_diffs[vault_diff_idx].prev.balance
        )
        vault_diff_idx += 1

    # Both order L1 and L2 (with fee) have an L2 vault as the fee destination vault, and thus,
    # a corresponding L2VaultUpdateWitness.
    destination_fee_witness = L2VaultUpdateWitness(
        balance_before=settlement_witness.vault_diffs[vault_diff_idx].prev.balance
    )
    return (
        FeeWitness(
            source_fee_witness=source_fee_witness, destination_fee_witness=destination_fee_witness
        ),
        vault_diff_idx + 1,
    )


def get_limit_order_struct(
    order: Order, segments: MemorySegmentManager, identifiers: IdentifierManager
) -> MaybeRelocatable:
    """
    Returns a pointer to an ExchangeLimitOrder initialized according to the values of the given
    order.
    """
    # Initialize fee related fields.
    if order.fee_info is None:
        fee_limit, fee_token_id, fee_src_vault = (0, 0, 0)
    else:
        fee_info = order.fee_info
        fee_limit, fee_token_id, fee_src_vault = (
            fee_info.fee_limit,
            fee_info.token_id,
            fee_info.source_vault_id,
        )

    # Initialize limit_order.
    if isinstance(order, OrderL1):
        signature = (0, 0)
        public_key = int(order.eth_address, 16)
    else:
        assert isinstance(order, OrderL2), f"Unsupported order type"
        signature = (order.signature.r, order.signature.s)
        public_key = order.public_key

    structs = CairoStructFactory(
        identifiers=identifiers,
        additional_imports=[
            "services.exchange.cairo.order.OrderBase",
            "services.exchange.cairo.signature_message_hashes.ExchangeLimitOrder",
        ],
    ).structs

    order_base = structs.OrderBase(
        nonce=order.nonce,
        public_key=public_key,
        expiration_timestamp=order.expiration_timestamp,
        signature_r=signature[0],
        signature_s=signature[1],
    )

    limit_order = structs.ExchangeLimitOrder(
        base=order_base,
        amount_buy=order.amount_buy,
        amount_sell=order.amount_sell,
        amount_fee=fee_limit,
        asset_id_buy=order.token_buy,
        asset_id_sell=order.token_sell,
        asset_id_fee=fee_token_id,
        vault_buy=order.vault_id_buy,
        vault_sell=order.vault_id_sell,
        vault_fee=fee_src_vault,
    )
    return segments.gen_arg(limit_order)


def get_fee_info_struct(
    fee_info_exchange: FeeInfoExchange, segments: MemorySegmentManager
) -> MaybeRelocatable:
    """
    Returns an address with the values of the given 'fee_info_exchange'.
    """
    return (
        0
        if fee_info_exchange is None
        else segments.gen_arg(
            [
                fee_info_exchange.fee_taken,
                fee_info_exchange.destination_vault_id,
                fee_info_exchange.destination_stark_key,
            ]
        )
    )
