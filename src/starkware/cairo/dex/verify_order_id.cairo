from starkware.cairo.common.math import assert_lt_felt
from starkware.cairo.dex.dex_constants import ORDER_ID_BOUND

// Verifies that the given order_id complies with the order data, encoded in the message_hash.
// The order ID should be equal to the message hash, which must be at most 2**251 (the order ID
// bound).
func verify_order_id{range_check_ptr}(message_hash: felt, order_id: felt) {
    assert_lt_felt(order_id, ORDER_ID_BOUND);
    assert message_hash = order_id;
    return ();
}
