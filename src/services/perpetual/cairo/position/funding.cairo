from services.perpetual.cairo.definitions.constants import (
    BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND, FXP_32_ONE)
from services.perpetual.cairo.definitions.objects import FundingIndex, FundingIndicesInfo
from services.perpetual.cairo.position.position import Position, PositionAsset, position_new
from starkware.cairo.common.find_element import find_element
from starkware.cairo.common.math import assert_nn_le, signed_div_rem
from starkware.cairo.common.registers import get_fp_and_pc

# Computes the total_funding for a given position and updates the cached funding indices.
# The funding per asset is computed as:
#   (global_funding_index - cached_funding_index) * balance.
#
# Arguments:
# range_check_ptr - range check builtin pointer.
# assets_before - a pointer to PositionAsset array.
# global_funding_indices - a pointer to a FundingIndicesInfo.
# current_collateral_fxp - Current collateral as signed (.32) fixed point.
# assets_after - a pointer to an output array, which will be filled with
# the same assets as assets_before but with an updated cached_funding_index.
#
# Returns:
# range_check_ptr - new range check builtin pointer.
# collateral_fxp - The colleteral after the funding was applied as signed (.32) fixed point.
#
# Assumption: current_collateral_fxp does not overflow, it is a sum of 95 bit values.
# Prover assumption: The assets in assets_before are a subset of the assets in
# global_funding_indices.
func apply_funding_inner(
        range_check_ptr, assets_before : PositionAsset*, n_assets,
        global_funding_indices : FundingIndicesInfo*, current_collateral_fxp,
        assets_after : PositionAsset*) -> (range_check_ptr, collateral_fxp):
    jmp body if n_assets != 0

    # Return.
    return (range_check_ptr=range_check_ptr, collateral_fxp=current_collateral_fxp)

    body:
    alloc_locals
    let current_asset : PositionAsset* = assets_before

    local asset_id = current_asset.asset_id

    # The key must be at offset 0.
    static_assert FundingIndex.asset_id == 0
    let (funding_index : FundingIndex*) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=global_funding_indices.funding_indices,
        elm_size=FundingIndex.SIZE,
        n_elms=global_funding_indices.n_funding_indices,
        key=asset_id)

    tempvar global_funding_index = funding_index.funding_index

    # Compute fixed point fxp_delta_funding := delta_funding_index * balance.
    tempvar balance = current_asset.balance
    tempvar delta_funding_index = global_funding_index - current_asset.cached_funding_index
    tempvar fxp_delta_funding = delta_funding_index * balance

    # Copy asset to assets_after with an updated cached_funding_index.
    let asset_after : PositionAsset* = assets_after
    asset_after.asset_id = asset_id
    asset_after.cached_funding_index = global_funding_index
    asset_after.balance = balance

    # Call recursively.
    return apply_funding_inner(
        range_check_ptr=range_check_ptr,
        assets_before=assets_before + PositionAsset.SIZE,
        n_assets=n_assets - 1,
        global_funding_indices=global_funding_indices,
        current_collateral_fxp=current_collateral_fxp - fxp_delta_funding,
        assets_after=assets_after + PositionAsset.SIZE)
end

# Change the cached funding indices in the position into the updated funding indices and update the
# collateral balance according to the funding diff.
func position_apply_funding(
        range_check_ptr, position : Position*, global_funding_indices : FundingIndicesInfo*) -> (
        range_check_ptr, position : Position*):
    local new_assets_ptr : PositionAsset*
    alloc_locals

    %{
        ids.new_assets_ptr = new_assets_ptr = segments.add()
        segments.finalize(
            new_assets_ptr.segment_index,
            ids.position.n_assets * ids.PositionAsset.SIZE)
    %}

    let (range_check_ptr, collateral_fxp) = apply_funding_inner(
        range_check_ptr=range_check_ptr,
        assets_before=position.assets_ptr,
        n_assets=position.n_assets,
        global_funding_indices=global_funding_indices,
        current_collateral_fxp=position.collateral_balance * FXP_32_ONE,
        assets_after=new_assets_ptr)

    # Convert collateral_fxp from fixed points to an integer and range check that
    # BALANCE_LOWER_BOUND <= collateral_balance < BALANCE_UPPER_BOUND.
    static_assert BALANCE_LOWER_BOUND == -BALANCE_UPPER_BOUND
    # The collateral changes due to funding over all positions always sum up to 0
    # (Assuming no rounding). Therefore the collateral delta is rounded down to make sure funding
    # does not make collateral out of thin air.
    # For example if we have 3 users a, b and c and the computed funding is as follows:
    # a = -0.5, b = -0.5, c = 1, we round the funding down to a = -1, b = -1 and c = 1 and therefore
    # we lose 1 collateral in the system from funding
    # (If instead we rounded up we would've created 1).
    let (new_collateral_balance, _) = signed_div_rem{range_check_ptr=range_check_ptr}(
        value=collateral_fxp, div=FXP_32_ONE, bound=BALANCE_UPPER_BOUND)

    let (updated_position) = position_new(
        public_key=position.public_key,
        collateral_balance=new_collateral_balance,
        n_assets=position.n_assets,
        assets_ptr=new_assets_ptr,
        funding_timestamp=global_funding_indices.funding_timestamp)

    return (range_check_ptr=range_check_ptr, position=updated_position)
end
