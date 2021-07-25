from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.oracle.oracle_price import AssetOraclePrice
from services.perpetual.cairo.state.state import CarriedState, SharedState
from services.perpetual.cairo.transactions.transaction import Transactions

struct ProgramInput:
    member general_config : GeneralConfig*
    member prev_shared_state : SharedState*
    member new_shared_state : SharedState*
    member minimum_expiration_timestamp : felt
    member txs : Transactions*
    member n_signed_oracle_prices : felt
    member signed_min_oracle_prices : AssetOraclePrice*
    member signed_max_oracle_prices : AssetOraclePrice*
end
