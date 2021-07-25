from services.perpetual.cairo.definitions.constants import FXP_32_ONE
from services.perpetual.cairo.definitions.general_config import GeneralConfig, SyntheticAssetInfo
from services.perpetual.cairo.definitions.objects import OraclePrices
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.position.check_smaller_holdings import (
    check_smaller_in_synthetic_holdings)
from services.perpetual.cairo.position.position import Position
from services.perpetual.cairo.position.status import position_get_status
from starkware.cairo.common.math_cmp import is_le, is_le_felt

# Checks if a position update was legal.
# A position update is legal if
#   1. The result position is well leveraged, or
#   2. a. The result position is `smaller` than the original position, and
#      b. The ratio between the total_value and the total_risk in the result position is not
#         smaller than the same ratio in the original position, and
#      c. If the total risk of the original position is 0, the total value of the result
#         position is not smaller than the total value of the original position.
func check_valid_transition(
        range_check_ptr, updated_position : Position*, initial_position : Position*,
        oracle_prices : OraclePrices*, general_config : GeneralConfig*) -> (
        range_check_ptr, return_code):
    alloc_locals
    let (range_check_ptr, local updated_tv, local updated_tr, return_code) = position_get_status(
        range_check_ptr=range_check_ptr,
        position=updated_position,
        oracle_prices=oracle_prices,
        general_config=general_config)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, return_code=return_code)
    end

    let (is_well_leveraged) = is_le{range_check_ptr=range_check_ptr}(
        updated_tr, updated_tv * FXP_32_ONE)
    if is_well_leveraged != 0:
        return (range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.SUCCESS)
    end

    let (range_check_ptr, local initial_tv, local initial_tr, return_code) = position_get_status(
        range_check_ptr=range_check_ptr,
        position=initial_position,
        oracle_prices=oracle_prices,
        general_config=general_config)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, return_code=return_code)
    end

    let (range_check_ptr, return_code) = check_smaller_in_synthetic_holdings(
        range_check_ptr=range_check_ptr,
        updated_position=updated_position,
        initial_position=initial_position)
    if return_code != PerpetualErrorCode.SUCCESS:
        return (range_check_ptr=range_check_ptr, return_code=return_code)
    end

    # total_value / total_risk must not decrease.
    # tv0 / tr0 <= tv1 / tr1 iff tv0 * tr1 <= tv1 * tr0.
    # tv is 96 bit.
    # tr is 128 bit.
    # tv*tr fits in 224 bits.
    # Since tv can be negative, adding 2**224 to each side.
    let (success) = is_le_felt{range_check_ptr=range_check_ptr}(
        %[2**224%] + initial_tv * updated_tr, %[2**224%] + updated_tv * initial_tr)

    if success == 0:
        let return_code = (
            PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_REDUCING_TOTAL_VALUE_RISK_RATIO)
        return (range_check_ptr=range_check_ptr, return_code=return_code)
    end
    if initial_tr == 0:
        # Edge case: When the total risk is 0 the TV/TR ratio is undefined and we need to check that
        # initial_tv <= updated_tv. Note that because we passed
        # 'check_smaller_in_synthetic_holdings' and initial_tr == 0 we must have updated_tr == 0.
        let (success) = is_le{range_check_ptr=range_check_ptr}(initial_tv, updated_tv)
        if success == 0:
            return (
                range_check_ptr=range_check_ptr,
                return_code=PerpetualErrorCode.ILLEGAL_POSITION_TRANSITION_NO_RISK_REDUCED_VALUE)
        end
    end

    return (range_check_ptr=range_check_ptr, return_code=PerpetualErrorCode.SUCCESS)
end
