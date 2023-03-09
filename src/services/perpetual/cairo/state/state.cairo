from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.objects import (
    FundingIndicesInfo,
    OraclePrice,
    OraclePrices,
    funding_indices_info_serialize,
    oracle_price_serialize,
)
from services.perpetual.cairo.position.hash import hash_position_updates
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.dict import dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.serialize import serialize_array, serialize_word
from starkware.cairo.common.squash_dict import squash_dict

// State carried through batch execution. Keeps the current pointer of all dicts.
struct CarriedState {
    positions_dict: DictAccess*,
    orders_dict: DictAccess*,
    global_funding_indices: FundingIndicesInfo*,
    oracle_prices: OraclePrices*,
    system_time: felt,
}

func carried_state_new(
    positions_dict: DictAccess*,
    orders_dict: DictAccess*,
    global_funding_indices: FundingIndicesInfo*,
    oracle_prices: OraclePrices*,
    system_time,
) -> (carried_state: CarriedState*) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as a CarriedState object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (carried_state=cast(fp_val - 2 - CarriedState.SIZE, CarriedState*));
}

// Carried state that keeps the squashed dicts.
struct SquashedCarriedState {
    positions_dict: DictAccess*,
    positions_dict_end: DictAccess*,
    orders_dict: DictAccess*,
    orders_dict_end: DictAccess*,
    global_funding_indices: FundingIndicesInfo*,
    oracle_prices: OraclePrices*,
    system_time: felt,
}

func squashed_carried_state_new(
    positions_dict: DictAccess*,
    positions_dict_end: DictAccess*,
    orders_dict: DictAccess*,
    orders_dict_end: DictAccess*,
    global_funding_indices: FundingIndicesInfo*,
    oracle_prices: OraclePrices*,
    system_time,
) -> (carried_state: SquashedCarriedState*) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as a SquashedCarriedState object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (carried_state=cast(fp_val - 2 - SquashedCarriedState.SIZE, SquashedCarriedState*));
}

func carried_state_squash{range_check_ptr}(
    initial_carried_state: CarriedState*, carried_state: CarriedState*
) -> (squashed_carried_state: SquashedCarriedState*) {
    alloc_locals;
    // Squash positions dict.
    let (local squashed_positions_dict: DictAccess*) = alloc();
    let (local squashed_positions_dict_end: DictAccess*) = squash_dict(
        dict_accesses=initial_carried_state.positions_dict,
        dict_accesses_end=carried_state.positions_dict,
        squashed_dict=squashed_positions_dict,
    );
    // Squash orders dict.
    let (local squashed_orders_dict: DictAccess*) = alloc();
    let (local squashed_orders_dict_end: DictAccess*) = squash_dict(
        dict_accesses=initial_carried_state.orders_dict,
        dict_accesses_end=carried_state.orders_dict,
        squashed_dict=squashed_orders_dict,
    );
    // Return SquashedCarriedState.
    let (squashed_carried_state) = squashed_carried_state_new(
        positions_dict=squashed_positions_dict,
        positions_dict_end=squashed_positions_dict_end,
        orders_dict=squashed_orders_dict,
        orders_dict_end=squashed_orders_dict_end,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time,
    );
    return (squashed_carried_state=squashed_carried_state);
}

// State stored on the blockchain.
struct SharedState {
    positions_root: felt,
    positions_tree_height: felt,
    orders_root: felt,
    orders_tree_height: felt,
    global_funding_indices: FundingIndicesInfo*,
    oracle_prices: OraclePrices*,
    system_time: felt,
}

func shared_state_new(
    positions_root,
    positions_tree_height,
    orders_root,
    orders_tree_height,
    global_funding_indices: FundingIndicesInfo*,
    oracle_prices: OraclePrices*,
    system_time,
) -> (carried_state: SharedState*) {
    let (fp_val, pc_val) = get_fp_and_pc();
    // We refer to the arguments of this function as a SharedState object
    // (fp_val - 2 points to the end of the function arguments in the stack).
    return (carried_state=cast(fp_val - 2 - SharedState.SIZE, SharedState*));
}

