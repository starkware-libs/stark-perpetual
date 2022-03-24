%builtins output pedersen range_check ecdsa

from services.perpetual.cairo.definitions.general_config_hash import (
    general_config_hash, general_config_hash_synthetic_assets)
from services.perpetual.cairo.execute_batch import execute_batch
from services.perpetual.cairo.output.data_availability import output_availability_data
from services.perpetual.cairo.output.forced import ForcedAction
from services.perpetual.cairo.output.program_input import ProgramInput
from services.perpetual.cairo.output.program_output import (
    Modification, ProgramOutput, perpetual_outputs_empty, program_output_new,
    program_output_serialize)
from services.perpetual.cairo.state.state import (
    CarriedState, SquashedCarriedState, carried_state_squash, shared_state_apply_state_updates,
    shared_state_to_carried_state)
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.registers import get_fp_and_pc

# Hint argument:
# program_input - An object that has the following fields:
#   program_input_struct - The fields of ProgramInput.
#   positions_dict - A dictionary from position id to position.
#   orders_dict - A dictionary from order id to order state.
#   max_n_words_per_memory_page - Amount of words that can fit in a memory page.
#   merkle_facts - A dictionary from the hash value of a merkle node to the pair of children values.
func main(
        output_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        ecdsa_ptr : SignatureBuiltin*) -> (
        output_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr,
        ecdsa_ptr : SignatureBuiltin*):
    alloc_locals
    let (local __fp__, _) = get_fp_and_pc()
    local program_input : ProgramInput

    %{
        # Initialize program input and hint variables.
        segments.write_arg(ids.program_input.address_, program_input['program_input_struct'])
        positions_dict = {int(x): y for x,y in program_input['positions_dict'].items()}
        orders_dict = {int(x): y for x,y in program_input['orders_dict'].items()}
        max_n_words_per_memory_page = program_input['max_n_words_per_memory_page']

        def as_int(x):
            return int(x, 16)
        preimage = {
          as_int(root): (as_int(left_child), as_int(right_child))
          for root, (left_child, right_child) in program_input['merkle_facts'].items()
        }
    %}
    let (local initial_carried_state) = shared_state_to_carried_state(
        program_input.prev_shared_state)

    # Execute batch.
    let (local outputs_start) = perpetual_outputs_empty()
    let (local pedersen_ptr, range_check_ptr, local ecdsa_ptr, carried_state : CarriedState*,
        local outputs) = execute_batch(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=initial_carried_state,
        program_input=&program_input,
        outputs=outputs_start,
        txs=program_input.txs,
        end_system_time=program_input.new_shared_state.system_time)

    # Get updated shared state.
    with range_check_ptr:
        let (squashed_carried_state) = carried_state_squash(
            initial_carried_state=initial_carried_state, carried_state=carried_state)
    end
    local range_check_ptr = range_check_ptr
    local squashed_carried_state : SquashedCarriedState* = squashed_carried_state

    let positions_root = program_input.new_shared_state.positions_root
    let orders_root = program_input.new_shared_state.orders_root
    %{
        new_positions_root = ids.positions_root
        new_orders_root = ids.orders_root
    %}
    let (pedersen_ptr, local new_shared_state) = shared_state_apply_state_updates(
        pedersen_ptr=pedersen_ptr,
        shared_state=program_input.prev_shared_state,
        squashed_carried_state=squashed_carried_state,
        general_config=program_input.general_config)

    # Write public output.
    with pedersen_ptr:
        let (n_asset_configs, asset_configs) = general_config_hash_synthetic_assets(
            general_config_ptr=program_input.general_config)
        let (general_config_hash_value) = general_config_hash(
            general_config_ptr=program_input.general_config)
    end
    local pedersen_ptr : HashBuiltin* = pedersen_ptr
    let (program_output : ProgramOutput*) = program_output_new(
        general_config_hash=general_config_hash_value,
        n_asset_configs=n_asset_configs,
        asset_configs=asset_configs,
        prev_shared_state=program_input.prev_shared_state,
        new_shared_state=new_shared_state,
        minimum_expiration_timestamp=program_input.minimum_expiration_timestamp,
        n_modifications=(
        outputs.modifications_ptr - outputs_start.modifications_ptr) / Modification.SIZE,
        modifications=outputs_start.modifications_ptr,
        n_forced_actions=(
        outputs.forced_actions_ptr - outputs_start.forced_actions_ptr) / ForcedAction.SIZE,
        forced_actions=outputs_start.forced_actions_ptr,
        n_conditions=outputs.conditions_ptr - outputs_start.conditions_ptr,
        conditions=outputs_start.conditions_ptr)

    with output_ptr:
        program_output_serialize(program_output=program_output)
    end

    %{ onchain_data_start = ids.output_ptr %}

    let (range_check_ptr, output_ptr) = output_availability_data(
        range_check_ptr=range_check_ptr,
        output_ptr=output_ptr,
        squashed_state=squashed_carried_state,
        perpetual_outputs_start=outputs_start,
        perpetual_outputs_end=outputs)

    %{
        from starkware.python.math_utils import div_ceil
        onchain_data_size = ids.output_ptr - onchain_data_start
        assert onchain_data_size > 0, 'Empty onchain data is not supported.'

        # Split the output into pages.
        n_pages = div_ceil(onchain_data_size, max_n_words_per_memory_page)
        for i in range(n_pages):
            start_offset = i * max_n_words_per_memory_page
            output_builtin.add_page(
                page_id=1 + i,
                page_start=onchain_data_start + start_offset,
                page_size=min(onchain_data_size - start_offset, max_n_words_per_memory_page),
            )

        # Set the tree structure to a root with two children:
        # * A leaf which represents the main part
        # * An inner node for the onchain data part (which contains n_pages children).
        #
        # This is encoded using the following sequence:
        output_builtin.add_attribute('gps_fact_topology', [
            # Push 1 + n_pages pages (all of the pages).
            1 + n_pages,
            # Create a parent node for the last n_pages.
            n_pages,
            # Don't push additional pages.
            0,
            # Take the first page (the main part) and the node that was created (onchain data)
            # and use them to construct the root of the fact tree.
            2,
        ])
    %}

    return (
        output_ptr=output_ptr,
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr)
end
