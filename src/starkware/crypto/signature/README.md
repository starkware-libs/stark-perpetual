# Introduction

This JS library implements an ECDSA signature SDK, necessary for most StarkWare products such as
StarkEx.
It consists of the following modules:

1. ``key_derivation.js`` -
    - Generating random private STARK keys or deriving them from an Ethereum-signature.
    - Deriving a public STARK key from the private STARK key.
2. ``signature.js`` -
    - Generating StarkEx-related transaction message hashes.
    - Signing messages and verifying signatures using STARK keys.
3. ``asset.js`` -
    - Getting the correct asset IDs (based on the desired type and quantum) for use in L2.


# Documentation

1. ``key_derivation.js`` -
    - Nowadays the vast majority of StarkEx systems don't require strict user registration
    flows, in the interest of saving the gas costs for registration txs on L1.
    - Instead, the users are free to generate their own random private STARK key (a 63-bit
    integer) from which a public STARK key can be derived and used for L2 transactions.
    - Common practice for apps that want to allow users to apply their Ethereum keys for L2
    transactions (essentially abstracting the usage of STARK keys) is to have the user
    sign some predetermined message with their Ethereum key (e.g. - "Hello World!") and then
    deriving a private STARK key from the Ethereum signature using the function
    ``getPrivateKeyFromEthSignature`` which can be found under ``key_derivation.js``
    - For more information refer to the following documentation (depending on the kind of
    StarkEx system you are integrating with):
        - Perpetual Trading: https://docs.starkware.co/starkex-v4/starkex-deep-dive/smart-contracts-1/register/for-perpetual-trading/perpetual-trading-v2.0.
        - Spot Trading: https://docs.starkware.co/starkex-v4/starkex-deep-dive/smart-contracts-1/register/for-spot-trading.
2. ``signature.js`` -
    - For detailed information on the structure of StarkEx messages and how to sign them,
    refer to the StarkEx documentation (depending on the kind of StarkEx system you are
    integrating with):
        - Perpetual Trading: https://docs.starkware.co/starkex-v4/starkex-deep-dive/message-encodings/in-perpetual.
        - Spot Trading: https://docs.starkware.co/starkex-v4/starkex-deep-dive/message-encodings/signatures.
    * NOTE - Some of the message types that can be generated in this library are deprecated
    from StarkEx V4.5 onwards, consult with the documentation to see which message type
    is right for the system you are integrating with.
3. ``asset.js`` -
    - For detailed information on the process of calculating and registering asset IDs to
    the StarkEx system refer to the StarkEx documentation: https://docs.starkware.co/starkex-v4/starkex-deep-dive/starkex-specific-concepts.

For common usage examples of the functions provided in this repo you may refer to
``signature_example.js`` (also provided in this module).

# Installation instructions

We use yarn as the package manager for this project. For more info visit https://yarnpkg.com/.

To install simply run:

```bash
> yarn install
```

# Testing

This repo comes with a comprehensive test suite for every module. These tests can be referred to for
common usage examples of the functions provided in this repo, and can be run using:

```bash
> yarn test
```

To run the example code provided under ``signature_example.js``:

```bash
> node signature_example.js
```

You may also use ``nodejs`` to play around with the functions under this module.

## Building using the dockerfile

The root directory holds a dedicated Dockerfile, which automatically builds the package and runs
the unit tests on a simulated Ubuntu 18.04 environment.
You should have docker installed (see https://docs.docker.com/get-docker/).

Build the docker image:

```bash
> docker build --tag starkex-signatures .
```

If everything works, you should see

```bash
Successfully tagged starkex-signatures:latest
```

