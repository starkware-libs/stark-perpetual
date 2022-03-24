from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.objects import (
    FundingIndex, FundingIndicesInfo, OraclePrice, OraclePrices)
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.position.add_asset import position_add_asset
from services.perpetual.cairo.position.funding import position_apply_funding
from services.perpetual.cairo.position.position import (
    Position, check_request_public_key, position_add_collateral)
from services.perpetual.cairo.position.validate_state_transition import check_valid_transition
from starkware.cairo.common.dict import dict_update
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.find_element import search_sorted
from starkware.cairo.common.math import assert_not_zero

# An asset id representing that no asset id is changed.
const NO_SYNTHETIC_DELTA_ASSET_ID = -1

# Checks whether an asset can be traded. An asset can be traded iff it has a price and a funding
# index or if it is NO_SYNTHETIC_DELTA_ASSET_ID.
func is_asset_id_tradable(
        range_check_ptr, synthetic_asset_id, synthetic_delta,
        global_funding_indices : FundingIndicesInfo*, oracle_prices : OraclePrices*) -> (
        range_check_ptr, return_code):
    if synthetic_asset_id == NO_SYNTHETIC_DELTA_ASSET_ID:
        assert synthetic_delta = 0
        return (range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.SUCCESS)
    end
    let (_, success) = search_sorted{range_check_ptr=range_check_ptr}(
        array_ptr=oracle_prices.data,
        elm_size=OraclePrice.SIZE,
        n_elms=oracle_prices.len,
        key=synthetic_asset_id)
    if success == 0:
        return (
            range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.MISSING_ORACLE_PRICE)
    end
    let (_, success) = search_sorted{range_check_ptr=range_check_ptr}(
        array_ptr=global_funding_indices.funding_indices,
        elm_size=FundingIndex.SIZE,
        n_elms=global_funding_indices.n_funding_indices,
        key=synthetic_asset_id)
    if success == 0:
        return (
            range_check_ptr=range_check_ptr,
            return_code=PerpetualErrorCode.MISSING_GLOBAL_FUNDING_INDEX)
    end
    return (range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.SUCCESS)
end

