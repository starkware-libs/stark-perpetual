from services.perpetual.cairo.definitions.constants import FUNDING_INDEX_LOWER_BOUND
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.serialize import serialize_array, serialize_word

struct FundingIndex:
    member asset_id : felt
    # funding_index in fxp 32.32 format.
    member funding_index : felt
end

func funding_index_serialize{output_ptr : felt*}(funding_index : FundingIndex*):
    serialize_word(funding_index.asset_id)
    serialize_word(funding_index.funding_index - FUNDING_INDEX_LOWER_BOUND)
    return ()
end

# Funding indices and their timestamp.
struct FundingIndicesInfo:
    member n_funding_indices : felt
    member funding_indices : FundingIndex*
    member funding_timestamp : felt
end

func funding_indices_info_serialize{output_ptr : felt*}(funding_indices : FundingIndicesInfo*):
    let (callback_address) = get_label_location(funding_index_serialize)
    serialize_array(
        array=cast(funding_indices.funding_indices, felt*),
        n_elms=funding_indices.n_funding_indices,
        elm_size=FundingIndex.SIZE,
        callback=callback_address)
    serialize_word(funding_indices.funding_timestamp)
    return ()
end

# Represents a single asset's Oracle Price in internal representation (Refer to the documentation of
# AssetOraclePrice for the definition of internal representation).
struct OraclePrice:
    member asset_id : felt
    # 32.32 fixed point.
    member price : felt
end

# An array of oracle prices.
struct OraclePrices:
    member len : felt
    member data : OraclePrice*
end

func oracle_prices_new(len, data : OraclePrice*) -> (oracle_prices : OraclePrices*):
    let (fp_val, pc_val) = get_fp_and_pc()
    # We refer to the arguments of this function as an OraclePrices object
    # (fp_val - 2 points to the end of the function arguments in the stack).
    return (oracle_prices=cast(fp_val - 2 - OraclePrices.SIZE, OraclePrices*))
end

func oracle_price_serialize{output_ptr : felt*}(oracle_price : OraclePrice*):
    serialize_word(oracle_price.asset_id)
    serialize_word(oracle_price.price)
    return ()
end
