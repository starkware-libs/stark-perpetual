from services.perpetual.cairo.definitions.constants import (
    EXTERNAL_PRICE_FIXED_POINT_UNIT, EXTERNAL_PRICE_UPPER_BOUND, FXP_32_ONE, PRICE_LOWER_BOUND,
    PRICE_UPPER_BOUND)
from services.perpetual.cairo.definitions.general_config import (
    CollateralAssetInfo, GeneralConfig, SyntheticAssetInfo)
from services.perpetual.cairo.definitions.objects import OraclePrice
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.find_element import find_element
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math import (
    assert_in_range, assert_le, assert_lt_felt, assert_nn_le, assert_not_zero, sign,
    unsigned_div_rem)
from starkware.cairo.common.signature import verify_ecdsa_signature

# Price definitions:
# An external price is a unit of the collateral asset divided by a unit of synthetic asset.
# An internal price is computed as the ratio between a unit of collateral asset and its resolution,
# divided by the ratio between a unit of synthetic asset and its resolution:
#   (collateral_asset_unit / collateral_resolution) / (synthetic_asset_unit / synthetic_resolution).

# Represents a single signature on an external price with a timestamp.
struct SignedOraclePrice:
    member signer_key : felt
    member external_price : felt
    member timestamp : felt
    member signed_asset_id : felt
    member signature_r : felt
    member signature_s : felt
end

# Represents a single Oracle Price of an asset in internal representation and
# signatures on that price. The price is a median of all prices in the signatures.
struct AssetOraclePrice:
    member asset_id : felt
    member price : felt
    member n_signed_prices : felt
    # Oracle signatures, sorted by signer_key.
    member signed_prices : SignedOraclePrice*
end

struct TimeBounds:
    member min_time : felt
    member max_time : felt
end

const TIMESTAMP_BOUND = %[2**32%]

# Checks a single price signature.
# * Signature is valid.
# * Signer public key is present in the SyntheticAssetInfo.
# * Signer asset id is present in the SyntheticAssetInfo.
# * Valid timestamp.
# * Signer key is greater than the last signer key (for uniqueness).
# Returns (is_le, is_ge) with respect to the median price. This is needed to verify the median.
func check_price_signature(
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*,
        time_bounds : TimeBounds*, asset_info : SyntheticAssetInfo*, median_price,
        collateral_resolution, sig : SignedOraclePrice*) -> (
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*, is_le, is_ge):
    alloc_locals

    # Check ranges.
    assert_nn_le{range_check_ptr=range_check_ptr}(sig.external_price, EXTERNAL_PRICE_UPPER_BOUND)
    assert_nn_le{range_check_ptr=range_check_ptr}(sig.timestamp, TIMESTAMP_BOUND)

    # Compute message.
    with hash_ptr:
        let (message) = hash2(
            x=sig.signed_asset_id, y=sig.external_price * TIMESTAMP_BOUND + sig.timestamp)
    end
    local hash_ptr : HashBuiltin* = hash_ptr

    # Check signature.
    with ecdsa_ptr:
        verify_ecdsa_signature(
            message=message,
            public_key=sig.signer_key,
            signature_r=sig.signature_r,
            signature_s=sig.signature_s)
    end
    local ecdsa_ptr : SignatureBuiltin* = ecdsa_ptr

    # Check that signer is in the config.
    %{ error_code = ids.PerpetualErrorCode.INVALID_ASSET_ORACLE_PRICE %}
    find_element{range_check_ptr=range_check_ptr}(
        array_ptr=asset_info.oracle_price_signers,
        elm_size=1,
        n_elms=asset_info.n_oracle_price_signers,
        key=sig.signer_key)

    %{ del error_code %}
    # Check that signed_asset_id is in the config.
    find_element{range_check_ptr=range_check_ptr}(
        array_ptr=asset_info.oracle_price_signed_asset_ids,
        elm_size=1,
        n_elms=asset_info.n_oracle_price_signed_asset_ids,
        key=sig.signed_asset_id)

    # Check timestamp.
    assert_in_range{range_check_ptr=range_check_ptr}(
        sig.timestamp, time_bounds.min_time, time_bounds.max_time + 1)

    # Transform to internal price.
    # price is a 32.32 bit fixed point number in internal asset units.
    # signed prices are fixed point in external asset units.
    # external_price_repr = external_coll / external_synth * EXTERNAL_PRICE_FIXED_POINT_UNIT
    # internal_price_repr = internal_coll / internal_synth * FXP_32_ONE
    # = (external_coll * res_coll) / (external_synth * res_synth) * FXP_32_ONE
    # = external_price_repr * res_coll * FXP_32_ONE /
    #   (res_synth * EXTERNAL_PRICE_FIXED_POINT_UNIT).
    # Assuming resolutions are 64bit.
    # numerator is 192 bit.
    let numerator = sig.external_price * collateral_resolution * FXP_32_ONE
    # denominator is 96 bit.
    tempvar denominator = asset_info.resolution * EXTERNAL_PRICE_FIXED_POINT_UNIT
    # Add denominator/2 to round.
    let (internal_price, _) = unsigned_div_rem{range_check_ptr=range_check_ptr}(
        numerator + denominator / 2, denominator)

    # Check above or below median.
    let (median_comparison) = sign{range_check_ptr=range_check_ptr}(
        value=median_price - internal_price)

    if median_comparison == 0:
        return (
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            hash_ptr=hash_ptr,
            is_le=1,
            is_ge=1)
    end
    # If median_comparison is 1, is_ge will be 1. If median_comparison is -1, is_ge will be 0.
    tempvar is_ge = (median_comparison + 1) / 2
    return (
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        is_le=1 - is_ge,
        is_ge=is_ge)
