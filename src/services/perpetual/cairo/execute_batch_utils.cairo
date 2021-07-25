from services.perpetual.cairo.definitions.constants import (
    ASSET_ID_UPPER_BOUND, ASSET_RESOLUTION_LOWER_BOUND, ASSET_RESOLUTION_UPPER_BOUND,
    COLLATERAL_ASSET_ID_UPPER_BOUND, N_ASSETS_UPPER_BOUND, ORACLE_PRICE_QUORUM_LOWER_BOUND,
    ORACLE_PRICE_QUORUM_UPPER_BOUND, RISK_FACTOR_LOWER_BOUND, RISK_FACTOR_UPPER_BOUND)
from services.perpetual.cairo.definitions.general_config import (
    CollateralAssetInfo, GeneralConfig, SyntheticAssetInfo)
from services.perpetual.cairo.definitions.objects import FundingIndicesInfo
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.position.funding import FundingIndex
from starkware.cairo.common.math import (
    assert_in_range, assert_le, assert_le_felt, assert_lt, assert_not_zero)

func validate_funding_indices_in_general_config_inner(
        funding_index : FundingIndex*, n_funding_indices,
        synthetic_asset_info : SyntheticAssetInfo*, n_synthetic_assets_info):
    if n_funding_indices == 0:
        return ()
    end
    assert_not_zero(n_synthetic_assets_info)
    if funding_index.asset_id == synthetic_asset_info.asset_id:
        # Found synthetic asset info.
        validate_funding_indices_in_general_config_inner(
            funding_index=funding_index + FundingIndex.SIZE,
            n_funding_indices=n_funding_indices - 1,
            synthetic_asset_info=synthetic_asset_info + SyntheticAssetInfo.SIZE,
            n_synthetic_assets_info=n_synthetic_assets_info - 1)
        return ()
    else:
        # Skip synthetic asset info.
        validate_funding_indices_in_general_config_inner(
            funding_index=funding_index,
            n_funding_indices=n_funding_indices,
            synthetic_asset_info=synthetic_asset_info + SyntheticAssetInfo.SIZE,
            n_synthetic_assets_info=n_synthetic_assets_info - 1)
        return ()
    end
end

# Validates that everey asset id in global_funding_indices is in general_config's
# synthetic asset info.
func validate_funding_indices_in_general_config(
        global_funding_indices : FundingIndicesInfo*, general_config : GeneralConfig*):
    validate_funding_indices_in_general_config_inner(
        funding_index=global_funding_indices.funding_indices,
        n_funding_indices=global_funding_indices.n_funding_indices,
        synthetic_asset_info=general_config.synthetic_assets_info,
        n_synthetic_assets_info=general_config.n_synthetic_assets_info)
    return ()
end

func validate_assets_config_inner(
        range_check_ptr, synthetic_assets_info_ptr : SyntheticAssetInfo*, n_synthetic_assets_info,
        prev_asset_id) -> (range_check_ptr):
    if n_synthetic_assets_info == 0:
        assert_lt{range_check_ptr=range_check_ptr}(prev_asset_id, ASSET_ID_UPPER_BOUND)
        return (range_check_ptr=range_check_ptr)
    end
    assert_lt{range_check_ptr=range_check_ptr}(prev_asset_id, synthetic_assets_info_ptr.asset_id)

    assert_in_range{range_check_ptr=range_check_ptr}(
        synthetic_assets_info_ptr.risk_factor, RISK_FACTOR_LOWER_BOUND, RISK_FACTOR_UPPER_BOUND)

    assert_in_range{range_check_ptr=range_check_ptr}(
        synthetic_assets_info_ptr.oracle_price_quorum,
        ORACLE_PRICE_QUORUM_LOWER_BOUND,
        ORACLE_PRICE_QUORUM_UPPER_BOUND)

    assert_in_range{range_check_ptr=range_check_ptr}(
        synthetic_assets_info_ptr.resolution,
        ASSET_RESOLUTION_LOWER_BOUND,
        ASSET_RESOLUTION_UPPER_BOUND)

    return validate_assets_config_inner(
        range_check_ptr=range_check_ptr,
        synthetic_assets_info_ptr=synthetic_assets_info_ptr + SyntheticAssetInfo.SIZE,
        n_synthetic_assets_info=n_synthetic_assets_info - 1,
        prev_asset_id=synthetic_assets_info_ptr.asset_id)
end

# Validates that the synthetic assets info in general_config is sorted according to asset_id and
# that their risk factor is in range.
func validate_assets_config(range_check_ptr, general_config : GeneralConfig*) -> (range_check_ptr):
    return validate_assets_config_inner(
        range_check_ptr=range_check_ptr,
        synthetic_assets_info_ptr=general_config.synthetic_assets_info,
        n_synthetic_assets_info=general_config.n_synthetic_assets_info,
        prev_asset_id=-1)
end

# Validates that all the fields in general config are in range and that the synthetic assets info is
# sorted according to asset_id.
func validate_general_config(range_check_ptr, general_config : GeneralConfig*) -> (range_check_ptr):
    let (range_check_ptr) = validate_assets_config(
        range_check_ptr=range_check_ptr, general_config=general_config)

    tempvar collateral_asset_info : CollateralAssetInfo* = general_config.collateral_asset_info

    assert_le_felt{range_check_ptr=range_check_ptr}(
        collateral_asset_info.asset_id, COLLATERAL_ASSET_ID_UPPER_BOUND - 1)

    assert_in_range{range_check_ptr=range_check_ptr}(
        collateral_asset_info.resolution,
        ASSET_RESOLUTION_LOWER_BOUND,
        ASSET_RESOLUTION_UPPER_BOUND)

    %{ error_code = ids.PerpetualErrorCode.TOO_MANY_SYNTHETIC_ASSETS_IN_SYSTEM %}
    assert_le{range_check_ptr=range_check_ptr}(
        general_config.n_synthetic_assets_info, N_ASSETS_UPPER_BOUND)
    %{ del error_code %}
    return (range_check_ptr=range_check_ptr)
end
