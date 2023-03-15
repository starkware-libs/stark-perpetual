from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.dex.general_config import GeneralConfig

// A representation of a DEX context struct.

struct DexContext {
    general_config: GeneralConfig,
    global_expiration_timestamp: felt,
}

// Returns a pointer to a new DexContext struct.
func make_dex_context(general_config: GeneralConfig, global_expiration_timestamp: felt) -> (
    addr: DexContext*
) {
    let (__fp__, _) = get_fp_and_pc();
    return (addr=cast(__fp__ - 2 - DexContext.SIZE, DexContext*));
}