end

func check_oracle_price_inner(
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*,
        time_bounds : TimeBounds*, asset_info : SyntheticAssetInfo*, median_price,
        collateral_resolution, sig : SignedOraclePrice*, n_sigs, last_signer, n_le, n_ge) -> (
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*, n_le, n_ge):
    if n_sigs == 0:
        # All signatures are checked.
        return (
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            hash_ptr=hash_ptr,
            n_le=n_le,
            n_ge=n_ge)
    end

    # Check that signer_key is greater than the last signer key. This assures uniqueness of signers.
    assert_lt_felt{range_check_ptr=range_check_ptr}(last_signer, sig.signer_key)

    # Check the signature.
    let (range_check_ptr, ecdsa_ptr, hash_ptr, is_le, is_ge) = check_price_signature(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        time_bounds=time_bounds,
        asset_info=asset_info,
        median_price=median_price,
        collateral_resolution=collateral_resolution,
        sig=sig)

    # Recursive call.
    return check_oracle_price_inner(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        time_bounds=time_bounds,
        asset_info=asset_info,
        median_price=median_price,
        collateral_resolution=collateral_resolution,
        sig=sig + SignedOraclePrice.SIZE,
        n_sigs=n_sigs - 1,
        last_signer=sig.signer_key,
        n_le=n_le + is_le,
        n_ge=n_ge + is_ge)
end

# Checks the validity of a single oracle price given as AssetOraclePrice.
# Checks there are at least quorum valid signatures from distinct signer keys, and that the price
# used is a median price of these signed prices.
func check_oracle_price(
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*,
        time_bounds : TimeBounds*, asset_oracle_price : AssetOraclePrice*,
        asset_info : SyntheticAssetInfo*, collateral_info : CollateralAssetInfo*) -> (
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*):
    alloc_locals
    local n_sigs = asset_oracle_price.n_signed_prices

    # Check that we have enough signatures (>= quorum).
    assert_le{range_check_ptr=range_check_ptr}(asset_info.oracle_price_quorum, n_sigs)

    # Check that price is in range.
    assert_in_range{range_check_ptr=range_check_ptr}(
        asset_oracle_price.price, PRICE_LOWER_BOUND, PRICE_UPPER_BOUND)

    # Check all signatures.
    let (range_check_ptr, ecdsa_ptr, hash_ptr, n_le, n_ge) = check_oracle_price_inner(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        time_bounds=time_bounds,
        asset_info=asset_info,
        median_price=asset_oracle_price.price,
        collateral_resolution=collateral_info.resolution,
        sig=asset_oracle_price.signed_prices,
        n_sigs=n_sigs,
        last_signer=0,
        n_le=0,
        n_ge=0)

    # Check that the median price is indeed a median:
    # At least half the oracle prices are greater or equal to the median price and
    # at least half the oracle prices are smaller or equal to the median price.
    assert_le{range_check_ptr=range_check_ptr}(n_sigs, n_le * 2)
    assert_le{range_check_ptr=range_check_ptr}(n_sigs, n_ge * 2)

    return (range_check_ptr=range_check_ptr, ecdsa_ptr=ecdsa_ptr, hash_ptr=hash_ptr)
