import json
import os

from starkware.cairo.bootloader.hash_program import compute_program_hash_chain
from starkware.cairo.lang.compiler.program import Program
from starkware.python.utils import get_source_dir_path

PROGRAM_PATH = os.path.join(os.path.dirname(__file__), 'perpetual_cairo_compiled.json')
HASH_PATH = get_source_dir_path('src/services/perpetual/cairo/program_hash.json')


def run_generate_hash_test(fix: bool):
    compiled_program = Program.Schema().load(json.load(open(PROGRAM_PATH)))
    program_hash = compute_program_hash_chain(compiled_program)

    if fix:
        json.dump(obj={'program_hash': program_hash}, fp=open(HASH_PATH, 'w'))
    else:
        expected_hash = json.load(open(HASH_PATH))['program_hash']
        assert expected_hash == program_hash, \
            'Wrong program hash in program_hash.json. ' + \
            'Please run generate_perpetual_cairo_program_hash.'


def test_perpetual_program_hash():
    run_generate_hash_test(fix=False)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(
        description='Create or test the perpetual program hash.')
    parser.add_argument(
        '--fix', action='store_true', help='Fix the value of the program hash.')

    args = parser.parse_args()
    run_generate_hash_test(fix=args.fix)
