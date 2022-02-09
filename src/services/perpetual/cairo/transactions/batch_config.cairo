from services.perpetual.cairo.definitions.general_config import GeneralConfig
from services.perpetual.cairo.definitions.objects import OraclePrice
from starkware.cairo.common.registers import get_fp_and_pc

struct BatchConfig:
    member general_config : GeneralConfig*
    member signed_min_oracle_prices : OraclePrice*
    member signed_max_oracle_prices : OraclePrice*
    member n_oracle_prices : felt
    member min_expiration_timestamp : felt
end

func batch_config_new(
        general_config : GeneralConfig*, signed_min_oracle_prices : OraclePrice*,
        signed_max_oracle_prices : OraclePrice*, n_oracle_prices, min_expiration_timestamp) -> (
        batch_config : BatchConfig*):
    let (fp_val, pc_val) = get_fp_and_pc()
    # We refer to the arguments of this function as a BatchConfig object
    # (fp_val - 2 points to the end of the function arguments in the stack).
    return (batch_config=cast(fp_val - 2 - BatchConfig.SIZE, BatchConfig*))
end
