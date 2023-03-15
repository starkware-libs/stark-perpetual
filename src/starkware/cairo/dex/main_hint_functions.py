import dataclasses
from typing import Dict, List, Tuple

from common.objects.transaction.common_transaction import OrderL1, Party, SettlementInfo
from common.objects.transaction.raw_transaction import Settlement, Transaction
from services.starkex.definitions.transaction_type import UserVaultRole
from starkware.crypto.signature.signature import pedersen_hash


@dataclasses.dataclass(frozen=True)
class L1VaultKey:
    eth_key: int
    token_id: int
    vault_index: int

    def to_hash_input(self) -> Tuple[int, int]:
        """
        Returns an input to a hash function for creating a hashed key from this L1VaultKey.
        """
        return (self.vault_index << 160) | self.eth_key, self.token_id

    def to_tuple(self) -> Tuple[int, int, int]:
        return self.eth_key, self.token_id, self.vault_index

    @classmethod
    def from_order_l1(cls, order_l1: OrderL1, vault_role: UserVaultRole) -> "L1VaultKey":
        """
        Creates an L1VaultKey instance based on an OrderL1.
        vault_role is used to determine the desired vault to produce the key for, out of sell, buy
        and fee source.
        """
        eth_key = int(order_l1.eth_address, 16)
        if vault_role is UserVaultRole.SELL:
            return cls(
                eth_key=eth_key, token_id=order_l1.token_sell, vault_index=order_l1.vault_id_sell
            )
        elif vault_role is UserVaultRole.BUY:
            return cls(
                eth_key=eth_key, token_id=order_l1.token_buy, vault_index=order_l1.vault_id_buy
            )
        elif vault_role is UserVaultRole.FEE_SOURCE:
            assert order_l1.fee_info is not None, f"fee_info cannot be None in an L1 order."
            return cls(
                eth_key=eth_key,
                token_id=order_l1.fee_info.token_id,
                vault_index=order_l1.fee_info.source_vault_id,
            )
        else:
            raise NotImplementedError(f"Unsupported UserVaultRole.")


@dataclasses.dataclass
class L1VaultBalances:
    # The minimal temporary balance a vault reaches throughout the execution of a batch.
    min_balance: int
    # The balance at some point during the batch execution.
    current_balance: int


L1VaultKeysToBalance = Dict[L1VaultKey, L1VaultBalances]


def update_order_vaults(
    party: Party,
    order: OrderL1,
    settlement_info: SettlementInfo,
    balance_updates: L1VaultKeysToBalance,
):
    """
    Updates L1VaultBalances of an L1 vault according to the data in order.
    Used to compute the minimal balance a vault reaches throughout the execution of a batch if it
    starts with a balance of 0. The negation of this value (or zero if the value is non-negative)
    will be the minimal balance for the vault's output data.
    """
    amount_sold = settlement_info.get_amount_sold_by_party(party=party)
    amount_bought = settlement_info.get_amount_sold_by_party(party=party.other_party)
    fee_taken = settlement_info.get_fee_info_by_party(party=party).fee_taken

    # Update L1VaultBalances for each of vault roles in the order.
    for vault_role, diff in zip(
        (UserVaultRole.SELL, UserVaultRole.BUY, UserVaultRole.FEE_SOURCE),
        (-amount_sold, amount_bought, -fee_taken),
    ):
        l1_vault_key = L1VaultKey.from_order_l1(order_l1=order, vault_role=vault_role)

        # Get the vault L1VaultBalances computed so far. Initialize both balances to 0 if vault was
        # not yet seen.
        min_balance, current_balance = dataclasses.astuple(
            balance_updates.get(l1_vault_key, L1VaultBalances(min_balance=0, current_balance=0))
        )
        new_balance = current_balance + diff
        new_min_balance = min(new_balance, min_balance)

        balance_updates[l1_vault_key] = L1VaultBalances(
            min_balance=new_min_balance, current_balance=new_balance
        )


def update_l1_vault_balances(
    transactions: List[Transaction],
) -> Tuple[Dict[int, int], Dict[int, L1VaultKey]]:
    """
    Returns two dictionaries:
    1. A mapping from the hashed key of every L1 vault that appears in the given transaction list,
      to its minimal initial balance that will prevent a temporary negative balance throughout the
      execution of the transactions list (batch).
    2. A mapping from the hash key of every L1 vault to its L1VaultKey (the keys before the hash).
    """
    l1_vaults_balances: L1VaultKeysToBalance = {}
    for tx in transactions:
        if not isinstance(tx, Settlement):
            continue
        for party in Party:
            order = tx.get_order_by_party(party=party)
            if isinstance(order, OrderL1):
                update_order_vaults(
                    party=party,
                    order=order,
                    settlement_info=tx.settlement_info,
                    balance_updates=l1_vaults_balances,
                )

    # A mapping from the DictAccess keys (the hash of L1VaultKey), to the original
    # L1VaultKey.
    l1_vaults_min_balance: Dict[int, int] = {}
    l1_vault_hash_key_to_explicit: Dict[int, L1VaultKey] = {}
    for vault_key, balances in l1_vaults_balances.items():
        vault_hash_key = pedersen_hash(*vault_key.to_hash_input())
        l1_vault_hash_key_to_explicit[vault_hash_key] = vault_key
        l1_vaults_min_balance[vault_hash_key] = -balances.min_balance
    return l1_vaults_min_balance, l1_vault_hash_key_to_explicit
