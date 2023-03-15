from services.perpetual.cairo.definitions.constants import BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from starkware.cairo.common.find_element import search_sorted
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.math_cmp import is_nn_le
from starkware.cairo.common.registers import get_fp_and_pc

// Represents a specific asset in a user position.
struct PositionAsset {
    asset_id: felt,
    balance: felt,
    // A snapshot of the funding index at the last time that funding was applied (fxp 32.32).
    cached_funding_index: felt,
}

// A user position.
struct Position {
    public_key: felt,
    collateral_balance: felt,
    n_assets: felt,
    assets_ptr: PositionAsset*,
    // funding_timestamp is an auxiliary field that keeps the funding timestamp of funded positions.
    // The invariant is that every position we change must have the correct funding_timestamp.
    // Note however that it is not a part of the position hash, and thus, we cannot trust this value
    // for positions not created during the current run (e.g. previous position in the state).
    funding_timestamp: felt,
}

func position_new(
    public_key, collateral_balance, n_assets, assets_ptr: PositionAsset*, funding_timestamp
) -> (position: Position*) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as a Position object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (position=cast(fp_val - 2 - Position.SIZE, Position*));
}

// If the position is empty (collateral_balance == n_assets == 0) returns an empty position with a
// zero public_key. Otherwise, returns the given position.
// The input's public_key must be non-zero.
func create_maybe_empty_position(initial_position: Position*) -> (position: Position*) {
    assert_not_zero(initial_position.public_key);

    tempvar collateral_balance = initial_position.collateral_balance;
    tempvar n_assets = initial_position.n_assets;
    jmp assign_position if collateral_balance != 0;
    jmp assign_position if n_assets != 0;
    return position_new(0, 0, 0, cast(0, PositionAsset*), 0);

    assign_position:
    return (position=initial_position);
}

// Checks that the public key supplied in a request to change the position is valid.
// The public key is valid if it matches the position's public key or if the position is empty
// (public key is zero).
// The supplied key may not be zero.
// Return 0 if the check passed, otherwise returns an error code that describes the failure.
func check_request_public_key(position_public_key, request_public_key) -> (return_code: felt) {
    if (request_public_key == 0) {
        // Invalid request_public_key.
        return (return_code=PerpetualErrorCode.INVALID_PUBLIC_KEY);
    }
    if (position_public_key == 0) {
        // Initial position is empty.
        return (return_code=PerpetualErrorCode.SUCCESS);
    }
    if (position_public_key == request_public_key) {
        // Matching keys.
        return (return_code=PerpetualErrorCode.SUCCESS);
    }
    // Mismatching keys.
    return (return_code=PerpetualErrorCode.INVALID_PUBLIC_KEY);
}

// Checks that value is in the range [BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND).
func check_valid_balance(range_check_ptr, balance) -> (range_check_ptr: felt, return_code: felt) {
    let success = is_nn_le{range_check_ptr=range_check_ptr}(
        balance - BALANCE_LOWER_BOUND, BALANCE_UPPER_BOUND - BALANCE_LOWER_BOUND - 1
    );
    if (success == 0) {
        return (
            range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.OUT_OF_RANGE_BALANCE
        );
    }
    return (range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.SUCCESS);
}

// Changes the collateral balance of the position by delta. delta may be negative.
// If the position is empty, the new position will have the given public key.
// Assumption: Either public_key matches the position, or position is empty.
func position_add_collateral(range_check_ptr, position: Position*, delta, public_key) -> (
    range_check_ptr: felt, position: Position*, return_code: felt
) {
    alloc_locals;

    let (final_position: Position*) = position_new(
        public_key=public_key,
        collateral_balance=position.collateral_balance + delta,
        n_assets=position.n_assets,
        assets_ptr=position.assets_ptr,
        funding_timestamp=position.funding_timestamp,
    );

    let (range_check_ptr, return_code) = check_valid_balance(
        range_check_ptr=range_check_ptr, balance=final_position.collateral_balance
    );

    return (range_check_ptr=range_check_ptr, position=final_position, return_code=return_code);
}

// Gets the balance of a specific asset in the position.
func position_get_asset_balance(range_check_ptr, position: Position*, asset_id) -> (
    range_check_ptr: felt, balance: felt
) {
    let (position_asset_ptr: PositionAsset*, success) = search_sorted{
        range_check_ptr=range_check_ptr
    }(
        array_ptr=position.assets_ptr,
        elm_size=PositionAsset.SIZE,
        n_elms=position.n_assets,
        key=asset_id,
    );
    if (success == 0) {
        // Asset is not in the position. Therefore the balance of that asset is 0 in said position.
        return (range_check_ptr=range_check_ptr, balance=0);
    } else {
        return (range_check_ptr=range_check_ptr, balance=position_asset_ptr.balance);
    }
}
