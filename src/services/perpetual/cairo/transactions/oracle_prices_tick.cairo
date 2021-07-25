from services.perpetual.cairo.definitions.constants import ASSET_ID_UPPER_BOUND
from services.perpetual.cairo.definitions.objects import (
    OraclePrice, OraclePrices, oracle_prices_new)
from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.find_element import find_element, search_sorted_lower
from starkware.cairo.common.math import assert_in_range, assert_le
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.registers import get_fp_and_pc

# A tick containing oracle prices for assets.
# The tick does not contain signatures. Instead, at the start of each batch, signatures are verified
# for the minimal and maximal prices that appeared for each asset (which have the most potential to
# cause liquidations). Each OraclePricesTick is subsequently verified to be within this price range.
struct OraclePricesTick:
    member oracle_prices : OraclePrices*
    member timestamp : felt
end

# Inserts into new_oracle_price_ptr all prices from given array with asset_id less than
# asset_id_bound. Returns the amount of prices inserted.
func insert_oracle_prices_until_asset_id(
        range_check_ptr, oracle_price_ptr : OraclePrice*, n_oracle_prices, asset_id_bound,
        new_oracle_price_ptr : OraclePrice*) -> (range_check_ptr, n_new_oracle_prices):
    alloc_locals
    static_assert OraclePrice.asset_id == 0
    let (oracle_price_lower_end : OraclePrice*) = search_sorted_lower{
        range_check_ptr=range_check_ptr}(
        array_ptr=oracle_price_ptr,
        elm_size=OraclePrice.SIZE,
        n_elms=n_oracle_prices,
        key=asset_id_bound)
    local range_check_ptr = range_check_ptr
    local oracle_prices_lower_size = (oracle_price_lower_end - oracle_price_ptr)
    memcpy(dst=new_oracle_price_ptr, src=oracle_price_ptr, len=oracle_prices_lower_size)
    return (
        range_check_ptr=range_check_ptr,
        n_new_oracle_prices=oracle_prices_lower_size / OraclePrice.SIZE)
end

