from services.perpetual.cairo.definitions.objects import (
    FundingIndicesInfo,
    funding_indices_info_serialize,
)
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.position.serialize_change import serialize_position_change
from services.perpetual.cairo.state.state import SquashedCarriedState
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.serialize import serialize_array

const VALIDIUM_MODE = 0;
const ROLLUP_MODE = 1;

// Serializes a single FundingIndicesInfo entry.
func funding_indices_info_ptr_serialize{output_ptr: felt*}(
    funding_indices_ptr: FundingIndicesInfo**
) {
    return funding_indices_info_serialize(funding_indices=[funding_indices_ptr]);
}

// Outputs the position changes.
func output_changed_positions(
    range_check_ptr, output_ptr: felt*, squashed_dict: DictAccess*, n_entries
) -> (range_check_ptr: felt, output_ptr: felt*) {
    if (n_entries == 0) {
        return (range_check_ptr=range_check_ptr, output_ptr=output_ptr);
    }

    let (range_check_ptr, output_ptr) = serialize_position_change(
        range_check_ptr=range_check_ptr, output_ptr=output_ptr, dict_access=squashed_dict
    );

    return output_changed_positions(
        range_check_ptr=range_check_ptr,
        output_ptr=output_ptr,
        squashed_dict=squashed_dict + DictAccess.SIZE,
        n_entries=n_entries - 1,
    );
}

// Outputs the data required for data availability.
func output_availability_data(
    range_check_ptr,
    output_ptr: felt*,
    squashed_state: SquashedCarriedState*,
    perpetual_outputs_start: PerpetualOutputs*,
    perpetual_outputs_end: PerpetualOutputs*,
) -> (range_check_ptr: felt, output_ptr: felt*) {
    alloc_locals;

    // Serialize the funding indices table.
    let (callback_address) = get_label_location(label_value=funding_indices_info_ptr_serialize);
    let funding_indices_table_size = (
        perpetual_outputs_end.funding_indices_table_ptr -
        perpetual_outputs_start.funding_indices_table_ptr
    );

    with output_ptr {
        serialize_array(
            array=cast(perpetual_outputs_start.funding_indices_table_ptr, felt*),
            n_elms=funding_indices_table_size,
            elm_size=1,
            callback=callback_address,
        );
    }

    // Serialize the position changes.
    let dict_len = (
        cast(squashed_state.positions_dict_end, felt) - cast(squashed_state.positions_dict, felt)
    );
    let (range_check_ptr, output_ptr) = output_changed_positions(
        range_check_ptr=range_check_ptr,
        output_ptr=output_ptr,
        squashed_dict=squashed_state.positions_dict,
        n_entries=dict_len / DictAccess.SIZE,
    );

    return (range_check_ptr=range_check_ptr, output_ptr=output_ptr);
}