end

func check_oracle_prices_inner(
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*, n_oracle_prices,
        asset_oracle_prices : AssetOraclePrice*, n_synthetic_assets_info,
        synthetic_assets_info : SyntheticAssetInfo*, time_bounds : TimeBounds*,
        general_config : GeneralConfig*) -> (
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*):
    if n_oracle_prices == 0:
        # All prices are validated.
        return (range_check_ptr=range_check_ptr, ecdsa_ptr=ecdsa_ptr, hash_ptr=hash_ptr)
    end

    # n_synthetic_assets_info = 0 means that the current asset was not found in the general config.
    %{ error_code = ids.PerpetualErrorCode.MISSING_SYNTHETIC_ASSET_ID %}
    assert_not_zero(n_synthetic_assets_info)
    %{ del error_code %}

    if asset_oracle_prices.asset_id != synthetic_assets_info.asset_id:
        # Advance synthetic_assets_info until we get to our asset.
        return check_oracle_prices_inner(
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            hash_ptr=hash_ptr,
            n_oracle_prices=n_oracle_prices,
            asset_oracle_prices=asset_oracle_prices,
            n_synthetic_assets_info=n_synthetic_assets_info - 1,
            synthetic_assets_info=synthetic_assets_info + SyntheticAssetInfo.SIZE,
            time_bounds=time_bounds,
            general_config=general_config)
    end

    # Check this oracle price.
    let (range_check_ptr, ecdsa_ptr, hash_ptr) = check_oracle_price(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        time_bounds=time_bounds,
        asset_oracle_price=asset_oracle_prices,
        asset_info=synthetic_assets_info,
        collateral_info=general_config.collateral_asset_info)

    # Recursive call.
    return check_oracle_prices_inner(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        n_oracle_prices=n_oracle_prices - 1,
        asset_oracle_prices=asset_oracle_prices + AssetOraclePrice.SIZE,
        n_synthetic_assets_info=n_synthetic_assets_info - 1,
        synthetic_assets_info=synthetic_assets_info + SyntheticAssetInfo.SIZE,
        time_bounds=time_bounds,
        general_config=general_config)
end

# Checks that a list of AssetOraclePrice instances are valid with respect to a GeneralConfig and a
# time frame.
func check_oracle_prices(
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*, n_oracle_prices,
        asset_oracle_prices : AssetOraclePrice*, time_bounds : TimeBounds*,
        general_config : GeneralConfig*) -> (
        range_check_ptr, ecdsa_ptr : SignatureBuiltin*, hash_ptr : HashBuiltin*):
    return check_oracle_prices_inner(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        hash_ptr=hash_ptr,
        n_oracle_prices=n_oracle_prices,
        asset_oracle_prices=asset_oracle_prices,
        n_synthetic_assets_info=general_config.n_synthetic_assets_info,
        synthetic_assets_info=general_config.synthetic_assets_info,
        time_bounds=time_bounds,
        general_config=general_config)
end

func signed_prices_to_price_inner(
        n_oracle_prices, asset_oracle_prices : AssetOraclePrice*, oracle_prices : OraclePrice*):
    if n_oracle_prices == 0:
        return ()
    end

    assert oracle_prices.asset_id = asset_oracle_prices.asset_id
    assert oracle_prices.price = asset_oracle_prices.price

    signed_prices_to_price_inner(
        n_oracle_prices=n_oracle_prices - 1,
        asset_oracle_prices=asset_oracle_prices + AssetOraclePrice.SIZE,
        oracle_prices=oracle_prices + OraclePrice.SIZE)
    return ()
end

# Converts signed oracle prices (AssetOraclePrice*) to oracle prices (OraclePrice*).
func signed_prices_to_prices(n_oracle_prices, asset_oracle_prices : AssetOraclePrice*) -> (
        oracle_prices : OraclePrice*):
    alloc_locals
    let (local oracle_prices : OraclePrice*) = alloc()
    signed_prices_to_price_inner(
        n_oracle_prices=n_oracle_prices,
        asset_oracle_prices=asset_oracle_prices,
        oracle_prices=oracle_prices)
    return (oracle_prices)
end
