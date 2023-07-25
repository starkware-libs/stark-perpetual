from starkware.cairo.common.math import assert_le, assert_lt, assert_nn_le

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

// Represents a segment of the risk factor function. The risk factor function is a
// step function, where each segment has a constant risk.
struct RiskFactorSegment {
    // The end of this segment (inclusive) as a part of the full step function. The start of the
    // segment is the upper bound of the previous segment (the first segment starts in 0).
    upper_bound: felt,
    // 0.32 fixed point number indicating the risk factor of the asset. This is used in deciding if
    // a position is well leveraged.
    risk: felt,
}

// Information about a synthetic asset in the system.
struct SyntheticAssetInfo {
    asset_id: felt,  // Asset id.
    // Resolution: Each unit of balance in the oracle is worth this much units in our system.
    resolution: felt,
    // A list of RiskFactorSegment that determines the risk factor step function.
    n_risk_factor_segments: felt,
    risk_factor_segments: RiskFactorSegment*,
    // A list of IDs associated with the asset, on which the oracle price providers sign.
    n_oracle_price_signed_asset_ids: felt,
    oracle_price_signed_asset_ids: felt*,
    // The minimum amounts of signatures required to sign on a price.
    oracle_price_quorum: felt,
    // A list of oracle signer public keys.
    n_oracle_price_signers: felt,
    oracle_price_signers: felt*,
}

// Returns the risk factor for the given price and balance (in absolute value), according to the
// risk factor function described by risk_factor_segments.
func get_risk_factor{range_check_ptr}(
    risk_factor_segments: RiskFactorSegment*,
    n_risk_factor_segments: felt,
    is_risk_by_balance_only: felt,
    abs_balance: felt,
    price: felt,
) -> felt {
    alloc_locals;
    local segment_idx;
    local amount;
    if (is_risk_by_balance_only != 0) {
        amount = abs_balance;
    } else {
        amount = abs_balance * price;
    }

    %{
        # Finds the right segment for the given amount.
        segments_ptr = ids.risk_factor_segments
        for i in range(ids.n_risk_factor_segments):
            segment = segments_ptr[i]
            if ids.amount <= segment.upper_bound:
                break
        ids.segment_idx = i
    %}
    assert_nn_le(segment_idx, n_risk_factor_segments - 1);
    if (segment_idx != 0) {
        let previous_segment = risk_factor_segments + (segment_idx - 1) * RiskFactorSegment.SIZE;
        assert_lt(previous_segment.upper_bound, amount);
    }
    let segment = risk_factor_segments + segment_idx * RiskFactorSegment.SIZE;
    assert_le(amount, segment.upper_bound);
    return segment.risk;
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
    // If True, the risk calculation is according to the asset balance.
    // If False, the risk calculation is according to the asset value (balance * price).
    is_risk_by_balance_only: felt,
}
