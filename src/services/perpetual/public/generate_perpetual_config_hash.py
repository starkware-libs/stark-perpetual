#!/usr/bin/env python3

###############################################################################
#                                                                             #
# Calculates dYdX general config and synthetic asset hash values.             #
#                                                                             #
###############################################################################

###############################################################################
# Copyright 2021 StarkWare Industries Ltd.                                    #
#                                                                             #
# Licensed under the Apache License, Version 2.0 (the "License").             #
# You may not use this file except in compliance with the License.            #
# You may obtain a copy of the License at                                     #
#                                                                             #
# https://www.starkware.co/open-source-license/                               #
#                                                                             #
# Unless required by applicable law or agreed to in writing,                  #
# software distributed under the License is distributed on an "AS IS" BASIS,  #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    #
# See the License for the specific language governing permissions             #
# and limitations under the License.                                          #
###############################################################################


import argparse
import sys

import yaml

from services.perpetual.public.definitions.constants import ASSET_ID_UPPER_BOUND
from starkware.crypto.signature.fast_pedersen_hash import pedersen_hash_func

CONFIG_FILE_NAME = 'production_general_config.yml'
HASH_BYTES = 32

ASSET_ID_BYTES = 15
assert 2 ** (ASSET_ID_BYTES * 8) == ASSET_ID_UPPER_BOUND


def str2int(val: str) -> int:
    """
    Converts a decimal or hex string into an int.
    Also accepts an int and returns it unchanged.
    """
    if type(val) is int:
        return int(val)
    if len(val) < 3:
        return int(val, 10)
    if val[:2] == '0x':
        return int(val, 16)
    return int(val, 10)


def bytes2str(val: bytes) -> str:
    """
    Converts a bytes into a hex string.
    """
    return f'0x{val.hex()}'


def pad_hex_string(val: str, bytes_len: int) -> str:
    """
    Pads a hex string with leading zeros to match a length of bytes_len.
    """
    assert val[:2] == '0x'
    val_nibbles_len = (len(val) - 2)
    assert val_nibbles_len <= 2 * bytes_len
    return f'0x{"0" * (2 * bytes_len - val_nibbles_len)}{val[2:]}'


def calculate_general_config_hash(config: dict) -> bytes:
    """
    Calculates the hash of the general config without the synthetic assets info.
    """
    assert 'max_funding_rate' in config
    max_funding_rate = config['max_funding_rate']

    assert 'collateral_asset_info' in config
    collateral_asset_info = config['collateral_asset_info']
    assert 'asset_id' in collateral_asset_info
    asset_id = collateral_asset_info['asset_id']
    assert 'resolution' in collateral_asset_info
    resolution = collateral_asset_info['resolution']

    assert 'fee_position_info' in config
    fee_position_info = config['fee_position_info']
    assert 'position_id' in fee_position_info
    position_id = fee_position_info['position_id']
    assert 'public_key' in fee_position_info
    public_key = fee_position_info['public_key']

    assert 'positions_tree_height' in config
    positions_tree_height = config['positions_tree_height']
    assert 'orders_tree_height' in config
    orders_tree_height = config['orders_tree_height']

    assert 'timestamp_validation_config' in config
    timestamp_validation_config = config['timestamp_validation_config']
    assert 'price_validity_period' in timestamp_validation_config
    price_validity_period = timestamp_validation_config['price_validity_period']
    assert 'funding_validity_period' in timestamp_validation_config
    funding_validity_period = timestamp_validation_config['funding_validity_period']

    field_values = [
        max_funding_rate, asset_id, resolution, position_id, public_key, positions_tree_height,
        orders_tree_height, price_validity_period, funding_validity_period,
    ]
    field_values.append(str(len(field_values)))

    hash_result = b'\x00' * HASH_BYTES
    for value in field_values:
        hash_result = pedersen_hash_func(
            hash_result, str2int(value).to_bytes(HASH_BYTES, 'big'))
    return hash_result


def calculate_asset_hash(config: dict, asset_id: str) -> bytes:
    """
    Calculates the hash of a synthetic asset definition.
    """
    assert 'synthetic_assets_info' in config
    synthetic_assets_info = config['synthetic_assets_info']
    assert asset_id in synthetic_assets_info
    synthetic_asset_info = synthetic_assets_info[asset_id]

    assert 'resolution' in synthetic_asset_info
    resolution = synthetic_asset_info['resolution']

    assert 'risk_factor' in synthetic_asset_info
    risk_factor = synthetic_asset_info['risk_factor']

    assert 'oracle_price_signed_asset_ids' in synthetic_asset_info
    oracle_price_signed_asset_ids = synthetic_asset_info['oracle_price_signed_asset_ids']

    assert 'oracle_price_quorum' in synthetic_asset_info
    oracle_price_quorum = synthetic_asset_info['oracle_price_quorum']

    assert 'oracle_price_signers' in synthetic_asset_info
    oracle_price_signers = synthetic_asset_info['oracle_price_signers']

    field_values = [asset_id, resolution, risk_factor]
    field_values += oracle_price_signed_asset_ids
    field_values.append(oracle_price_quorum)
    field_values += oracle_price_signers
    field_values.append(str(len(field_values)))

    hash_result = b'\x00' * HASH_BYTES
    for value in field_values:
        hash_result = pedersen_hash_func(hash_result, str2int(value).to_bytes(HASH_BYTES, 'big'))
    return hash_result


def generate_config_hashes(config: dict) -> str:
    output = ''
    config_hash_bytes = calculate_general_config_hash(config)
    config_hash_hex = bytes2str(config_hash_bytes)
    output += f'Global config hash: {config_hash_hex}\n'
    for asset_id in config['synthetic_assets_info'].keys():
        config_hash_bytes = calculate_asset_hash(config=config, asset_id=asset_id)
        config_hash_hex = bytes2str(config_hash_bytes)
        asset_id_padded = pad_hex_string(asset_id, ASSET_ID_BYTES)
        output += f'asset_id: {asset_id_padded}, config_hash: {config_hash_hex}\n'
    output += '\n'
    return output


def parse_cmdline():
    parser = argparse.ArgumentParser(
        description='Calculates dYdX general config and synthetic asset hash values.')
    parser.add_argument(
        '--general_config_file_name', type=str, default=CONFIG_FILE_NAME,
        help='Input YAML file containing the general configuration.')

    return parser.parse_args()


def main():
    args = parse_cmdline()
    with open(args.general_config_file_name, 'r') as f:
        config = yaml.load(f, Loader=yaml.FullLoader)
    output = generate_config_hashes(config)
    print(output)


if __name__ == '__main__':
    sys.exit(main())