# Creates a new oracle prices array that is sorted and contains all prices from
# prev_oracle_price_ptr and tick_price_ptr. If an asset has prices in both of them, the price from
# tick_price_ptr will be taken. Also validates that tick_price_ptr is sorted and its prices are in
# the range defined in batch_config.
# Returns the new range_check_ptr and the amount of oracle_prices inserted.
func create_new_oracle_prices_and_validate_tick(
        range_check_ptr, prev_oracle_price_ptr : OraclePrice*, n_oracle_prices,
        tick_price_ptr : OraclePrice*, n_tick_prices, last_tick_asset_id,
        batch_config : BatchConfig*, new_oracle_price_ptr : OraclePrice*) -> (
        range_check_ptr, n_new_oracle_prices):
    if n_tick_prices == 0:
        assert_le{range_check_ptr=range_check_ptr}(last_tick_asset_id + 1, ASSET_ID_UPPER_BOUND)
        return insert_oracle_prices_until_asset_id(
            range_check_ptr=range_check_ptr,
            oracle_price_ptr=prev_oracle_price_ptr,
            n_oracle_prices=n_oracle_prices,
            asset_id_bound=ASSET_ID_UPPER_BOUND,
            new_oracle_price_ptr=new_oracle_price_ptr)
    end
    alloc_locals

    # Inserting into new_oracle_price_ptr all prices from prev_oracle_price_ptr with asset ids
    # smaller than the asset id in tick_price_ptr.
    let (range_check_ptr, local n_oracle_prices_inserted) = insert_oracle_prices_until_asset_id(
        range_check_ptr=range_check_ptr,
        oracle_price_ptr=prev_oracle_price_ptr,
        n_oracle_prices=n_oracle_prices,
        asset_id_bound=tick_price_ptr.asset_id,
        new_oracle_price_ptr=new_oracle_price_ptr)

    %{ error_code = ids.PerpetualErrorCode.UNSORTED_ORACLE_PRICES %}
    assert_le{range_check_ptr=range_check_ptr}(last_tick_asset_id + 1, tick_price_ptr.asset_id)
    %{ del error_code %}

    # Asserting that price in tick is in the range defined in batch config.
    let (min_oracle_price : OraclePrice*) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=batch_config.signed_min_oracle_prices,
        elm_size=OraclePrice.SIZE,
        n_elms=batch_config.n_oracle_prices,
        key=tick_price_ptr.asset_id)

    let (max_oracle_price : OraclePrice*) = find_element{range_check_ptr=range_check_ptr}(
        array_ptr=batch_config.signed_max_oracle_prices,
        elm_size=OraclePrice.SIZE,
        n_elms=batch_config.n_oracle_prices,
        key=tick_price_ptr.asset_id)

    assert_in_range{range_check_ptr=range_check_ptr}(
        tick_price_ptr.price, min_oracle_price.price, max_oracle_price.price + 1)
    local range_check_ptr = range_check_ptr

    # Advance prev_oracle_price_ptr by n_oracle_prices_inserted.
    local prev_oracle_price_ptr : OraclePrice* = (
        prev_oracle_price_ptr + n_oracle_prices_inserted * OraclePrice.SIZE)
    # If the asset id in tick_price_ptr exists in prev_oracle_price_ptr, advance
    # prev_oracle_price_ptr by an extra 1.
    local oracle_price_ptr1 : OraclePrice*
    local n_oracle_prices1
    if n_oracle_prices != n_oracle_prices_inserted:
        if prev_oracle_price_ptr.asset_id == tick_price_ptr.asset_id:
            oracle_price_ptr1 = prev_oracle_price_ptr + OraclePrice.SIZE
            assert n_oracle_prices1 = n_oracle_prices - n_oracle_prices_inserted - 1
        else:
            oracle_price_ptr1 = prev_oracle_price_ptr
            n_oracle_prices1 = n_oracle_prices - n_oracle_prices_inserted
        end
    else:
        oracle_price_ptr1 = prev_oracle_price_ptr
        n_oracle_prices1 = n_oracle_prices - n_oracle_prices_inserted
    end
    let prev_oracle_price_ptr : OraclePrice* = oracle_price_ptr1
    let n_oracle_prices = n_oracle_prices1

    # Advance new_oracle_price_ptr by the amount of elements we inserted into it from
    # prev_oracle_price_ptr.
    let new_oracle_price_ptr = new_oracle_price_ptr + n_oracle_prices_inserted * OraclePrice.SIZE

    # Copy current tick asset into new_oracle_price_ptr.
    memcpy(dst=new_oracle_price_ptr, src=tick_price_ptr, len=OraclePrice.SIZE)
    let new_oracle_price_ptr = new_oracle_price_ptr + OraclePrice.SIZE

    let (range_check_ptr, n_new_oracle_prices) = create_new_oracle_prices_and_validate_tick(
        range_check_ptr=range_check_ptr,
        prev_oracle_price_ptr=prev_oracle_price_ptr,
        n_oracle_prices=n_oracle_prices,
        tick_price_ptr=tick_price_ptr + OraclePrice.SIZE,
        n_tick_prices=n_tick_prices - 1,
        last_tick_asset_id=tick_price_ptr.asset_id,
        batch_config=batch_config,
        new_oracle_price_ptr=new_oracle_price_ptr)
    return (
        range_check_ptr=range_check_ptr,
        n_new_oracle_prices=n_new_oracle_prices + n_oracle_prices_inserted + 1)
end

func execute_oracle_prices_tick(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : OraclePricesTick*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals
    # Check that new timestamp is larger than previous system time.
    assert_le{range_check_ptr=range_check_ptr}(carried_state.system_time, tx.timestamp)

    let (local new_oracle_price_ptr : OraclePrice*) = alloc()
    local tick_prices : OraclePrices* = tx.oracle_prices
    let (range_check_ptr, n_new_oracle_prices) = create_new_oracle_prices_and_validate_tick(
        range_check_ptr=range_check_ptr,
        prev_oracle_price_ptr=carried_state.oracle_prices.data,
        n_oracle_prices=carried_state.oracle_prices.len,
        tick_price_ptr=tick_prices.data,
        n_tick_prices=tick_prices.len,
        last_tick_asset_id=-1,
        batch_config=batch_config,
        new_oracle_price_ptr=new_oracle_price_ptr)
    let (oracle_prices) = oracle_prices_new(len=n_new_oracle_prices, data=new_oracle_price_ptr)

    let (carried_state) = carried_state_new(
        positions_dict=carried_state.positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=oracle_prices,
        system_time=tx.timestamp)
    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
