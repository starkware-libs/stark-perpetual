from services.perpetual.cairo.definitions.constants import (
    ASSET_ID_UPPER_BOUND, FUNDING_INDEX_LOWER_BOUND, FUNDING_INDEX_UPPER_BOUND, FXP_32_ONE)
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.objects import (
    FundingIndicesInfo, OraclePrice, OraclePrices)
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.output.program_output import PerpetualOutputs, perpetual_outputs_new
from services.perpetual.cairo.position.funding import FundingIndex
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import abs_value, assert_in_range, assert_le, assert_le_250_bit
from starkware.cairo.common.registers import get_fp_and_pc

struct FundingTick:
    member global_funding_indices : FundingIndicesInfo*
end

# Validate that funding index diff isn't too large. In other words, that:
# abs(change_in_funding_index) <= max_funding_rate * price * change_in_timestamp.
func validate_funding_index_diff_in_range(
        range_check_ptr, max_funding_rate, funding_index_diff, timestamp_diff, price) -> (
        range_check_ptr):
    let (funding_index_diff) = abs_value{range_check_ptr=range_check_ptr}(funding_index_diff)
    # Using 250 bit version here because the second argument can be up to 2**160.
    assert_le_250_bit{range_check_ptr=range_check_ptr}(
        funding_index_diff * FXP_32_ONE, max_funding_rate * price * timestamp_diff)
    return (range_check_ptr)
end

# Arguments to validate_funding_tick_inner that remain constant throughout the recursive call.
struct ValidateFundingTickInnerArgs:
    member max_funding_rate : felt
    member timestamp_diff : felt
end

func validate_funding_tick_inner_args_new(max_funding_rate, timestamp_diff) -> (
        args : ValidateFundingTickInnerArgs*):
    let (fp_val, pc_val) = get_fp_and_pc()
    # We refer to the arguments of this function as a ValidateFundingTickInnerArgs object
    # (fp_val - 2 points to the end of the function arguments in the stack).
    return (
        args=cast(fp_val - 2 - ValidateFundingTickInnerArgs.SIZE, ValidateFundingTickInnerArgs*))
end

