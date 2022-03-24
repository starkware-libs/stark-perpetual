from services.perpetual.cairo.definitions.constants import AMOUNT_UPPER_BOUND
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.perpetual_error_code import (
    PerpetualErrorCode, assert_success)
from services.perpetual.cairo.output.forced import (
    ForcedAction, ForcedActionType, forced_trade_action_new)
from services.perpetual.cairo.output.program_output import PerpetualOutputs, perpetual_outputs_new
from services.perpetual.cairo.position.position import Position
from services.perpetual.cairo.position.update_position import update_position
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.dict import dict_update
from starkware.cairo.common.math import assert_nn_le, assert_not_equal

struct ForcedTrade:
    member public_key_a : felt
    member public_key_b : felt
    member position_id_a : felt
    member position_id_b : felt
    member synthetic_asset_id : felt
    member amount_collateral : felt
    member amount_synthetic : felt
    member is_party_a_buying_synthetic : felt
    member nonce : felt
    member is_valid : felt
end

func try_to_trade(
        range_check_ptr, carried_state : CarriedState*, position_buyer : Position*,
        position_seller : Position*, public_key_buyer, public_key_seller, synthetic_asset_id,
        amount_collateral, amount_synthetic, general_config : GeneralConfig*) -> (
        range_check_ptr, position_buyer : Position*, position_seller : Position*, return_code):
    alloc_locals
    # update_position will return the funded position as the updated position if it failed.
    let (range_check_ptr, local updated_position_buyer, local funded_position_buyer,
        local return_code_a) = update_position(
        range_check_ptr=range_check_ptr,
        position=position_buyer,
        request_public_key=public_key_buyer,
        collateral_delta=-amount_collateral,
        synthetic_asset_id=synthetic_asset_id,
        synthetic_delta=amount_synthetic,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config)
    # This could be optimized. In the case that the buyer's update fails, we can just compute the
    # seller's funded position without computing the updated position.
    # Since forced trade is a rare transaction, this optimization isn't implemented.
    let (range_check_ptr, local updated_position_seller, local funded_position_seller,
        local return_code_b) = update_position(
        range_check_ptr=range_check_ptr,
        position=position_seller,
        request_public_key=public_key_seller,
        collateral_delta=amount_collateral,
        synthetic_asset_id=synthetic_asset_id,
        synthetic_delta=-amount_synthetic,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config)

    # Assumes that the return code for success is zero and all other error codes are positive.
    if return_code_a + return_code_b == 0:
        return (
            range_check_ptr=range_check_ptr,
            position_buyer=updated_position_buyer,
            position_seller=updated_position_seller,
            return_code=PerpetualErrorCode.SUCCESS)
    end
    local return_code
    if return_code_a == 0:
        return_code = return_code_b
    else:
        return_code = return_code_a
    end
    return (
        range_check_ptr=range_check_ptr,
        position_buyer=funded_position_buyer,
        position_seller=funded_position_seller,
        return_code=return_code)
end

