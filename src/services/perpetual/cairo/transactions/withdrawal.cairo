from services.exchange.cairo.order import OrderBase
from services.perpetual.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND,
    EXPIRATION_TIMESTAMP_UPPER_BOUND,
    NONCE_UPPER_BOUND,
    POSITION_ID_UPPER_BOUND,
)
from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.perpetual_error_code import assert_success
from services.perpetual.cairo.order.order import validate_order_and_update_fulfillment
from services.perpetual.cairo.output.program_output import (
    Modification,
    PerpetualOutputs,
    perpetual_outputs_new,
)
from services.perpetual.cairo.position.update_position import (
    NO_SYNTHETIC_DELTA_ASSET_ID,
    update_position_in_dict,
)
from services.perpetual.cairo.state.state import CarriedState, carried_state_new
from services.perpetual.cairo.transactions.batch_config import BatchConfig
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.hash import hash2

struct Withdrawal {
    base: OrderBase*,
    position_id: felt,
    amount: felt,
    owner_key: felt,
}

// withdrawal_hash:
// Computes the hash of withdrawal request.
//
// The hash is defined as h(w1, w2) where h is the starkware pedersen function and w1, w2 are as
// follows:
//   w1= asset_id_collateral
//   w2= 0x6 (10 bit) || vault_from (64 bit) || nonce (32 bit) || amount (64 bit)
//    || expiration_timestamp (32 bit) ||  0 (49 bit)
//
// Assumptions:
// 0 <= nonce < NONCE_UPPER_BOUND
// 0 <= position_id < POSITION_ID_UPPER_BOUND
// 0 <= expiration_timestamp < EXPIRATION_TIMESTAMP_UPPER_BOUND
// 0 <= amount < AMOUNT_UPPER_BOUND.
func withdrawal_hash(pedersen_ptr: HashBuiltin*, withdrawal: Withdrawal*, asset_id_collateral) -> (
    pedersen_ptr: HashBuiltin*, message: felt
) {
    alloc_locals;
    local packed_message0;
    local packed_message1;
    // If owner_key is equal to public key, this is a withdrawal of the old API and therefore the
    // transaction type id is different and the owner_key is not part of the message.
    local has_address = withdrawal.owner_key - withdrawal.base.public_key;
    local pedersen_ptr1: HashBuiltin*;
    const WITHDRAWAL = 6;
    const WITHDRAWAL_TO_OWNER_KEY = 7;

    if (has_address == 0) {
        packed_message0 = asset_id_collateral;
        packed_message1 = WITHDRAWAL;
        pedersen_ptr1 = pedersen_ptr;
    } else {
        let (message) = hash2{hash_ptr=pedersen_ptr}(x=asset_id_collateral, y=withdrawal.owner_key);
        packed_message0 = message;
        packed_message1 = WITHDRAWAL_TO_OWNER_KEY;
        pedersen_ptr1 = pedersen_ptr;
    }
    let packed_message1 = packed_message1 * POSITION_ID_UPPER_BOUND + withdrawal.position_id;
    let packed_message1 = packed_message1 * NONCE_UPPER_BOUND + withdrawal.base.nonce;
    let packed_message1 = packed_message1 * AMOUNT_UPPER_BOUND + withdrawal.amount;
    let expiration_timestamp = withdrawal.base.expiration_timestamp;
    let packed_message1 = packed_message1 * EXPIRATION_TIMESTAMP_UPPER_BOUND + expiration_timestamp;
    let packed_message1 = packed_message1 * (2 ** 49);  // Padding.

    let (message) = hash2{hash_ptr=pedersen_ptr1}(x=packed_message0, y=packed_message1);
    return (pedersen_ptr=pedersen_ptr1, message=message);
}

func execute_withdrawal(
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    batch_config: BatchConfig*,
    outputs: PerpetualOutputs*,
    tx: Withdrawal*,
) -> (
    pedersen_ptr: HashBuiltin*,
    range_check_ptr: felt,
    ecdsa_ptr: SignatureBuiltin*,
    carried_state: CarriedState*,
    outputs: PerpetualOutputs*,
) {
    alloc_locals;
    local general_config: GeneralConfig* = batch_config.general_config;

    // The amount, nonce and expiration_timestamp are range checked in
    // validate_order_and_update_fulfillment.
    // By using update_position_in_dict with tx.position_id we check that
    // 0 <= tx.position_id < 2**POSITION_TREE_HEIGHT = POSITION_ID_UPPER_BOUND.
    let (pedersen_ptr, message_hash) = withdrawal_hash(
        pedersen_ptr=pedersen_ptr,
        withdrawal=tx,
        asset_id_collateral=general_config.collateral_asset_info.asset_id,
    );

    let (range_check_ptr, ecdsa_ptr, orders_dict) = validate_order_and_update_fulfillment(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        orders_dict=carried_state.orders_dict,
        message_hash=message_hash,
        order=tx.base,
        min_expiration_timestamp=batch_config.min_expiration_timestamp,
        update_amount=tx.amount,
        full_amount=tx.amount,
    );

    let (range_check_ptr, positions_dict, _, _, return_code) = update_position_in_dict(
        range_check_ptr=range_check_ptr,
        positions_dict=carried_state.positions_dict,
        position_id=tx.position_id,
        request_public_key=tx.base.public_key,
        collateral_delta=-tx.amount,
        synthetic_asset_id=NO_SYNTHETIC_DELTA_ASSET_ID,
        synthetic_delta=0,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        general_config=general_config,
    );
    assert_success(return_code);

    let (carried_state) = carried_state_new(
        positions_dict=positions_dict,
        orders_dict=orders_dict,
        global_funding_indices=carried_state.global_funding_indices,
        oracle_prices=carried_state.oracle_prices,
        system_time=carried_state.system_time,
    );

    // Write to output.
    tempvar modification: Modification* = outputs.modifications_ptr;
    assert modification.owner_key = tx.owner_key;
    assert modification.position_id = tx.position_id;
    // For explanation why we add AMOUNT_UPPER_BOUND, see Modification's documentation.
    assert modification.biased_delta = AMOUNT_UPPER_BOUND - tx.amount;
    let (outputs: PerpetualOutputs*) = perpetual_outputs_new(
        modifications_ptr=modification + Modification.SIZE,
        forced_actions_ptr=outputs.forced_actions_ptr,
        conditions_ptr=outputs.conditions_ptr,
        funding_indices_table_ptr=outputs.funding_indices_table_ptr,
    );

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
    );
}
