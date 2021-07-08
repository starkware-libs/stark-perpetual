###############################################################################
# Copyright 2019 StarkWare Industries Ltd.                                    #
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

import sys
from argparse import ArgumentParser, RawTextHelpFormatter

from services.perpetual.public.perpetual_messages import get_price_msg
from starkware.crypto.signature.signature import FIELD_PRIME, private_to_stark_key, sign


class HexedBoundedParam():
    def __init__(self, bound):
        self.bound = bound

    def __call__(self, input_element):
        num = int(input_element, 16)
        assert num < self.bound
        return num


def sign_cli(key, data):
    r, s = sign(data, key)
    return ' '.join([hex(r), hex(s)])


def public_cli(key):
    return hex(private_to_stark_key(key))


def hash_price(oracle_name, asset_pair, price, timestamp):
    return hex(get_price_msg(oracle_name, asset_pair, timestamp, price))[2:]


def main():
    description = """
    #####################################################################################
    # Starkware hash&sign cli, provides hash and sign functions.                        #
    #                                                                                   #
    # Sign: gets as input:                                                              #
    #   private key:  (a number which is less than FIELD_PRIME, roughly 2**251)         #
    #   data to sign: (another number from the same range)                              #
    # and outputs:                                                                      #
    #   Stark signature with the key on the data                                        #
    #                                                                                   #
    # Hash: gets as input:                                                              #
    #   oracle: a 40-bit number, describes the oracle (e.g., hex encoding of "Maker")   #
    #   price: a 120-bit number                                                         #
    #   asset: a 128-bit number                                                         #
    #   timestamp: a 32 bit number, represents seconds since Unix epoch                 #
    # Outputs a number which is less than FIELD_PRIME, which can be used as data        #
    # to sign on in the sign method. This number is obtained by applying pedersen       #
    # on the following two numbers:                                                     #
    #                                                                                   #
    # first number:                                                                     #
    # --------------------------------------------------------------------------------- #
    # | 0 (84 bits)       | asset_name (128 bits)         |   oracle_name (40 bits)   | #
    # --------------------------------------------------------------------------------- #
    #                                                                                   #
    # second number:                                                                    #
    # --------------------------------------------------------------------------------- #
    # | 0 (100 bits)         | price (120 bits)             |   timestamp (32 bits)   | #
    # --------------------------------------------------------------------------------- #
    #                                                                                   #
    #####################################################################################
    """

    def hash_main(args, unknown):
        parser = ArgumentParser()
        parser.add_argument(
            '-a', '--asset', required=True, dest='asset',
            help='The asset pair', type=HexedBoundedParam(2**128))
        parser.add_argument(
            '-o', '--oracle', required=True, dest='oracle',
            help='The signing oracle', type=HexedBoundedParam(2**40))
        parser.add_argument(
            '-p', '--price', required=True, dest='price',
            help='The asset price', type=HexedBoundedParam(2**120))
        parser.add_argument(
            '-t', '--time', required=True, dest='time',
            help='The asset time', type=HexedBoundedParam(2**32))

        parser.parse_args(unknown, namespace=args)

        return hash_price(args.oracle, args.asset, args.price, args.time)

    def sign_main(args, unknown):
        parser = ArgumentParser()
        parser.add_argument(
            '-k', '--key', required=True, dest='key',
            help='The private key (hex string)', type=HexedBoundedParam(FIELD_PRIME))

        parser.add_argument(
            '-d', '--data', required=True, dest='data',
            help='The data to sign', type=HexedBoundedParam(FIELD_PRIME))

        parser.parse_args(unknown, namespace=args)
        return sign_cli(args.key, args.data)

    def public_main(args, unknown):
        parser = ArgumentParser()
        parser.add_argument(
            '-k', '--key', required=True, dest='key',
            help='The private key (hex string)', type=HexedBoundedParam(FIELD_PRIME))

        parser.parse_args(unknown, namespace=args)
        return public_cli(args.key)

    subparsers = {
        'hash': hash_main,
        'sign': sign_main,
        'get_public': public_main,
    }

    parser = ArgumentParser(description=description, formatter_class=RawTextHelpFormatter)
    parser.add_argument(
        '-m', '--method', required=True, dest='method',
        help='The required operation - hash or sign', choices=subparsers.keys())

    args, unknown = parser.parse_known_args()
    try:
        result = subparsers[args.method](args, unknown)
        print(result)
        return 0
    except Exception:
        print('Got an error while processing "%s":' % name, file=sys.stderr)
        traceback.print_exc()
        print(file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
