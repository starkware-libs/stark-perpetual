from services.perpetual.cairo.definitions.constants import (
    FXP_32_ONE, TOTAL_RISK_UPPER_BOUND, TOTAL_VALUE_LOWER_BOUND, TOTAL_VALUE_UPPER_BOUND)
from services.perpetual.cairo.definitions.general_config import GeneralConfig, SyntheticAssetInfo
from services.perpetual.cairo.definitions.objects import OraclePrice, OraclePrices
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.position.position import Position, PositionAsset
from starkware.cairo.common.find_element import find_element
from starkware.cairo.common.math import abs_value
from starkware.cairo.common.math_cmp import is_in_range, is_le

# Inner tail recursive function for position_get_status.
# Computes the risk and value of the synthetic assets.
# total_value_rep is signed (.32) fixed point = sum(price * balance) for asset in assets.
# total_risk_rep is unsigned (.64) fixed point = sum(risk_factor * abs(price * balance))
# for asset in assets.
func position_get_status_inner(
        range_check_ptr, assets : PositionAsset*, n_assets, oracle_prices : OraclePrices*,
        general_config : GeneralConfig*, total_value_rep, total_risk_rep) -> (
        range_check_ptr, total_value_rep, total_risk_rep):
    jmp body if n_assets != 0
    return (
        range_check_ptr=range_check_ptr,
        total_value_rep=total_value_rep,
        total_risk_rep=total_risk_rep)

    body:
    alloc_locals
    let current_asset : PositionAsset* = assets
    local asset_id = current_asset.asset_id

    # Compute value.

    # The key for `find_element` must be at offset 0.
    static_assert OraclePrice.asset_id == 0
    let (oracle_price_elm : OraclePrice*) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=oracle_prices.data,
        elm_size=OraclePrice.SIZE,
        n_elms=oracle_prices.len,
        key=asset_id)
    # Signed (96.32) fixed point.
    local value_rep = oracle_price_elm.price * current_asset.balance

    # The key must be at offset 0.
    static_assert SyntheticAssetInfo.asset_id == 0
    let (synthetic_info : SyntheticAssetInfo*) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=general_config.synthetic_assets_info,
        elm_size=SyntheticAssetInfo.SIZE,
        n_elms=general_config.n_synthetic_assets_info,
        key=asset_id)
    local risk_factor = synthetic_info.risk_factor

    let (abs_value_rep) = abs_value{range_check_ptr=range_check_ptr}(value=value_rep)

    # value_rep is a (96.32) fixed point so risk_rep is a (128.64) fixed point.
    tempvar risk_rep = abs_value_rep * risk_factor

    return position_get_status_inner(
        range_check_ptr=range_check_ptr,
        assets=assets + PositionAsset.SIZE,
        n_assets=n_assets - 1,
        oracle_prices=oracle_prices,
        general_config=general_config,
        total_value_rep=total_value_rep + value_rep,
        total_risk_rep=total_risk_rep + risk_rep)
end

# Computes the risk and value of a position. Returns an error code if the computed values are out of
# range.
#
# Arguments:
# range_check_ptr - range check builtin pointer.
# position - a pointer to Position.
# oracle_prices - an array of oracle prices.
# general_config - The general config of the program.
#
# Returns:
# range_check_ptr - new range check builtin pointer.
# total_value_rep is signed (.32) fixed point.
# total_risk_rep is unsigned (.64) fixed point.
func position_get_status(
        range_check_ptr, position : Position*, oracle_prices : OraclePrices*,
        general_config : GeneralConfig*) -> (
        range_check_ptr, total_value_rep, total_risk_rep, return_code):
    alloc_locals
    let (range_check_ptr, local total_value_rep, local total_risk_rep) = position_get_status_inner(
        range_check_ptr=range_check_ptr,
        assets=position.assets_ptr,
        n_assets=position.n_assets,
        oracle_prices=oracle_prices,
        general_config=general_config,
        total_value_rep=position.collateral_balance * FXP_32_ONE,
        total_risk_rep=0)

    const TOTAL_VALUE_LOWER_BOUND_REP = TOTAL_VALUE_LOWER_BOUND * FXP_32_ONE
    const TOTAL_VALUE_UPPER_BOUND_REP = TOTAL_VALUE_UPPER_BOUND * FXP_32_ONE
    let (res) = is_in_range{range_check_ptr=range_check_ptr}(
        total_value_rep, TOTAL_VALUE_LOWER_BOUND_REP, TOTAL_VALUE_UPPER_BOUND_REP)
    if res == 0:
        return (
            range_check_ptr=range_check_ptr,
            total_value_rep=0,
            total_risk_rep=0,
            return_code=PerpetualErrorCode.OUT_OF_RANGE_TOTAL_VALUE)
    end

    const TR_UPPER_BOUND_REP = TOTAL_RISK_UPPER_BOUND * FXP_32_ONE * FXP_32_ONE
    let (res) = is_le{range_check_ptr=range_check_ptr}(total_risk_rep, TR_UPPER_BOUND_REP - 1)
    if res == 0:
        return (
            range_check_ptr=range_check_ptr,
            total_value_rep=0,
            total_risk_rep=0,
            return_code=PerpetualErrorCode.OUT_OF_RANGE_TOTAL_RISK)
    end

    return (
        range_check_ptr=range_check_ptr,
        total_value_rep=total_value_rep,
        total_risk_rep=total_risk_rep,
        return_code=PerpetualErrorCode.SUCCESS)
end
