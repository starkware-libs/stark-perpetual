# An enum that lists all possible errors that could happen during the run. Useful for giving context
# upon error via hints.
# The error code for success is zero and all other error codes are positive.
namespace PerpetualErrorCode:
    const SUCCESS = 0
    # An error code for unspecified errors.
    const ERROR = 1
    const ILLEGAL_POSITION_TRANSITION_ENLARGING_SYNTHETIC_HOLDINGS = 2
    const ILLEGAL_POSITION_TRANSITION_NO_RISK_REDUCED_VALUE = 3
    const ILLEGAL_POSITION_TRANSITION_REDUCING_TOTAL_VALUE_RISK_RATIO = 4
    const INVALID_ASSET_ORACLE_PRICE = 5
    const INVALID_COLLATERAL_ASSET_ID = 6
    const INVALID_FULFILLMENT_ASSETS_RATIO = 7
    const INVALID_FULFILLMENT_FEE_RATIO = 8
    const INVALID_FULFILLMENT_INFO = 9
    const INVALID_FUNDING_TICK_TIMESTAMP = 10
    const INVALID_PUBLIC_KEY = 11
    const INVALID_SIGNATURE = 12
    const MISSING_GLOBAL_FUNDING_INDEX = 13
    const MISSING_ORACLE_PRICE = 14
    const MISSING_SYNTHETIC_ASSET_ID = 15
    const OUT_OF_RANGE_AMOUNT = 16
    const OUT_OF_RANGE_BALANCE = 17
    const OUT_OF_RANGE_FUNDING_INDEX = 18
    const OUT_OF_RANGE_POSITIVE_AMOUNT = 19
    const OUT_OF_RANGE_TOTAL_RISK = 20
    const OUT_OF_RANGE_TOTAL_VALUE = 21
    const SAME_POSITION_ID = 22
    const TOO_MANY_SYNTHETIC_ASSETS_IN_POSITION = 23
    const TOO_MANY_SYNTHETIC_ASSETS_IN_SYSTEM = 24
    const UNDELEVERAGABLE_POSITION = 25
    const UNFAIR_DELEVERAGE = 26
    const UNLIQUIDATABLE_POSITION = 27
    const UNSORTED_ORACLE_PRICES = 28
end

# Receives an error code and verifies it is equal to SUCCESS.
# If not, the function will put the error code in a hint variable before exiting.
func assert_success(error_code):
    %{ error_code = ids.error_code %}
    assert error_code = PerpetualErrorCode.SUCCESS
    %{ del error_code %}
    return ()
end