# Validates the funding tick recursively. Refer to the documentation of `validate_funding_tick` for
# the conditions a valid funding tick needs to hold.
# Each recursive call will advance new_funding_index_ptr and oracle_price_ptr until they point to an
# object with an asset_id that matches prev_funding_index_ptr. If no corresponding asset_id is found
# the function will fail. Then it will validate the funding diff according to the price (see
# 'validate_funding_index_diff_in_range'). After that it will advance prev_funding_index_ptr and
# repeat.
func validate_funding_tick_inner(
        range_check_ptr, prev_funding_index_ptr : FundingIndex*,
        new_funding_index_ptr : FundingIndex*, oracle_price_ptr : OraclePrice*,
        last_new_funding_asset_id, args : ValidateFundingTickInnerArgs*) -> (
        range_check_ptr, prev_funding_index_ptr : FundingIndex*,
        new_funding_index_ptr : FundingIndex*, oracle_price_ptr : OraclePrice*):
    alloc_locals
    local should_continue
    local should_advance_oracle_price
    local should_advance_new_funding_index
    %{
        # Decide non-deterministically whether to advance oracle_price_ptr, new_funding_index_ptr.
        # Also decide if we checked all the assets.
        # validate_funding_tick will ensure that the final pointers are equal to the end pointers.
        # This is sound because prev_funding_index_ptr will not advance until the other 2 pointers
        # will have its asset id.
        is_prev_funding_index_done = \
            ids.prev_funding_index_ptr.address_ == prev_funding_index_end.address_
        is_new_funding_index_done = \
            ids.new_funding_index_ptr.address_ == new_funding_index_end.address_
        is_oracle_price_done = ids.oracle_price_ptr.address_ == oracle_price_end.address_

        prev_asset_id = \
            ids.prev_funding_index_ptr.asset_id if not is_prev_funding_index_done \
            else ids.ASSET_ID_UPPER_BOUND
        new_asset_id = \
            ids.new_funding_index_ptr.asset_id if not is_new_funding_index_done \
            else ids.ASSET_ID_UPPER_BOUND
        oracle_asset_id = \
            ids.oracle_price_ptr.asset_id if not is_oracle_price_done else ids.ASSET_ID_UPPER_BOUND

        ids.should_advance_new_funding_index = int(new_asset_id < prev_asset_id)
        ids.should_advance_oracle_price = int(oracle_asset_id < prev_asset_id)
        ids.should_continue = int(
            not (is_prev_funding_index_done and is_new_funding_index_done and is_oracle_price_done))
    %}
    if should_continue == 0:
        assert_le{range_check_ptr=range_check_ptr}(
            last_new_funding_asset_id + 1, ASSET_ID_UPPER_BOUND)
        should_advance_oracle_price = should_advance_oracle_price
        should_advance_new_funding_index = should_advance_new_funding_index
        return (
            range_check_ptr=range_check_ptr,
            prev_funding_index_ptr=prev_funding_index_ptr,
            new_funding_index_ptr=new_funding_index_ptr,
            oracle_price_ptr=oracle_price_ptr)
    end

    # Since we need to validate that prev_funding_indices is contained in new_funding_indices and
    # in oracle_prices, we will advance new_funding_index_ptr and oracle_price_ptr until its asset
    # id is equal to current_asset_id.
    if should_advance_oracle_price != 0:
        should_advance_new_funding_index = should_advance_new_funding_index
        return validate_funding_tick_inner(
            range_check_ptr=range_check_ptr,
            prev_funding_index_ptr=prev_funding_index_ptr,
            new_funding_index_ptr=new_funding_index_ptr,
            oracle_price_ptr=oracle_price_ptr + OraclePrice.SIZE,
            last_new_funding_asset_id=last_new_funding_asset_id,
            args=args)
    end

    # We are always going to advance new_funding_index_ptr if we reached here. Therefore we will now
    # check that its asset_id is larger than its previous asset_id and that the index is in range.
    assert_le{range_check_ptr=range_check_ptr}(
        last_new_funding_asset_id + 1, new_funding_index_ptr.asset_id)
    %{ error_code = ids.PerpetualErrorCode.OUT_OF_RANGE_FUNDING_INDEX %}
    assert_in_range{range_check_ptr=range_check_ptr}(
        new_funding_index_ptr.funding_index, FUNDING_INDEX_LOWER_BOUND, FUNDING_INDEX_UPPER_BOUND)
    %{ del error_code %}

    if should_advance_new_funding_index != 0:
        return validate_funding_tick_inner(
            range_check_ptr=range_check_ptr,
            prev_funding_index_ptr=prev_funding_index_ptr,
            new_funding_index_ptr=new_funding_index_ptr + FundingIndex.SIZE,
            oracle_price_ptr=oracle_price_ptr,
            last_new_funding_asset_id=new_funding_index_ptr.asset_id,
            args=args)
    end

    tempvar current_asset_id = prev_funding_index_ptr.asset_id
    current_asset_id = new_funding_index_ptr.asset_id
    current_asset_id = oracle_price_ptr.asset_id

    # Now all asset ids are equal. We need to check the rate of the funding change.
    # If we are here, then prev_funding_index_ptr hasn't reached its end.
    let (range_check_ptr) = validate_funding_index_diff_in_range(
        range_check_ptr=range_check_ptr,
        max_funding_rate=args.max_funding_rate,
        funding_index_diff=new_funding_index_ptr.funding_index - prev_funding_index_ptr.funding_index,
        timestamp_diff=args.timestamp_diff,
        price=oracle_price_ptr.price)

    return validate_funding_tick_inner(
        range_check_ptr=range_check_ptr,
        prev_funding_index_ptr=prev_funding_index_ptr + FundingIndex.SIZE,
        new_funding_index_ptr=new_funding_index_ptr + FundingIndex.SIZE,
        oracle_price_ptr=oracle_price_ptr + OraclePrice.SIZE,
        last_new_funding_asset_id=new_funding_index_ptr.asset_id,
        args=args)
