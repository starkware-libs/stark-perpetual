from services.exchange.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND,
    EXPIRATION_TIMESTAMP_UPPER_BOUND,
    NONCE_UPPER_BOUND,
)

// This is the lower bound for actual synthetic asset and limit order collateral amounts. Those
// amounts can't be 0 to prevent order replay and arbitrary actual fees.
const POSITIVE_AMOUNT_LOWER_BOUND = 1;
// ASSET_ID_UPPER_BOUND is set so that PositionAsset could be packed into a field element.
const ASSET_ID_UPPER_BOUND = 2 ** 120;

// A valid balance satisfies BALANCE_LOWER_BOUND < balance < BALANCE_UPPER_BOUND.
const BALANCE_UPPER_BOUND = 2 ** 63;
const BALANCE_LOWER_BOUND = -BALANCE_UPPER_BOUND;

const TOTAL_VALUE_UPPER_BOUND = 2 ** 63;
const TOTAL_VALUE_LOWER_BOUND = -(2 ** 63);

const TOTAL_RISK_UPPER_BOUND = 2 ** 64;

const N_ASSETS_UPPER_BOUND = 2 ** 16;
const POSITION_MAX_SUPPORTED_N_ASSETS = 2 ** 6;

// Fixed point (.32) representation of the number 1.
const FXP_32_ONE = 2 ** 32;
// Oracle prices are signed by external entities, which use a fixed point representation where
// 10**18 is 1.0 .
const EXTERNAL_PRICE_FIXED_POINT_UNIT = 10 ** 18;

const ORACLE_PRICE_QUORUM_LOWER_BOUND = 1;
const ORACLE_PRICE_QUORUM_UPPER_BOUND = 2 ** 32;

const POSITION_ID_UPPER_BOUND = 2 ** 64;
const ORDER_ID_UPPER_BOUND = 2 ** 64;
// Fixed point (32.32).
const FUNDING_INDEX_UPPER_BOUND = 2 ** 63;
const FUNDING_INDEX_LOWER_BOUND = -(2 ** 63);

// Fixed point (0.32).
const RISK_LOWER_BOUND = 1;
const RISK_UPPER_BOUND = FXP_32_ONE;

const RISK_FACTOR_SEGMENT_UPPER_BOUND = 2 ** 128;

// Fixed point (32.32).
const PRICE_LOWER_BOUND = 1;
const PRICE_UPPER_BOUND = 2 ** 64;

const EXTERNAL_PRICE_UPPER_BOUND = 2 ** 120;

const ASSET_RESOLUTION_LOWER_BOUND = 1;
const ASSET_RESOLUTION_UPPER_BOUND = 2 ** 64;
const COLLATERAL_ASSET_ID_UPPER_BOUND = 2 ** 250;

// General Cairo constants.
const SIGNED_MESSAGE_BOUND = 2 ** 251;
const RANGE_CHECK_BOUND = 2 ** 128;
