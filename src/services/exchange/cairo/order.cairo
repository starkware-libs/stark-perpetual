# Common struct for user signed orders (limit_order, withdrawal, transfer, etc.).
struct OrderBase:
    member nonce : felt
    member public_key : felt
    member expiration_timestamp : felt
    member signature_r : felt
    member signature_s : felt
end