end

# Validate that:
# 1. prev_funding_indices is contained in new funding indices.
# 2. prev_funding_indices is contained in oracle prices.
# 3. new funding indices are in range for indices that are in prev_funding_indices.
# 4. new_funding_indices is sorted and has no duplicates.
func validate_funding_tick(
        range_check_ptr, carried_state : CarriedState*, general_config : GeneralConfig*,
        new_funding_indices : FundingIndicesInfo*) -> (range_check_ptr):
    alloc_locals
    tempvar prev_funding_indices : FundingIndicesInfo* = carried_state.global_funding_indices
    tempvar oracle_prices : OraclePrices* = carried_state.oracle_prices

    let (args) = validate_funding_tick_inner_args_new(
        max_funding_rate=general_config.max_funding_rate,
        timestamp_diff=(
        new_funding_indices.funding_timestamp - prev_funding_indices.funding_timestamp))

    local prev_funding_index_end : FundingIndex* = (
        prev_funding_indices.funding_indices +
        FundingIndex.SIZE * prev_funding_indices.n_funding_indices)
    local new_funding_index_end : FundingIndex* = (
        new_funding_indices.funding_indices +
        FundingIndex.SIZE * new_funding_indices.n_funding_indices)
    local oracle_price_end : OraclePrice* = (
        oracle_prices.data + OraclePrice.SIZE * oracle_prices.len)
    %{
        prev_funding_index_end = ids.prev_funding_index_end
        new_funding_index_end = ids.new_funding_index_end
        oracle_price_end = ids.oracle_price_end
    %}

    let (range_check_ptr, returned_prev_funding_index_ptr, returned_new_funding_index_ptr,
        returned_oracle_price_ptr) = validate_funding_tick_inner(
        range_check_ptr=range_check_ptr,
        prev_funding_index_ptr=prev_funding_indices.funding_indices,
        new_funding_index_ptr=new_funding_indices.funding_indices,
        oracle_price_ptr=oracle_prices.data,
        last_new_funding_asset_id=-1,
        args=args)

    # Validate that all the asset_ids that validate_funding_tick_inner() went through are all the
    # asset ids there are.
    prev_funding_index_end = returned_prev_funding_index_ptr
    new_funding_index_end = returned_new_funding_index_ptr
    oracle_price_end = returned_oracle_price_ptr

    return (range_check_ptr)
end

func execute_funding_tick(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : FundingTick*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    let new_funding_indices : FundingIndicesInfo* = tx.global_funding_indices
    # Check that new timestamp is not smaller than previous system time.
    # If signatures will be required to verify OraclePricesTick, then the timestamps for the
    # oracle prices in the carried state will be verified here.
    assert_le{range_check_ptr=range_check_ptr}(
        carried_state.system_time, new_funding_indices.funding_timestamp)

    let (range_check_ptr) = validate_funding_tick(
        range_check_ptr=range_check_ptr,
        carried_state=carried_state,
        general_config=batch_config.general_config,
        new_funding_indices=new_funding_indices)

    let (new_carried_state) = carried_state_new(
        positions_dict=carried_state.positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=new_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=new_funding_indices.funding_timestamp)

    assert [outputs.funding_indices_table_ptr] = new_funding_indices

    let (outputs : PerpetualOutputs*) = perpetual_outputs_new(
        modifications_ptr=outputs.modifications_ptr,
        forced_actions_ptr=outputs.forced_actions_ptr,
        conditions_ptr=outputs.conditions_ptr,
        funding_indices_table_ptr=outputs.funding_indices_table_ptr + 1)

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=new_carried_state,
        outputs=outputs)
end
