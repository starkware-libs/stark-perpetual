# StarkEx Perpetual Resources

## Overview
​
This repository contains the Cairo code and a collection of tools used by StarkEx Perpetual,
StarkWare's scalability solution for derivatives trading.
If you are not familiar with StarkEx, you can read more about it [here](https://docs.starkware.co/starkex/).

Note: The Cairo code that proves spot trading, can be found [in another repo](https://github.com/starkware-libs/starkex-for-spot-trading).

If you are not familiar with the Cairo language, you can find more details about it [here](https://www.cairo-lang.org/).

The Cairo code is published to allow a permissionless audit of StarkEx business logic,
as enforced by the StarkEx smart-contract


## Repository Contents
​
**src/starkware/cairo/dex**, **src/services/exchange/cairo**, **src/services/perpetual/cairo**
The full Cairo program that StarkEx Perpetual executes.
It includes a Python file, *generate_program_hash_test.py*, that calculates the hash of the
Cairo code and compares it to the pre-calculated value found at *program_hash.json*
​

**src/starkware/crypto/starkware/crypto/signature**, **src/services/perpetual/public**
The Python implementation of the cryptographic primitives used by StarkEx.
These implementations, or equivalent implementations in other languages such as JS, are used by StarkEx user's wallets in order to generate and sign on orders.


### Usage:
​
1. Run the repo's tests by running the command:\
    `docker build .`

2. Verify that the same hash is used by StarkEx on Mainnet by running the script
*src/services/extract_cairo_hash.py* in the following way:\
    `./src/services/exchange/extract_cairo_hash.py --main_address <checksummed_main_address> --node_endpoint <your_node_endpoint> `
​

You can find the relevant addresses and current versions for the
different StarkEx deployments [here](https://docs.starkware.co/starkex/deployments-addresses.html).

When comparing the hash, please make sure you checkout the tag that corresponds to the
deployed version from this repo.
