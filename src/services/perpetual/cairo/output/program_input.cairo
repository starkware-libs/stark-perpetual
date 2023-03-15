from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.oracle.oracle_price import AssetOraclePrice
from services.perpetual.cairo.state.state import SharedState
from services.perpetual.cairo.transactions.transaction import Transactions

struct ProgramInput {
    general_config: GeneralConfig*,
    prev_shared_state: SharedState*,
    new_shared_state: SharedState*,
    minimum_expiration_timestamp: felt,
    txs: Transactions*,
    n_signed_oracle_prices: felt,
    signed_min_oracle_prices: AssetOraclePrice*,
    signed_max_oracle_prices: AssetOraclePrice*,
}