# Updates the position with collateral_delta and synthetic_delta and returns the updated position.
# Checks that the transition is valid.
# If the transition is invalid or a failure occured, returns the funded position and a return code
# reporting the problem.
# If the given public key is 0, skip the public key validation and validate instead that the
# position's public key isn't 0. It can be 0 if both synthetic_delta and collateral_delta are 0.
# Returns the initial position, the updated position and the initial position after funding was
# applied.
func update_position(
        range_check_ptr, position : Position*, request_public_key, collateral_delta,
        synthetic_asset_id, synthetic_delta, global_funding_indices : FundingIndicesInfo*,
        oracle_prices : OraclePrices*, general_config : GeneralConfig*) -> (
        range_check_ptr, updated_position : Position*, funded_position : Position*, return_code):
    alloc_locals
    local final_position : Position*
    let (range_check_ptr, local funded_position) = position_apply_funding(
        range_check_ptr=range_check_ptr,
        position=position,
        global_funding_indices=global_funding_indices)

    # We need to explicitly check that the asset has a price and a funding index because otherwise,
    # if the initial and updated position have a balance of 0 for that asset, it won't be caught.
    let (range_check_ptr, return_code) = is_asset_id_tradable(
        range_check_ptr=range_check_ptr,
        synthetic_asset_id=synthetic_asset_id,
        synthetic_delta=synthetic_delta,
        global_funding_indices=global_funding_indices,
        oracle_prices=oracle_prices)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (
            range_check_ptr=range_check_ptr,
            updated_position=funded_position,
            funded_position=funded_position,
            return_code=return_code)
    end

    # Verify public_key.
    local public_key
    local range_check_ptr = range_check_ptr
    if request_public_key == 0:
        # If request_public_key = 0, We'll take the request public key from the current position.
        if position.public_key == 0:
            # The current position is empty and we can't take its public key. We need to assert that
            # the new position is also empty because only in that case we don't need the public key.
            if synthetic_delta != 0:
                return (
                    range_check_ptr=range_check_ptr,
                    updated_position=funded_position,
                    funded_position=funded_position,
                    return_code=PerpetualErrorCode.INVALID_PUBLIC_KEY)
            end
            if collateral_delta != 0:
                return (
                    range_check_ptr=range_check_ptr,
                    updated_position=funded_position,
                    funded_position=funded_position,
                    return_code=PerpetualErrorCode.INVALID_PUBLIC_KEY)
            end
            # There is no change to the position. We can return.
            return (
                range_check_ptr=range_check_ptr,
                updated_position=funded_position,
                funded_position=funded_position,
                return_code=PerpetualErrorCode.SUCCESS)
        end
        public_key = position.public_key
    else:
        let (return_code) = check_request_public_key(
            position_public_key=position.public_key, request_public_key=request_public_key)
        if return_code != PerpetualErrorCode.SUCCESS:
            return (
                range_check_ptr=range_check_ptr,
                updated_position=funded_position,
                funded_position=funded_position,
                return_code=return_code)
        end
        public_key = request_public_key
    end

    let (range_check_ptr, updated_position, return_code) = position_add_collateral(
        range_check_ptr=range_check_ptr,
        position=funded_position,
        delta=collateral_delta,
        public_key=public_key)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (
            range_check_ptr=range_check_ptr,
            updated_position=funded_position,
            funded_position=funded_position,
            return_code=return_code)
    end

    let (range_check_ptr, updated_position : Position*, return_code) = position_add_asset(
        range_check_ptr=range_check_ptr,
        position=updated_position,
        global_funding_indices=global_funding_indices,
        asset_id=synthetic_asset_id,
        delta=synthetic_delta,
        public_key=public_key)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (
            range_check_ptr=range_check_ptr,
            updated_position=funded_position,
            funded_position=funded_position,
            return_code=return_code)
    end
    final_position = updated_position

    let (range_check_ptr, return_code) = check_valid_transition(
        range_check_ptr, final_position, funded_position, oracle_prices, general_config)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (
            range_check_ptr=range_check_ptr,
            updated_position=funded_position,
            funded_position=funded_position,
            return_code=return_code)
    end

    return (
        range_check_ptr=range_check_ptr,
        updated_position=final_position,
        funded_position=funded_position,
        return_code=PerpetualErrorCode.SUCCESS)
end

# Updates the position in 'position_id' in a given dict with collateral_delta and synthetic_delta.
# Checks that initially the position is either empty or belongs to request_public_key.
# Checks that the transition is valid.
# If a failure occured, updates the position in the dict to the funded position without any changes,
# and returns a return code reporting the problem.
# If the given public key is 0, skip the public key validation.
# If synthetic delta is 0, then synthetic_asset_id can be NO_SYNTHETIC_DELTA_ASSET_ID to signal that
# no synthetic asset balance is being changed.
# Returns the updated dict, initial position, the updated position and the initial position after
# funding was applied.
func update_position_in_dict(
        range_check_ptr, positions_dict : DictAccess*, position_id, request_public_key,
        collateral_delta, synthetic_asset_id, synthetic_delta,
        global_funding_indices : FundingIndicesInfo*, oracle_prices : OraclePrices*,
        general_config : GeneralConfig*) -> (
        range_check_ptr, positions_dict : DictAccess*, funded_position : Position*,
        updated_position : Position*, return_code):
    local initial_position : Position*
    alloc_locals

    # You can find the documentation of the class DictManager in the common library.
    %{ ids.initial_position = __dict_manager.get_dict(ids.positions_dict)[ids.position_id] %}

    let (range_check_ptr, updated_position, funded_position, return_code) = update_position(
        range_check_ptr=range_check_ptr,
        position=initial_position,
        request_public_key=request_public_key,
        collateral_delta=collateral_delta,
        synthetic_asset_id=synthetic_asset_id,
        synthetic_delta=synthetic_delta,
        global_funding_indices=global_funding_indices,
        oracle_prices=oracle_prices,
        general_config=general_config)

    # Even if update failed, we need to write the update.
    dict_update{dict_ptr=positions_dict}(
        key=position_id,
        prev_value=cast(initial_position, felt),
        new_value=cast(updated_position, felt))

    return (
        range_check_ptr=range_check_ptr,
        positions_dict=positions_dict,
        funded_position=funded_position,
        updated_position=updated_position,
        return_code=return_code)
end
