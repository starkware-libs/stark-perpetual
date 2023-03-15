#!/usr/bin/env python3

import argparse

from web3 import HTTPProvider, Web3

ADAPTER_ABI = [
    {
        "inputs": [],
        "name": "programHash",
        "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
        "stateMutability": "view",
        "type": "function",
    }
]

STARKEX_ABI = [
    {
        "inputs": [],
        "name": "getRegisteredVerifiers",
        "outputs": [{"internalType": "address[]", "name": "_verifers", "type": "address[]"}],
        "stateMutability": "view",
        "type": "function",
    }
]


def parse_cmdline():
    parser = argparse.ArgumentParser(
        description="Demonstrate extraction starkex cairo program hash"
    )
    parser.add_argument("--node_endpoint", type=str)
    parser.add_argument("--main_address", type=str)
    return parser.parse_args()


def main():
    args = parse_cmdline()
    w3 = Web3(HTTPProvider(args.node_endpoint))
    assert w3.isConnected()

    starkex = w3.eth.contract(address=args.main_address, abi=STARKEX_ABI)
    adapter_address = starkex.functions.getRegisteredVerifiers().call()[0]
    adapter = w3.eth.contract(address=adapter_address, abi=ADAPTER_ABI)

    program_hash = adapter.functions.programHash().call()
    print(
        f"Cairo program hash for StarkEx on address {args.main_address}\n"
        f"is {program_hash} (0x{program_hash:x})"
    )


if __name__ == "__main__":
    main()
