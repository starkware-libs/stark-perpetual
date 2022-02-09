from services.perpetual.cairo.definitions.constants import BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.position.position import Position, PositionAsset
from starkware.cairo.common.math_cmp import is_le, is_nn

# Inner function for check_smaller_in_synthetic_holdings_inner. Checks a single asset and then
# recursively checks the rest.
func check_smaller_in_synthetic_holdings_inner(
        range_check_ptr, n_updated_position_assets, updated_position_assets : PositionAsset*,
        n_initial_position_assets, initial_position_assets : PositionAsset*) -> (
        range_check_ptr, return_code):
    if n_updated_position_assets == 0:
        # At this point, we've either passed on all initial assets and updated assets, or there are
        # remaining assets in the initial position that have been removed from the updated position,
        # which means they are valid because their updated balance is 0.
        return (range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.SUCCESS)
    end
    if n_initial_position_assets == 0:
        # There is a new synthetic asset. Therefore the position is not smaller in synthetic
        # holdings.
        return (
            range_check_ptr=range_check_ptr,
            return_code=PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_ENLARGING_SYNTHETIC_HOLDINGS)
    end

    alloc_locals
    local updated_balance = updated_position_assets.balance
    local initial_balance = initial_position_assets.balance

    if updated_position_assets.asset_id != initial_position_assets.asset_id:
        # Because the asset ids are sorted, we can assume that the initial position's asset id
        # doesn't exist in the updated position. (If that isn't true then we will eventually have
        # n_initial_position_assets == 0).
        # This means that the initial position's asset has updated balance 0 and we can skip it.
        return check_smaller_in_synthetic_holdings_inner(
            range_check_ptr=range_check_ptr,
            n_updated_position_assets=n_updated_position_assets,
            updated_position_assets=updated_position_assets,
            n_initial_position_assets=n_initial_position_assets - 1,
            initial_position_assets=initial_position_assets + PositionAsset.SIZE)
    end

    # Check that updated_balance and initial_balance have the same sign.
    # They cannot be zero at this point.
    let (success) = is_nn{range_check_ptr=range_check_ptr}(updated_balance * initial_balance)
    if success == 0:
        return (
            range_check_ptr=range_check_ptr,
            return_code=PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_ENLARGING_SYNTHETIC_HOLDINGS)
    end

    # Check that abs(updated_balance) <= abs(initial_balance) using
    # (updated_balance^2) <= (initial_balance^2).
    # See the assumption in check_smaller_in_synthetic_holdings.
    let (success) = is_le{range_check_ptr=range_check_ptr}(
        updated_balance * updated_balance, initial_balance * initial_balance)
    if success == 0:
        return (
            range_check_ptr=range_check_ptr,
            return_code=PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_ENLARGING_SYNTHETIC_HOLDINGS)
    end

    return check_smaller_in_synthetic_holdings_inner(
        range_check_ptr=range_check_ptr,
        n_updated_position_assets=n_updated_position_assets - 1,
        updated_position_assets=updated_position_assets + PositionAsset.SIZE,
        n_initial_position_assets=n_initial_position_assets - 1,
        initial_position_assets=initial_position_assets + PositionAsset.SIZE)
end

# Checks that updated_position is as safe as the initial position.
# This means that the balance of each asset did not change sign, and its absolute value
# did not increase.
# Returns 1 if the check passes, 0 otherwise.
#
# Assumption:
#    All the asset balances are in the range [BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND).
#    The position's assets are sorted by asset id.
#    max(BALANCE_LOWER_BOUND**2, (BALANCE_UPPER_BOUND - 1)**2) < range_check_builtin.bound.
func check_smaller_in_synthetic_holdings(
        range_check_ptr, updated_position : Position*, initial_position : Position*) -> (
        range_check_ptr, return_code):
    %{
        assert max(
           ids.BALANCE_LOWER_BOUND**2, (ids.BALANCE_UPPER_BOUND - 1)**2) < range_check_builtin.bound
    %}
    return check_smaller_in_synthetic_holdings_inner(
        range_check_ptr=range_check_ptr,
        n_updated_position_assets=updated_position.n_assets,
        updated_position_assets=updated_position.assets_ptr,
        n_initial_position_assets=initial_position.n_assets,
        initial_position_assets=initial_position.assets_ptr)
end
