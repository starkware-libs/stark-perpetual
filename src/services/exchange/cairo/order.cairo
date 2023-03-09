// Common struct for user signed orders (limit_order, withdrawal, transfer, etc.).
struct OrderBase {
    nonce: felt,
    public_key: felt,
    expiration_timestamp: felt,
    signature_r: felt,
    signature_s: felt,
}
