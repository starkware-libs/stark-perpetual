# Information about the unique collateral asset of the system.
struct CollateralAssetInfo:
    member asset_id : felt
    # Resolution: Each unit of balance in the oracle is worth this much units in our system.
    member resolution : felt
end

# Information about the unique fee position of the system. All fees are paid to it.
struct FeePositionInfo:
    member position_id : felt
    member public_key : felt
end

# Information about a synthetic asset in the system.
struct SyntheticAssetInfo:
    member asset_id : felt  # Asset id.
    # Resolution: Each unit of balance in the oracle is worth this much units in our system.
    member resolution : felt
    # 32.32 fixed point number indicating the risk factor of the asset. This is used in deciding if
    # a position is well leveraged.
    member risk_factor : felt
    # A list of IDs associated with the asset, on which the oracle price providers sign.
    member n_oracle_price_signed_asset_ids : felt
    member oracle_price_signed_asset_ids : felt*
    # The minimum amounts of signatures required to sign on a price.
    member oracle_price_quorum : felt
    # A list of oracle signer public keys.
    member n_oracle_price_signers : felt
    member oracle_price_signers : felt*
end

# Configuration for timestamp validation.
struct TimestampValidationConfig:
    member price_validity_period : felt
    member funding_validity_period : felt
end

struct GeneralConfig:
    # 32.32 fixed point number, indicating the maximum rate of change of a normalized funding index.
    # Units are (1) / (time * price)
    member max_funding_rate : felt
    # See CollateralAssetInfo.
    member collateral_asset_info : CollateralAssetInfo*
    # See FeePositionInfo.
    member fee_position_info : FeePositionInfo*
    # Information about the synthetic assets in the system. See SyntheticAssetInfo.
    member n_synthetic_assets_info : felt
    member synthetic_assets_info : SyntheticAssetInfo*
    # Height of the merkle tree in which positions are kept.
    member positions_tree_height : felt
    # Height of the merkle tree in which orders are kept.
    member orders_tree_height : felt
    # See TimestampValidationConfig.
    member timestamp_validation_config : TimestampValidationConfig*
end
