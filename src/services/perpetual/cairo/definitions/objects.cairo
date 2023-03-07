from services.perpetual.cairo.definitions.constants import FUNDING_INDEX_LOWER_BOUND
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.serialize import serialize_array, serialize_word

struct FundingIndex {
    asset_id: felt,
    // funding_index in fxp 32.32 format.
    funding_index: felt,
}

func funding_index_serialize{output_ptr: felt*}(funding_index: FundingIndex*) {
    serialize_word(funding_index.asset_id);
    serialize_word(funding_index.funding_index - FUNDING_INDEX_LOWER_BOUND);
    return ();
}

// Funding indices and their timestamp.
struct FundingIndicesInfo {
    n_funding_indices: felt,
    funding_indices: FundingIndex*,
    funding_timestamp: felt,
}

func funding_indices_info_serialize{output_ptr: felt*}(funding_indices: FundingIndicesInfo*) {
    let (callback_address) = get_label_location(label_value=funding_index_serialize);
    serialize_array(
        array=cast(funding_indices.funding_indices, felt*),
        n_elms=funding_indices.n_funding_indices,
        elm_size=FundingIndex.SIZE,
        callback=callback_address,
    );
    serialize_word(funding_indices.funding_timestamp);
    return ();
}

// Represents a single asset's Oracle Price in internal representation (Refer to the documentation
// of AssetOraclePrice for the definition of internal representation).
struct OraclePrice {
    asset_id: felt,
    // 32.32 fixed point.
    price: felt,
}

// An array of oracle prices.
struct OraclePrices {
    len: felt,
    data: OraclePrice*,
}

func oracle_prices_new(len, data: OraclePrice*) -> (oracle_prices: OraclePrices*) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as an OraclePrices object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (oracle_prices=cast(fp_val - 2 - OraclePrices.SIZE, OraclePrices*));
}

func oracle_price_serialize{output_ptr: felt*}(oracle_price: OraclePrice*) {
    serialize_word(oracle_price.asset_id);
    serialize_word(oracle_price.price);
    return ();
}
