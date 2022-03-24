from services.perpetual.cairo.definitions.constants import (
    BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND, FUNDING_INDEX_LOWER_BOUND, FUNDING_INDEX_UPPER_BOUND,
    N_ASSETS_UPPER_BOUND)
from services.perpetual.cairo.position.position import Position, PositionAsset
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2

# Inner tail recursive function for position_hash.
#
# Assumptions:
# assets.asset_id < ASSET_ID_UPPER_BOUND (Enforced by the solidity contract).
# FUNDING_INDEX_LOWER_BOUND <= assets.cached_funding_index < FUNDING_INDEX_UPPER_BOUND
# BALANCE_LOWER_BOUND <= assets.balance < BALANCE_UPPER_BOUND.
# ASSET_ID_UPPER_BOUND * (FUNDING_INDEX_UPPER_BOUND - FUNDING_INDEX_LOWER_BOUND) * (
#    BALANCE_UPPER_BOUND - BALANCE_LOWER_BOUND) < PRIME
func position_hash_assets{pedersen_ptr : HashBuiltin*}(
        assets : PositionAsset*, n_assets, current_hash) -> (assets_hash):
    if n_assets == 0:
        return (assets_hash=current_hash)
    end

    let asset_packed = assets.asset_id
    let asset_packed = asset_packed * (
        FUNDING_INDEX_UPPER_BOUND - FUNDING_INDEX_LOWER_BOUND) + (
        assets.cached_funding_index - FUNDING_INDEX_LOWER_BOUND)
    let asset_packed = asset_packed * (BALANCE_UPPER_BOUND - BALANCE_LOWER_BOUND) +
        (assets.balance - BALANCE_LOWER_BOUND)

    let (result) = hash2{hash_ptr=pedersen_ptr}(x=current_hash, y=asset_packed)

    # Call recursively.
    return position_hash_assets(
        assets=assets + PositionAsset.SIZE, n_assets=n_assets - 1, current_hash=result)
end

# Computes the hash of the position.
#
# Arguments:
# pedersen_ptr - a pedersen builtin pointer.
# position - a pointer to Position.
#
# Returns:
# pedersen_ptr - new pedersen builtin pointer.
# position_hash - the hash of the position
#
# Assumptions:
# The assets are sorted by asset_id.
# The position_hash_assets assumptions hold for all the assets.
func position_hash{pedersen_ptr : HashBuiltin*}(position : Position*) -> (position_hash):
    let (assets_hash) = position_hash_assets(
        assets=position.assets_ptr, n_assets=position.n_assets, current_hash=0)

    # Hash the assests_hash with the public key.
    let (result) = hash2{hash_ptr=pedersen_ptr}(x=assets_hash, y=position.public_key)

    # Hash the above with the biased collateral balance and the number of assets.
    let (result) = hash2{hash_ptr=pedersen_ptr}(
        x=result,
        y=(position.collateral_balance - BALANCE_LOWER_BOUND) * N_ASSETS_UPPER_BOUND +
        position.n_assets)

    return (position_hash=result)
end

func hash_position_updates_inner{pedersen_ptr : HashBuiltin*}(
        update_ptr : DictAccess*, n_updates, hashed_updates_ptr : DictAccess*) -> ():
    if n_updates == 0:
        return ()
    end

    assert hashed_updates_ptr.key = update_ptr.key

    # Previous position hash.
    let prev_position = cast(update_ptr.prev_value, Position*)
    let (hashed_position) = position_hash(position=prev_position)
    assert hashed_updates_ptr.prev_value = hashed_position

    # Touch funding_timestamp.
    tempvar funding_timestamp = prev_position.funding_timestamp

    # New position hash.
    # A non-deterministic jump is used here to make the code more efficient.
    # Soundness is guaranteed by asserting update_ptr.prev_value = update_ptr.new_value in the equal
    # branch. In the not_equal branch it does not matter if they are equal or not.
    %{ memory[ap] = 1 if ids.update_ptr.prev_value != ids.update_ptr.new_value else 0 %}
    jmp not_equal if [ap] != 0; ap++

    equal:
    # Same as previous. Do not recompute hash.
    assert update_ptr.prev_value = update_ptr.new_value
    assert hashed_updates_ptr.new_value = hashed_position
    return hash_position_updates_inner(
        update_ptr=update_ptr + DictAccess.SIZE,
        n_updates=n_updates - 1,
        hashed_updates_ptr=hashed_updates_ptr + DictAccess.SIZE)

    not_equal:
    # Recompute hash.
    let (hashed_position) = position_hash(position=cast(update_ptr.new_value, Position*))
    assert hashed_updates_ptr.new_value = hashed_position
    return hash_position_updates_inner(
        update_ptr=update_ptr + DictAccess.SIZE,
        n_updates=n_updates - 1,
        hashed_updates_ptr=hashed_updates_ptr + DictAccess.SIZE)
end

# Converts a dict of positions into a dict of position hashes.
func hash_position_updates{pedersen_ptr : HashBuiltin*}(update_ptr : DictAccess*, n_updates) -> (
        hashed_updates_ptr : DictAccess*):
    alloc_locals
    let (local hashed_updates_ptr : DictAccess*) = alloc()
    hash_position_updates_inner(
        update_ptr=update_ptr, n_updates=n_updates, hashed_updates_ptr=hashed_updates_ptr)
    return (hashed_updates_ptr=hashed_updates_ptr)
end
