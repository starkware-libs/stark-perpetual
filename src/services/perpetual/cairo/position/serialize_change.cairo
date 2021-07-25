from services.perpetual.cairo.definitions.constants import (
    ASSET_ID_UPPER_BOUND, BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND)
from services.perpetual.cairo.position.position import Position, PositionAsset
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_le, is_nn
from starkware.cairo.common.serialize import serialize_word

# Serializes a position asset for the on-chain data availability.
#
# Assumptions:
#   asset_id < ASSET_ID_UPPER_BOUND.
#   BALANCE_LOWER_BOUND <= assets.balance < BALANCE_UPPER_BOUND.
#   ASSET_ID_UPPER_BOUND * (BALANCE_UPPER_BOUND - BALANCE_LOWER_BOUND) < PRIME.
func serialize_asset{output_ptr : felt*}(asset_id, balance):
    serialize_word(
        asset_id * (BALANCE_UPPER_BOUND - BALANCE_LOWER_BOUND) + (balance - BALANCE_LOWER_BOUND))
    return ()
end

# return assets_ptr.asset_id if n_asset != 0 and ASSET_ID_UPPER_BOUND otherwise.
func get_asset_id_or_bound(n_asset, assets_ptr : PositionAsset*) -> (asset_id):
    if n_asset != 0:
        return (asset_id=assets_ptr.asset_id)
    else:
        return (asset_id=ASSET_ID_UPPER_BOUND)
    end
end

# Inner function for serialize_position_change.
# Serializes the changes of the position assets.
func serialize_position_change_inner(
        range_check_ptr, output_ptr : felt*, n_prev_position_assets,
        prev_position_assets : PositionAsset*, n_new_position_assets,
        new_position_assets : PositionAsset*) -> (range_check_ptr, output_ptr : felt*):
    let (prev_asset_id) = get_asset_id_or_bound(n_prev_position_assets, prev_position_assets)
    let (new_asset_id) = get_asset_id_or_bound(n_new_position_assets, new_position_assets)

    if prev_asset_id == new_asset_id:
        # Both PositionAsset arrays are empty, we are done.
        if prev_asset_id == ASSET_ID_UPPER_BOUND:
            return (range_check_ptr=range_check_ptr, output_ptr=output_ptr)
        end

        if new_position_assets.balance != prev_position_assets.balance:
            with output_ptr:
                serialize_asset(asset_id=new_asset_id, balance=new_position_assets.balance)
            end
        else:
            tempvar output_ptr = output_ptr
        end

        return serialize_position_change_inner(
            range_check_ptr=range_check_ptr,
            output_ptr=output_ptr,
            n_prev_position_assets=n_prev_position_assets - 1,
            prev_position_assets=prev_position_assets + PositionAsset.SIZE,
            n_new_position_assets=n_new_position_assets - 1,
            new_position_assets=new_position_assets + PositionAsset.SIZE)
    end

    let (asset_was_deleted) = is_le{range_check_ptr=range_check_ptr}(prev_asset_id, new_asset_id)
    if asset_was_deleted != 0:
        with output_ptr:
            serialize_asset(asset_id=prev_position_assets.asset_id, balance=0)
        end

        return serialize_position_change_inner(
            range_check_ptr=range_check_ptr,
            output_ptr=output_ptr,
            n_prev_position_assets=n_prev_position_assets - 1,
            prev_position_assets=prev_position_assets + PositionAsset.SIZE,
            n_new_position_assets=n_new_position_assets,
            new_position_assets=new_position_assets)
    end

    # Asset was added.
    with output_ptr:
        serialize_asset(asset_id=new_position_assets.asset_id, balance=new_position_assets.balance)
    end

    return serialize_position_change_inner(
        range_check_ptr=range_check_ptr,
        output_ptr=output_ptr,
        n_prev_position_assets=n_prev_position_assets,
        prev_position_assets=prev_position_assets,
        n_new_position_assets=n_new_position_assets - 1,
        new_position_assets=new_position_assets + PositionAsset.SIZE)
end

# Outputs the changes between the positions in dict_access.
func serialize_position_change(range_check_ptr, output_ptr : felt*, dict_access : DictAccess*) -> (
        range_check_ptr, output_ptr : felt*):
    alloc_locals
    local output_start_ptr : felt* = output_ptr
    tempvar prev_position = cast(dict_access.prev_value, Position*)
    tempvar new_position = cast(dict_access.new_value, Position*)

    # Leaving space for length.
    let output_ptr = output_ptr + 1
    with output_ptr:
        serialize_word(dict_access.key)
        serialize_word(new_position.public_key)
        serialize_word(new_position.collateral_balance - BALANCE_LOWER_BOUND)
        serialize_word(new_position.funding_timestamp)
    end

    let (range_check_ptr, output_ptr) = serialize_position_change_inner(
        range_check_ptr=range_check_ptr,
        output_ptr=output_ptr,
        n_prev_position_assets=prev_position.n_assets,
        prev_position_assets=prev_position.assets_ptr,
        n_new_position_assets=new_position.n_assets,
        new_position_assets=new_position.assets_ptr)

    let size = cast(output_ptr, felt) - cast(output_start_ptr, felt) - 1
    serialize_word{output_ptr=output_start_ptr}(size)

    return (range_check_ptr=range_check_ptr, output_ptr=output_ptr)
end
