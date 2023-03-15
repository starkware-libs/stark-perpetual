// Information about the unique collateral asset of the system.
struct CollateralAssetInfo {
    asset_id: felt,
    // Resolution: Each unit of balance in the oracle is worth this much units in our system.
    resolution: felt,
}

// Information about the unique fee position of the system. All fees are paid to it.
struct FeePositionInfo {
    position_id: felt,
    public_key: felt,
}

// Information about a synthetic asset in the system.
struct SyntheticAssetInfo {
    asset_id: felt,  // Asset id.
    // Resolution: Each unit of balance in the oracle is worth this much units in our system.
    resolution: felt,
    // 32.32 fixed point number indicating the risk factor of the asset. This is used in deciding if
    // a position is well leveraged.
    risk_factor: felt,
    // A list of IDs associated with the asset, on which the oracle price providers sign.
    n_oracle_price_signed_asset_ids: felt,
    oracle_price_signed_asset_ids: felt*,
    // The minimum amounts of signatures required to sign on a price.
    oracle_price_quorum: felt,
    // A list of oracle signer public keys.
    n_oracle_price_signers: felt,
    oracle_price_signers: felt*,
}

// Configuration for timestamp validation.
struct TimestampValidationConfig {
    price_validity_period: felt,
    funding_validity_period: felt,
}

struct GeneralConfig {
    // 32.32 fixed point number, indicating the maximum rate of change of a normalized funding
    // index. Units are (1) / (time * price).
    max_funding_rate: felt,
    // See CollateralAssetInfo.
    collateral_asset_info: CollateralAssetInfo*,
    // See FeePositionInfo.
    fee_position_info: FeePositionInfo*,
    // Information about the synthetic assets in the system. See SyntheticAssetInfo.
    n_synthetic_assets_info: felt,
    synthetic_assets_info: SyntheticAssetInfo*,
    // Height of the merkle tree in which positions are kept.
    positions_tree_height: felt,
    // Height of the merkle tree in which orders are kept.
    orders_tree_height: felt,
    // See TimestampValidationConfig.
    timestamp_validation_config: TimestampValidationConfig*,
    // Identifier of data availability mode, validium or rollup.
    data_availability_mode: felt,
}
