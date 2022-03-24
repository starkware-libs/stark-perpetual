from services.perpetual.cairo.definitions.general_config_hash import AssetConfigHashEntry
from services.perpetual.cairo.definitions.objects import FundingIndicesInfo
from services.perpetual.cairo.output.forced import ForcedAction, forced_action_serialize
from services.perpetual.cairo.state.state import SharedState, shared_state_serialize
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.serialize import serialize_array, serialize_word

# Represents an external modification to the amount of collateral in a position (Deposit or
# withdrawal).
struct Modification:
    member public_key : felt
    member position_id : felt
    # Biased representation. biased_delta is in range [0, 2**65), where 2**64 means 0 change.
    # The effective difference is biased_delta - 2**64.
    member biased_delta : felt
end

func modification_serialize{output_ptr : felt*}(modification : Modification*):
    serialize_word(modification.public_key)
    serialize_word(modification.position_id)
    serialize_word(modification.biased_delta)
    return ()
end

func asset_config_hash_serialize{output_ptr : felt*}(asset_config_hash : AssetConfigHashEntry*):
    serialize_word(asset_config_hash.asset_id)
    serialize_word(asset_config_hash.config_hash)
    return ()
end

# Represents the entire output of the program.
struct ProgramOutput:
    member general_config_hash : felt
    member n_asset_configs : felt
    member asset_configs : AssetConfigHashEntry*
    member prev_shared_state : SharedState*
    member new_shared_state : SharedState*
    member minimum_expiration_timestamp : felt

    member n_modifications : felt
    member modifications : Modification*
    member n_forced_actions : felt
    member forced_actions : ForcedAction*
    member n_conditions : felt
    member conditions : felt*
end

func program_output_new(
        general_config_hash, n_asset_configs, asset_configs : AssetConfigHashEntry*,
        prev_shared_state : SharedState*, new_shared_state : SharedState*,
        minimum_expiration_timestamp, n_modifications, modifications : Modification*,
        n_forced_actions, forced_actions : ForcedAction*, n_conditions, conditions : felt*) -> (
        program_output : ProgramOutput*):
    let (fp_val, pc_val) = get_fp_and_pc()
    # We refer to the arguments of this function as a ProgramOutput object
    # (fp_val - 2 points to the end of the function arguments in the stack).
    return (program_output=cast(fp_val - 2 - ProgramOutput.SIZE, ProgramOutput*))
end

# Represents the outputs that were accumulated during the execution of the batch.
struct PerpetualOutputs:
    member modifications_ptr : Modification*
    member forced_actions_ptr : ForcedAction*
    member conditions_ptr : felt*
    # A log of all the funding indices. When serializing a position change, The funding
    # timestamp is serialized instead of the funding indices and it can be looked up in this log.
    member funding_indices_table_ptr : FundingIndicesInfo**
end

func perpetual_outputs_new(
        modifications_ptr : Modification*, forced_actions_ptr : ForcedAction*,
        conditions_ptr : felt*, funding_indices_table_ptr : FundingIndicesInfo**) -> (
        outputs : PerpetualOutputs*):
    let (fp_val, pc_val) = get_fp_and_pc()
    # We refer to the arguments of this function as a PerpetualOutputs object
    # (fp_val - 2 points to the end of the function arguments in the stack).
    return (outputs=cast(fp_val - 2 - PerpetualOutputs.SIZE, PerpetualOutputs*))
end

func perpetual_outputs_empty() -> (outputs : PerpetualOutputs*):
    let (modifications_ptr : Modification*) = alloc()
    let (forced_actions_ptr : ForcedAction*) = alloc()
    let (conditions_ptr : felt*) = alloc()
    let (funding_indices_table_ptr : FundingIndicesInfo**) = alloc()
    return perpetual_outputs_new(
        modifications_ptr=modifications_ptr,
        forced_actions_ptr=forced_actions_ptr,
        conditions_ptr=conditions_ptr,
        funding_indices_table_ptr=funding_indices_table_ptr)
end

func program_output_serialize{output_ptr : felt*}(program_output : ProgramOutput*):
    alloc_locals

    let (_, __pc__) = get_fp_and_pc()

    ret_pc_label:
    local __pc__ = __pc__

    serialize_word(program_output.general_config_hash)
    let (callback_address) = get_label_location(asset_config_hash_serialize)
    serialize_array(
        array=program_output.asset_configs,
        n_elms=program_output.n_asset_configs,
        elm_size=AssetConfigHashEntry.SIZE,
        callback=callback_address)
    shared_state_serialize(program_output.prev_shared_state)
    shared_state_serialize(program_output.new_shared_state)

    serialize_word(program_output.minimum_expiration_timestamp)

    # Modifications.
    let (callback_address) = get_label_location(modification_serialize)
    serialize_array(
        array=program_output.modifications,
        n_elms=program_output.n_modifications,
        elm_size=Modification.SIZE,
        callback=callback_address)
    # Forced actions.
    # Save a cell for total size of forced actions.
    local forced_actions_size_output_ptr : felt* = output_ptr
    let output_ptr = output_ptr + 1
    let (callback_address) = get_label_location(forced_action_serialize)
    serialize_array(
        array=program_output.forced_actions,
        n_elms=program_output.n_forced_actions,
        elm_size=ForcedAction.SIZE,
        callback=callback_address)
    # output_ptr - forced_actions_size_output_ptr is the size of written data including
    # forced_actions_size and n_forced_actions.
    let data_size = cast(output_ptr, felt) - cast(forced_actions_size_output_ptr, felt) - 2
    serialize_word{output_ptr=forced_actions_size_output_ptr}(data_size)

    # Conditions.
    serialize_word(program_output.n_conditions)
    local output_ptr : felt* = output_ptr
    memcpy(dst=output_ptr, src=program_output.conditions, len=program_output.n_conditions)
    let output_ptr = output_ptr + program_output.n_conditions
    return ()
end
