from services.perpetual.cairo.definitions.general_config import (
    CollateralAssetInfo, FeePositionInfo, GeneralConfig, SyntheticAssetInfo,
    TimestampValidationConfig)
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash_state import (
    HashState, hash_finalize, hash_init, hash_update, hash_update_single)

# A synthetic asset entry contaning tis asset id and its config's hash.
struct AssetConfigHashEntry:
    member asset_id : felt
    member config_hash : felt
end

# Calculate the hash of a SyntheticAssetInfo.
func synthetic_asset_info_hash{pedersen_ptr : HashBuiltin*}(
        synthetic_asset_info_ptr : SyntheticAssetInfo*) -> (hash):
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(hash_state_ptr, synthetic_asset_info_ptr.asset_id)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, synthetic_asset_info_ptr.resolution)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, synthetic_asset_info_ptr.risk_factor)
        let (hash_state_ptr) = hash_update(
            hash_state_ptr,
            synthetic_asset_info_ptr.oracle_price_signed_asset_ids,
            synthetic_asset_info_ptr.n_oracle_price_signed_asset_ids)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, synthetic_asset_info_ptr.oracle_price_quorum)
        let (hash_state_ptr) = hash_update(
            hash_state_ptr,
            synthetic_asset_info_ptr.oracle_price_signers,
            synthetic_asset_info_ptr.n_oracle_price_signers)

        static_assert SyntheticAssetInfo.SIZE == 8
        let (hash) = hash_finalize(hash_state_ptr)
    end
    let pedersen_ptr = hash_ptr
    return (hash=hash)
end

# Calculates the hash of a GeneralConfig. The returned value is the hash of all fields except the
# synthetic assets info. To get the hashes of the synthetic assets, use
# general_config_hash_synthetic_assets.
func general_config_hash{pedersen_ptr : HashBuiltin*}(general_config_ptr : GeneralConfig*) -> (
        hash):
    let hash_ptr = pedersen_ptr
    with hash_ptr:
        let (hash_state_ptr) = hash_init()
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.max_funding_rate)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.collateral_asset_info.asset_id)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.collateral_asset_info.resolution)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.fee_position_info.position_id)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.fee_position_info.public_key)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.positions_tree_height)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.orders_tree_height)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.timestamp_validation_config.price_validity_period)
        let (hash_state_ptr) = hash_update_single(
            hash_state_ptr, general_config_ptr.timestamp_validation_config.funding_validity_period)

        static_assert GeneralConfig.SIZE == 8
        let (hash) = hash_finalize(hash_state_ptr)
    end
    let pedersen_ptr = hash_ptr
    return (hash=hash)
end

func synthetic_assets_info_to_asset_configs{pedersen_ptr : HashBuiltin*}(
        output_ptr : AssetConfigHashEntry*, n_synthetic_assets_info,
        synthetic_assets_info : SyntheticAssetInfo*) -> ():
    if n_synthetic_assets_info == 0:
        return ()
    end

    let (hash) = synthetic_asset_info_hash(synthetic_assets_info)
    assert output_ptr.asset_id = synthetic_assets_info.asset_id
    assert output_ptr.config_hash = hash
    return synthetic_assets_info_to_asset_configs(
        output_ptr=output_ptr + AssetConfigHashEntry.SIZE,
        n_synthetic_assets_info=n_synthetic_assets_info - 1,
        synthetic_assets_info=synthetic_assets_info + SyntheticAssetInfo.SIZE)
end

# Calculates the hash of the synthetic assets of a GeneralConfig. Returns a list of each synthetic
# asset info's hash.
func general_config_hash_synthetic_assets{pedersen_ptr : HashBuiltin*}(
        general_config_ptr : GeneralConfig*) -> (
        n_asset_configs, asset_configs : AssetConfigHashEntry*):
    local asset_configs : AssetConfigHashEntry*
    alloc_locals

    %{
        ids.asset_configs = asset_configs = segments.add()
        segments.finalize(
            asset_configs.segment_index,
            ids.general_config_ptr.n_synthetic_assets_info * ids.AssetConfigHashEntry.SIZE
        )
    %}

    synthetic_assets_info_to_asset_configs(
        output_ptr=asset_configs,
        n_synthetic_assets_info=general_config_ptr.n_synthetic_assets_info,
        synthetic_assets_info=general_config_ptr.synthetic_assets_info)
    return (n_asset_configs=general_config_ptr.n_synthetic_assets_info, asset_configs=asset_configs)
end
