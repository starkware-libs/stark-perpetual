from services.perpetual.cairo.definitions.constants import POSITION_MAX_SUPPORTED_N_ASSETS
from services.perpetual.cairo.definitions.objects import FundingIndex, FundingIndicesInfo
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.position.position import (
    Position, PositionAsset, check_request_public_key, check_valid_balance, position_new)
from starkware.cairo.common.find_element import search_sorted, search_sorted_lower
from starkware.cairo.common.math import assert_not_equal
from starkware.cairo.common.memcpy import memcpy

# Fetches the balance and cached funding index of a position asset if found.
# Otherwise, returns 0 balance and fetches funding index from global_funding_indices.
func get_old_asset(
        range_check_ptr, asset_ptr : PositionAsset*, asset_found,
        global_funding_indices : FundingIndicesInfo*, asset_id) -> (
        range_check_ptr, balance, funding_index, return_code):
    if asset_found != 0:
        # Asset found.
        return (
            range_check_ptr=range_check_ptr,
            balance=asset_ptr.balance,
            funding_index=asset_ptr.cached_funding_index,
            return_code=PerpetualErrorCode.SUCCESS)
    end

    # Previous asset missing => initial balance is zero.
    # Find funding index.
    let (found_funding_index : FundingIndex*, success) = search_sorted{
        range_check_ptr=range_check_ptr}(
        array_ptr=global_funding_indices.funding_indices,
        elm_size=FundingIndex.SIZE,
        n_elms=global_funding_indices.n_funding_indices,
        key=asset_id)
    if success == 0:
        return (
            range_check_ptr=range_check_ptr,
            balance=0,
            funding_index=0,
            return_code=PerpetualErrorCode.ERROR)
    end

    return (
        range_check_ptr=range_check_ptr,
        balance=0,
        funding_index=found_funding_index.funding_index,
        return_code=PerpetualErrorCode.SUCCESS)
end

# Builds the result position assets array after adding delta to the original assets array at
# asset_id.
func add_asset_inner(
        range_check_ptr, n_assets, assets_ptr : PositionAsset*, res_ptr : PositionAsset*,
        global_funding_indices : FundingIndicesInfo*, asset_id, delta) -> (
        range_check_ptr, end_ptr : PositionAsset*, return_code):
    alloc_locals
    # Split original assets array, around asset_id.
    let (left_end_ptr : PositionAsset*) = search_sorted_lower{range_check_ptr=range_check_ptr}(
        array_ptr=assets_ptr, elm_size=PositionAsset.SIZE, n_elms=n_assets, key=asset_id)
    # left_end_ptr is the pointer before current asset.
    local left_end_ptr : PositionAsset* = left_end_ptr
    let (right_start_ptr : PositionAsset*) = search_sorted_lower{range_check_ptr=range_check_ptr}(
        array_ptr=assets_ptr, elm_size=PositionAsset.SIZE, n_elms=n_assets, key=asset_id + 1)
    local range_check_ptr = range_check_ptr
    # right_start_ptr is the pointer after current asset.
    local right_start_ptr : PositionAsset* = right_start_ptr

    # Auxiliary variables.
    local assets_end_ptr : PositionAsset* = assets_ptr + n_assets * PositionAsset.SIZE
    local left_size = left_end_ptr - assets_ptr
    local right_size = assets_end_ptr - right_start_ptr
    local res_left_end : PositionAsset* = res_ptr + left_size

    # Compute current balance and funding index.
    let (range_check_ptr, balance, local funding_index, return_code) = get_old_asset(
        range_check_ptr=range_check_ptr,
        asset_ptr=left_end_ptr,
        asset_found=right_start_ptr - left_end_ptr,
        global_funding_indices=global_funding_indices,
        asset_id=asset_id)

    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, end_ptr=res_ptr, return_code=return_code)
    end

    # Check new balance validity.
    local new_balance = balance + delta
    let (local range_check_ptr, return_code) = check_valid_balance(
        range_check_ptr=range_check_ptr, balance=new_balance)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, end_ptr=res_ptr, return_code=return_code)
    end

    # Copy left portion.
    memcpy(dst=res_ptr, src=assets_ptr, len=left_size)

    # Don't write new asset if new balance is 0.
    if new_balance == 0:
        # Copy right portion.
        memcpy(dst=res_left_end, src=right_start_ptr, len=right_size)
        return (
            range_check_ptr=range_check_ptr,
            end_ptr=res_left_end + right_size,
            return_code=PerpetualErrorCode.SUCCESS)
    end

    # Write new asset.
    assert res_left_end.asset_id = asset_id
    assert res_left_end.balance = new_balance
    assert res_left_end.cached_funding_index = funding_index

    # Copy right portion.
    let res_right_start = res_left_end + PositionAsset.SIZE
    memcpy(dst=res_right_start, src=right_start_ptr, len=right_size)
    return (
        range_check_ptr=range_check_ptr,
        end_ptr=res_right_start + right_size,
        return_code=PerpetualErrorCode.SUCCESS)
end

# Changes an asset balance of a position by delta. delta may be negative. Handles non existing and
# empty assets correctly.
func position_add_asset(
        range_check_ptr, position : Position*, global_funding_indices : FundingIndicesInfo*,
        asset_id, delta, public_key) -> (range_check_ptr, position : Position*, return_code):
    # Allow invalid asset_id when delta == 0.
    if delta == 0:
        return (
            range_check_ptr=range_check_ptr,
            position=position,
            return_code=PerpetualErrorCode.SUCCESS)
    end

    local res_assets_ptr : PositionAsset*
    %{ ids.res_assets_ptr = segments.add() %}
    alloc_locals

    # Verify public_key.
    let (return_code) = check_request_public_key(
        position_public_key=position.public_key, request_public_key=public_key)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, position=position, return_code=return_code)
    end

    # Call add_asset_inner.
    let (local range_check_ptr, end_ptr : PositionAsset*, return_code) = add_asset_inner(
        range_check_ptr=range_check_ptr,
        n_assets=position.n_assets,
        assets_ptr=position.assets_ptr,
        res_ptr=res_assets_ptr,
        global_funding_indices=global_funding_indices,
        asset_id=asset_id,
        delta=delta)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, position=position, return_code=return_code)
    end

    tempvar res_n_assets = (end_ptr - res_assets_ptr) / PositionAsset.SIZE
    # A single position may not contain more than POSITION_MAX_SUPPORTED_N_ASSETS assets. We may
    # assert that (res_n_assets != POSITION_MAX_SUPPORTED_N_ASSETS + 1) instead of
    # (res_n_assets <= POSITION_MAX_SUPPORTED_N_ASSETS) since each transaction adds at most one
    # asset to a position and therefore checking for inequality is equivalent to comparing.
    if res_n_assets == POSITION_MAX_SUPPORTED_N_ASSETS + 1:
        return (
            range_check_ptr=range_check_ptr,
            position=position,
            return_code=PerpetualErrorCode.TOO_MANY_SYNTHETIC_ASSETS_IN_POSITION)
    end

    let (position : Position*) = position_new(
        public_key=public_key,
        collateral_balance=position.collateral_balance,
        n_assets=res_n_assets,
        assets_ptr=res_assets_ptr,
        funding_timestamp=position.funding_timestamp)
    return (
        range_check_ptr=range_check_ptr, position=position, return_code=PerpetualErrorCode.SUCCESS)
end