// Applies the updates from the squashed carried state on the initial shared state.
// Arguments:
// pedersen_ptr - Pointer to the hash builtin.
// shared_state - The initial shared state
// squashed_carried_state - The squashed carried state representing the updated state.
// general_config - The general config (It doesn't change throughout the program so it's both
//   initial and updated).
//
// Returns:
// pedersen_ptr - Pointer to the hash builtin.
// shared_state - The shared state that corresponds to the updated state.
func shared_state_apply_state_updates(
    pedersen_ptr: HashBuiltin*,
    shared_state: SharedState*,
    squashed_carried_state: SquashedCarriedState*,
    general_config: GeneralConfig*,
) -> (pedersen_ptr: HashBuiltin*, shared_state: SharedState*) {
    alloc_locals;

    // Hash position updates.
    local n_position_updates = (
        squashed_carried_state.positions_dict_end - squashed_carried_state.positions_dict
    ) / DictAccess.SIZE;
    let (hashed_position_updates_ptr) = hash_position_updates{pedersen_ptr=pedersen_ptr}(
        update_ptr=squashed_carried_state.positions_dict, n_updates=n_position_updates
    );

    // Merkle update positions dict.
    local new_positions_root;
    // new_positions_root is defined in services/perpetual/cairo/main.cairo.
    %{ ids.new_positions_root = new_positions_root %}
    merkle_multi_update{hash_ptr=pedersen_ptr}(
        update_ptr=hashed_position_updates_ptr,
        n_updates=n_position_updates,
        height=general_config.positions_tree_height,
        prev_root=shared_state.positions_root,
        new_root=new_positions_root,
    );
    // Merkle update orders dict.
    local new_orders_root;
    let n_updates = (squashed_carried_state.orders_dict_end - squashed_carried_state.orders_dict) /
        DictAccess.SIZE;
    %{ ids.new_orders_root = new_orders_root %}
    merkle_multi_update{hash_ptr=pedersen_ptr}(
        update_ptr=squashed_carried_state.orders_dict,
        n_updates=n_updates,
        height=general_config.orders_tree_height,
        prev_root=shared_state.orders_root,
        new_root=new_orders_root,
    );

    // Return SharedState.
    let (shared_state) = shared_state_new(
        positions_root=new_positions_root,
        positions_tree_height=general_config.positions_tree_height,
        orders_root=new_orders_root,
        orders_tree_height=general_config.orders_tree_height,
        global_funding_indices=squashed_carried_state.global_funding_indices,
        oracle_prices=squashed_carried_state.oracle_prices,
        system_time=squashed_carried_state.system_time,
    );
    return (pedersen_ptr=pedersen_ptr, shared_state=shared_state);
}

func shared_state_serialize{output_ptr: felt*}(shared_state: SharedState*) {
    alloc_locals;
    local output_start_ptr: felt* = output_ptr;
    // Storing an empty slot for the size of the structure which will be filled later in the code.
    // A single slot due to the implementation of serialize_word which increments the ptr by one.
    let output_ptr = output_ptr + 1;
    serialize_word(shared_state.positions_root);
    serialize_word(shared_state.positions_tree_height);
    serialize_word(shared_state.orders_root);
    serialize_word(shared_state.orders_tree_height);
    funding_indices_info_serialize(shared_state.global_funding_indices);
    let (callback_adddress) = get_label_location(label_value=oracle_price_serialize);
    serialize_array(
        array=shared_state.oracle_prices.data,
        n_elms=shared_state.oracle_prices.len,
        elm_size=OraclePrice.SIZE,
        callback=callback_adddress,
    );
    serialize_word(shared_state.system_time);
    let size = cast(output_ptr, felt) - cast(output_start_ptr, felt) - 1;
    serialize_word{output_ptr=output_start_ptr}(size);
    return ();
}

// Converts a shared state into a carried state.
// Arguments:
// shared_state - The current shared state.
//
// Hint Arguments:
// positions_dict - A dict mapping between a position id and its position.
// orders_dict - A dict mapping between an order id and its order's state.
func shared_state_to_carried_state(shared_state: SharedState*) -> (carried_state: CarriedState*) {
    %{ initial_dict = positions_dict %}
    let (positions_dict: DictAccess*) = dict_new();
    %{ initial_dict = orders_dict %}
    let (orders_dict: DictAccess*) = dict_new();
    return carried_state_new(
        positions_dict=positions_dict,
        orders_dict=orders_dict,
        global_funding_indices=shared_state.global_funding_indices,
        oracle_prices=shared_state.oracle_prices,
        system_time=shared_state.system_time,
    );
}
