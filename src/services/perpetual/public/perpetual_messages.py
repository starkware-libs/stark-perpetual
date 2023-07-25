from typing import Callable

from mypy_extensions import VarArg
from web3 import Web3

from starkware.crypto.signature.signature import pedersen_hash
from starkware.python.utils import from_bytes

LIMIT_ORDER_WITH_FEES = 3
TRANSFER = 4
CONDITIONAL_TRANSFER = 5
WITHDRAWAL_TO_ADDRESS = 7


def build_condition(fact_registry_address: str, fact: bytes) -> int:
    """
    Creates a condition from a fact registry address and a fact.
    """
    condition_keccak = Web3.solidityKeccak(["address", "bytes32"], [fact_registry_address, fact])
    # Reduced to 250 LSB to be a field element.
    return from_bytes(condition_keccak) & (2**250 - 1)


def get_conditional_transfer_msg(
    asset_id: int,
    asset_id_fee: int,
    receiver_public_key: int,
    condition: int,
    sender_position_id: int,
    receiver_position_id: int,
    src_fee_position_id: int,
    nonce: int,
    amount: int,
    max_amount_fee: int,
    expiration_timestamp: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    assert 0 <= amount < 2**64
    assert 0 <= asset_id < 2**250
    assert 0 <= asset_id_fee < 2**250
    assert 0 <= condition < 2**251
    assert 0 <= expiration_timestamp < 2**32
    assert 0 <= src_fee_position_id < 2**64
    assert 0 <= max_amount_fee < 2**64
    assert 0 <= nonce < 2**32
    assert 0 <= receiver_position_id < 2**64
    assert 0 <= receiver_public_key < 2**251
    assert 0 <= sender_position_id < 2**64

    return get_conditional_transfer_msg_without_bounds(
        asset_id,
        asset_id_fee,
        receiver_public_key,
        condition,
        sender_position_id,
        receiver_position_id,
        src_fee_position_id,
        nonce,
        amount,
        max_amount_fee,
        expiration_timestamp,
        hash_function=hash_function,
    )


def get_conditional_transfer_msg_without_bounds(
    asset_id: int,
    asset_id_fee: int,
    receiver_public_key: int,
    condition: int,
    sender_position_id: int,
    receiver_position_id: int,
    src_fee_position_id: int,
    nonce: int,
    amount: int,
    max_amount_fee: int,
    expiration_timestamp: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    msg = hash_function(asset_id, asset_id_fee)
    msg = hash_function(msg, receiver_public_key)
    msg = hash_function(msg, condition)

    packed_message0 = sender_position_id
    packed_message0 = packed_message0 * 2**64 + receiver_position_id
    packed_message0 = packed_message0 * 2**64 + src_fee_position_id
    packed_message0 = packed_message0 * 2**32 + nonce
    msg = hash_function(msg, packed_message0)
    packed_message1 = CONDITIONAL_TRANSFER
    packed_message1 = packed_message1 * 2**64 + amount
    packed_message1 = packed_message1 * 2**64 + max_amount_fee
    packed_message1 = packed_message1 * 2**32 + expiration_timestamp
    packed_message1 = packed_message1 * 2**81  # Padding.
    return hash_function(msg, packed_message1)


def get_transfer_msg(
    asset_id: int,
    asset_id_fee: int,
    receiver_public_key: int,
    sender_position_id: int,
    receiver_position_id: int,
    src_fee_position_id: int,
    nonce: int,
    amount: int,
    max_amount_fee: int,
    expiration_timestamp: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    assert 0 <= amount < 2**64
    assert 0 <= asset_id < 2**250
    assert 0 <= asset_id_fee < 2**250
    assert 0 <= expiration_timestamp < 2**32
    assert 0 <= max_amount_fee < 2**64
    assert 0 <= nonce < 2**32
    assert 0 <= receiver_position_id < 2**64
    assert 0 <= receiver_public_key < 2**251
    assert 0 <= sender_position_id < 2**64
    assert 0 <= src_fee_position_id < 2**64

    return get_transfer_msg_without_bounds(
        asset_id,
        asset_id_fee,
        receiver_public_key,
        sender_position_id,
        receiver_position_id,
        src_fee_position_id,
        nonce,
        amount,
        max_amount_fee,
        expiration_timestamp,
        hash_function=hash_function,
    )


def get_transfer_msg_without_bounds(
    asset_id: int,
    asset_id_fee: int,
    receiver_public_key: int,
    sender_position_id: int,
    receiver_position_id: int,
    src_fee_position_id: int,
    nonce: int,
    amount: int,
    max_amount_fee: int,
    expiration_timestamp: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    msg = hash_function(asset_id, asset_id_fee)
    msg = hash_function(msg, receiver_public_key)

    packed_message0 = sender_position_id
    packed_message0 = packed_message0 * 2**64 + receiver_position_id
    packed_message0 = packed_message0 * 2**64 + src_fee_position_id
    packed_message0 = packed_message0 * 2**32 + nonce
    msg = hash_function(msg, packed_message0)
    packed_message1 = TRANSFER
    packed_message1 = packed_message1 * 2**64 + amount
    packed_message1 = packed_message1 * 2**64 + max_amount_fee
    packed_message1 = packed_message1 * 2**32 + expiration_timestamp
    packed_message1 = packed_message1 * 2**81  # Padding.
    return hash_function(msg, packed_message1)


def get_withdrawal_to_address_msg(
    asset_id_collateral: int,
    position_id: int,
    eth_address: str,
    nonce: int,
    expiration_timestamp: int,
    amount: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    assert 0 <= asset_id_collateral < 2**250
    assert 0 <= nonce < 2**32
    assert 0 <= position_id < 2**64
    assert 0 <= expiration_timestamp < 2**32
    assert 0 <= amount < 2**64
    assert 0 <= int(eth_address, 16) < 2**160

    return get_withdrawal_to_address_msg_without_bounds(
        asset_id_collateral,
        position_id,
        eth_address,
        nonce,
        expiration_timestamp,
        amount,
        hash_function=hash_function,
    )


def get_withdrawal_to_address_msg_without_bounds(
    asset_id_collateral: int,
    position_id: int,
    eth_address: str,
    nonce: int,
    expiration_timestamp: int,
    amount: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    eth_address_int = int(eth_address, 16)

    packed_message = WITHDRAWAL_TO_ADDRESS
    packed_message = packed_message * 2**64 + position_id
    packed_message = packed_message * 2**32 + nonce
    packed_message = packed_message * 2**64 + amount
    packed_message = packed_message * 2**32 + expiration_timestamp
    packed_message = packed_message * 2**49  # Padding.
    return hash_function(hash_function(asset_id_collateral, eth_address_int), packed_message)


def get_limit_order_msg(
    asset_id_synthetic: int,
    asset_id_collateral: int,
    is_buying_synthetic: int,
    asset_id_fee: int,
    amount_synthetic: int,
    amount_collateral: int,
    max_amount_fee: int,
    nonce: int,
    position_id: int,
    expiration_timestamp: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    # Synthetic asset IDs are generated by the exchange based on other crypto currency counterparts.
    assert 0 <= asset_id_synthetic < 2**128
    # Collateral asset ID is linked to a smart contract as part of its hash_function. Its range is
    # larger than synthetic asset IDs in order to reduce the chance of a collision of IDs.
    assert 0 <= asset_id_collateral < 2**250
    assert 0 <= asset_id_fee < 2**250
    assert 0 <= amount_synthetic < 2**64
    assert 0 <= amount_collateral < 2**64
    assert 0 <= max_amount_fee < 2**64
    assert 0 <= nonce < 2**32
    assert 0 <= position_id < 2**64
    assert 0 <= expiration_timestamp < 2**32

    return get_limit_order_msg_without_bounds(
        asset_id_synthetic,
        asset_id_collateral,
        is_buying_synthetic,
        asset_id_fee,
        amount_synthetic,
        amount_collateral,
        max_amount_fee,
        nonce,
        position_id,
        expiration_timestamp,
        hash_function=hash_function,
    )


def get_limit_order_msg_without_bounds(
    asset_id_synthetic: int,
    asset_id_collateral: int,
    is_buying_synthetic: int,
    asset_id_fee: int,
    amount_synthetic: int,
    amount_collateral: int,
    max_amount_fee: int,
    nonce: int,
    position_id: int,
    expiration_timestamp: int,
    hash_function: Callable[[VarArg(int)], int] = pedersen_hash,
) -> int:
    if is_buying_synthetic:
        asset_id_sell, asset_id_buy = asset_id_collateral, asset_id_synthetic
        amount_sell, amount_buy = amount_collateral, amount_synthetic
    else:
        asset_id_sell, asset_id_buy = asset_id_synthetic, asset_id_collateral
        amount_sell, amount_buy = amount_synthetic, amount_collateral

    msg = hash_function(asset_id_sell, asset_id_buy)
    msg = hash_function(msg, asset_id_fee)
    packed_message0 = amount_sell
    packed_message0 = packed_message0 * 2**64 + amount_buy
    packed_message0 = packed_message0 * 2**64 + max_amount_fee
    packed_message0 = packed_message0 * 2**32 + nonce
    msg = hash_function(msg, packed_message0)
    packed_message1 = LIMIT_ORDER_WITH_FEES
    packed_message1 = packed_message1 * 2**64 + position_id
    packed_message1 = packed_message1 * 2**64 + position_id
    packed_message1 = packed_message1 * 2**64 + position_id
    packed_message1 = packed_message1 * 2**32 + expiration_timestamp
    packed_message1 = packed_message1 * 2**17  # Padding.
    return hash_function(msg, packed_message1)


#####################################################################################
# get_price_msg: gets as input:                                                     #
#   oracle: a 40-bit number, describes the oracle (e.g., hex encoding of "Maker")   #
#   price: a 120-bit number                                                         #
#   asset: a 211-bit number                                                         #
#   timestamp: a 32 bit number, represents seconds since Unix epoch                 #
# Outputs a number which is less than FIELD_PRIME, which can be used as data        #
# to sign on in the sign method. This number is obtained by applying pedersen hash  #
# on the following two numbers:                                                     #
#                                                                                   #
# first number:                                                                     #
# --------------------------------------------------------------------------------- #
# | asset_name (rest of the number)  - 211 bits       |   oracle_name (40 bits)   | #
# --------------------------------------------------------------------------------- #
#                                                                                   #
# second number:                                                                    #
# --------------------------------------------------------------------------------- #
# | 0 (92 bits)         | price (120 bits)              |   timestamp (32 bits)   | #
# --------------------------------------------------------------------------------- #
#####################################################################################


def get_price_msg(
    oracle_name: int, asset_pair: int, timestamp: int, price: int, hash_function=pedersen_hash
):
    assert 0 <= oracle_name < 2**40
    assert 0 <= asset_pair < 2**128
    assert 0 <= timestamp < 2**32
    assert 0 <= price < 2**120

    # The first number to hash_function is the oracle name (e.g., Maker) in the 40 LSB, then the
    # asset name.
    first_number = (asset_pair << 40) + oracle_name

    # The second number is timestamp in the 32 LSB, then the price.
    second_number = (price << 32) + timestamp

    return hash_function(first_number, second_number)
