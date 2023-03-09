import os

from starkware.cairo.bootloaders.program_hash_test_utils import (
    program_hash_test_main,
    run_generate_hash_test,
)
from starkware.python.utils import get_source_dir_path

CURRENT_DIR = os.path.dirname(__file__)
PROGRAM_PATH = os.path.join(CURRENT_DIR, "cairo_dex_compiled.json")
HASH_RELATIVE_SRC_PATH = "src/starkware/cairo/dex/program_hash.json"
COMMAND = "generate_cairo_dex_program_hash"


def test_dex_program_hash():
    run_generate_hash_test(
        fix=False,
        program_path=PROGRAM_PATH,
        hash_path=os.path.join(CURRENT_DIR, os.path.basename(HASH_RELATIVE_SRC_PATH)),
        command=COMMAND,
    )


if __name__ == "__main__":
    program_hash_test_main(
        program_path=PROGRAM_PATH,
        # This call assumes that we are running an executable and not a test. In test mode,
        # get_source_dir_path will fail.
        hash_path=os.path.join(get_source_dir_path(), get_source_dir_path(HASH_RELATIVE_SRC_PATH)),
        command=COMMAND,
    )
