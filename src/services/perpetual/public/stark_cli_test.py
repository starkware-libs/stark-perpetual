###############################################################################
# Copyright 2019 StarkWare Industries Ltd.                                    #
#                                                                             #
# Licensed under the Apache License, Version 2.0 (the 'License').             #
# You may not use this file except in compliance with the License.            #
# You may obtain a copy of the License at                                     #
#                                                                             #
# https://www.starkware.co/open-source-license/                               #
#                                                                             #
# Unless required by applicable law or agreed to in writing,                  #
# software distributed under the License is distributed on an 'AS IS' BASIS,  #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    #
# See the License for the specific language governing permissions             #
# and limitations under the License.                                          #
###############################################################################
import json
import os
import subprocess
import sys

import pytest

from starkware.crypto.signature.signature import pedersen_hash, sign


@pytest.fixture(scope="module")
def data_file() -> dict:
    json_file = os.path.join(os.path.dirname(__file__), "signature_test_data.json")
    return json.load(open(json_file))


@pytest.fixture(scope="module")
def key_file() -> dict:
    json_file = os.path.join(os.path.dirname(__file__), "keys_precomputed.json")
    return json.load(open(json_file))


@pytest.fixture(scope="module")
def cli_file() -> str:
    return os.path.join(os.path.dirname(__file__), "stark_cli.py")


def test_cli_hash_args(data_file, cli_file):
    command = " ".join(
        [
            sys.executable,
            cli_file,
            "--method",
            "hash",
            "--oracle",
            "4d616b6572",
            "--asset",
            "42544355534400000000000000000000",
            "--price",
            "000000000000000000000000000000000000000000000000ac9f3163ad52b000",
            "--time",
            "000000000000000000000000000000000000000000000000000000005f590c1e",
        ]
    )
    cli_run = subprocess.run(command, shell=True, capture_output=True)

    assert cli_run.stderr == b""
    assert (
        bytes(
            hex(
                pedersen_hash(
                    0x425443555344000000000000000000004D616B6572, 0xAC9F3163AD52B0005F590C1E
                )
            )[2:]
            + "\n",
            "utf-8",
        )
        == cli_run.stdout
    )


illegal_tests_list = [
    (
        "14d616b6572",
        "42544355534400000000000000000000",
        "000000000000000000000000000000000000000000000000ac9f3163ad52b000",
        "000000000000000000000000000000000000000000000000000000005f590c1e",
    ),
    (
        "4d616b6572",
        "42544355534400000000000000000000",
        "000000000000000000000000000000000000000000000000ac9f3163ad52b000",
        "000000000000000000000000000000000000000000000000000000015f590c1e",
    ),
    (
        "4d616b6572",
        "4254435553440000000000000000000000",
        "000000000000000000000000000000000000000000000000ac9f3163ad52b000",
        "000000000000000000000000000000000000000000000000000000005f590c1e",
    ),
    (
        "4d616b6572",
        "42544355534400000000000000000000",
        "000010000000000000000000000000000000000000000000ac9f3163ad52b000",
        "000000000000000000000000000000000000000000000000000000005f590c1e",
    ),
]


@pytest.mark.parametrize("oracle, asset, price, time", illegal_tests_list)
def test_cli_hash_illegal_params(data_file, cli_file, oracle, asset, price, time):
    command = " ".join(
        [
            sys.executable,
            cli_file,
            "--method",
            "hash",
            "--oracle",
            oracle,
            "--asset",
            asset,
            "--price",
            price,
            "--time",
            time,
        ]
    )
    cli_run = subprocess.run(command, shell=True, capture_output=True)

    assert not (b"" == cli_run.stderr)


def test_cli_sign(data_file, cli_file):
    private_key = data_file["meta_data"]["party_a_order"]["private_key"]
    msg_hash = data_file["meta_data"]["party_a_order"]["message_hash"]
    r, s = sign(int(msg_hash, 16), int(private_key, 16))

    command = " ".join(
        [sys.executable, cli_file, "--method", "sign", "--key", private_key, "--data", msg_hash]
    )
    cli_run = subprocess.run(command, shell=True, capture_output=True)
    assert b"" == cli_run.stderr
    assert bytes(" ".join([hex(r), hex(s)]) + "\n", "utf-8") == cli_run.stdout


def test_public_key(key_file, cli_file):
    private, public = list(key_file.items())[0]
    command = " ".join([sys.executable, cli_file, "--method", "get_public", "--key", private])
    cli_run = subprocess.run(command, shell=True, capture_output=True)
    assert b"" == cli_run.stderr
    assert bytes(public + "\n", "utf-8") == cli_run.stdout