# Executes a forced trade between two parties, where both partied agree on the exact trade details.
# The forced trade is requested by party_a onchain, and is signed by party_b (verified onchain).
# The forced trade can be specified as false forced trade with the is_valid member. The following
# assumptions are made on the transaction and aren't guaranteed to be accepted on a false trade if
# they aren't met:
#   1. Position id is in range.
#   2. The trade is between two different positions.
#   3. The collateral asset id is indeed collateral.
#   4. The synthetic asset id is in the configuration.
#   5. The amounts are in range.
#   6. The nonce is in range.
func execute_forced_trade(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, batch_config : BatchConfig*, outputs : PerpetualOutputs*,
        tx : ForcedTrade*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals

    # Check fields.
    # public_keys are valid since they come from the previous position.
    # position_ids are verified by being a dict key.
    # synthetic_asset_id is verified in add_asset.
    # Note: We don't mind failing here even when is_valid is 0, since the amount and the position_id
    # should be verified on-chain when a user makes the forced action request.
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount_collateral, AMOUNT_UPPER_BOUND - 1)
    assert_nn_le{range_check_ptr=range_check_ptr}(tx.amount_synthetic, AMOUNT_UPPER_BOUND - 1)
    %{ error_code = ids.PerpetualErrorCode.SAME_POSITION_ID %}
    assert_not_equal(tx.position_id_a, tx.position_id_b)

    # Read both positions.
    local position_a : Position*
    local position_b : Position*
    let positions_dict = carried_state.positions_dict
    %{
        del error_code
        ids.position_a = __dict_manager.get_dict(ids.positions_dict)[ids.tx.position_id_a]
        ids.position_b = __dict_manager.get_dict(ids.positions_dict)[ids.tx.position_id_b]
    %}

    local new_position_a : Position*
    local new_position_b : Position*
    # Try to update the position.
    if tx.is_party_a_buying_synthetic != 0:
        let (range_check_ptr, new_position_buyer, new_position_seller, return_code) = try_to_trade(
            range_check_ptr=range_check_ptr,
            carried_state=carried_state,
            position_buyer=position_a,
            position_seller=position_b,
            public_key_buyer=tx.public_key_a,
            public_key_seller=tx.public_key_b,
            synthetic_asset_id=tx.synthetic_asset_id,
            amount_collateral=tx.amount_collateral,
            amount_synthetic=tx.amount_synthetic,
            general_config=batch_config.general_config)
        new_position_a = new_position_buyer
        new_position_b = new_position_seller
    else:
        let (range_check_ptr, new_position_buyer, new_position_seller, return_code) = try_to_trade(
            range_check_ptr=range_check_ptr,
            carried_state=carried_state,
            position_buyer=position_b,
            position_seller=position_a,
            public_key_buyer=tx.public_key_b,
            public_key_seller=tx.public_key_a,
            synthetic_asset_id=tx.synthetic_asset_id,
            amount_collateral=tx.amount_collateral,
            amount_synthetic=tx.amount_synthetic,
            general_config=batch_config.general_config)
        new_position_a = new_position_seller
        new_position_b = new_position_buyer
    end

    local range_check_ptr = range_check_ptr
    if tx.is_valid != 0:
        assert_success(return_code)
    else:
        assert_not_equal(return_code, PerpetualErrorCode.SUCCESS)
    end

    # Update positions.
    dict_update{dict_ptr=positions_dict}(
        key=tx.position_id_a,
        prev_value=cast(position_a, felt),
        new_value=cast(new_position_a, felt))
    dict_update{dict_ptr=positions_dict}(
        key=tx.position_id_b,
        prev_value=cast(position_b, felt),
        new_value=cast(new_position_b, felt))

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=carried_state.orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time)

    # Write the forced action to output.
    let forced_action : ForcedAction* = outputs.forced_actions_ptr
    assert forced_action.forced_type = ForcedActionType.FORCED_TRADE
    let (forced_trade_action) = forced_trade_action_new(
        public_key_a=tx.public_key_a,
        public_key_b=tx.public_key_b,
        position_id_a=tx.position_id_a,
        position_id_b=tx.position_id_b,
        synthetic_asset_id=tx.synthetic_asset_id,
        amount_collateral=tx.amount_collateral,
        amount_synthetic=tx.amount_synthetic,
        is_party_a_buying_synthetic=tx.is_party_a_buying_synthetic,
        nonce=tx.nonce)
    assert forced_action.forced_action = cast(forced_trade_action, felt*)

    let (outputs) = perpetual_outputs_new(
        modifications_ptr=outputs.modifications_ptr,
        forced_actions_ptr=outputs.forced_actions_ptr + ForcedAction.SIZE,
        conditions_ptr=outputs.conditions_ptr,
        funding_indices_table_ptr=outputs.funding_indices_table_ptr)
    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
