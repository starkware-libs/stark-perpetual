from services.exchange.cairo.definitions.constants import (
    AMOUNT_UPPER_BOUND,
    EXPIRATION_TIMESTAMP_UPPER_BOUND,
    NONCE_UPPER_BOUND,
    VAULT_ID_UPPER_BOUND,
)
from services.exchange.cairo.signature_message_hashes import ExchangeLimitOrder
from starkware.cairo.common.registers import get_fp_and_pc

// The L1 order message data written to the program output for each fulfilled L1 order.
// The L1 parallel of an L2 order signature.
struct L1OrderMessageOutput {
    eth_key: felt,
    // Amount of elements in the order message. Used to distinguish between other L1 messages with
    // different amount of elements. Currently the value of this will always be 5.
    n_elms: felt,
    token_sell: felt,
    token_buy: felt,
    token_fee: felt,
    // A packed field that consists of amount_sell, amount_buy, max_amount_fee, nonce and
    // message_type. The format is (from msb to lsb):
    //   amount_sell (64b) || amount_buy (64b) || max_amount_fee (64b) || nonce (32b).
    packed_message0: felt,
    // A packed field that consists of vault_fee_src, vault_fee, vault_buy and expiration_timestamp.
    // The format is (from msb to lsb):
    //   message_type (10b) (0x3 for limit order) || vault_fee_src (64b) || vault_sell (64b) ||
    //       vault_buy (64b) || expiration_timestamp (32b) || 0 (17b).
    packed_message1: felt,
}

// Serialize an L1 order to L1OrderMessageOutput.
//
// Hint argument:
// order - the L1 order to serialize.
func serialize_l1_limit_order(limit_order: ExchangeLimitOrder*) -> (
    l1_order_message: L1OrderMessageOutput*
) {
    alloc_locals;
    %{
        from common.objects.transaction.common_transaction import OrderL1
        assert isinstance(order, OrderL1)
    %}
    local l1_order_message: L1OrderMessageOutput;
    assert l1_order_message.eth_key = limit_order.base.public_key;
    // Counting the number of elements excluding eth_key and n_elms.
    l1_order_message.n_elms = L1OrderMessageOutput.SIZE - 2;

    let packed_message0 = limit_order.amount_sell;
    let packed_message0 = packed_message0 * AMOUNT_UPPER_BOUND + limit_order.amount_buy;
    let packed_message0 = packed_message0 * AMOUNT_UPPER_BOUND + limit_order.amount_fee;
    let packed_message0 = packed_message0 * NONCE_UPPER_BOUND + limit_order.base.nonce;
    assert l1_order_message.packed_message0 = packed_message0;

    let packed_message1 = 3;
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_fee;
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_sell;
    let packed_message1 = packed_message1 * VAULT_ID_UPPER_BOUND + limit_order.vault_buy;
    let packed_message1 = (
        packed_message1 * EXPIRATION_TIMESTAMP_UPPER_BOUND + limit_order.base.expiration_timestamp
    );
    let packed_message1 = packed_message1 * (2 ** 17);
    assert l1_order_message.packed_message1 = packed_message1;

    l1_order_message.token_sell = limit_order.asset_id_sell;
    l1_order_message.token_buy = limit_order.asset_id_buy;
    l1_order_message.token_fee = limit_order.asset_id_fee;

    // Return the address of the locally allocated l1_order_message.
    let (__fp__, _) = get_fp_and_pc();
    return (l1_order_message=&l1_order_message);
}
