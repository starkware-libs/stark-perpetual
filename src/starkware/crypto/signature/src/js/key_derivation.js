/////////////////////////////////////////////////////////////////////////////////
// Copyright 2019 StarkWare Industries Ltd.                                    //
//                                                                             //
// Licensed under the Apache License, Version 2.0 (the "License").             //
// You may not use this file except in compliance with the License.            //
// You may obtain a copy of the License at                                     //
//                                                                             //
// https://www.starkware.co/open-source-license/                               //
//                                                                             //
// Unless required by applicable law or agreed to in writing,                  //
// software distributed under the License is distributed on an "AS IS" BASIS,  //
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    //
// See the License for the specific language governing permissions             //
// and limitations under the License.                                          //
/////////////////////////////////////////////////////////////////////////////////

const { hdkey } = require('ethereumjs-wallet');
const bip39 = require('bip39');
const encUtils = require('enc-utils');
const BN = require('bn.js');
const hash = require('hash.js');
const { ec } = require('./signature.js');
const assert = require('assert');

const ETH_SIGNATURE_LENGTH = 130;
const STARK_PRIVATE_KEY_LENGTH = 63;

/*
 Returns an integer from a given section of bits out of a hex string.
 hex is the target hex string to slice.
 start represents the index of the first bit to cut from the hex string (binary) in LSB order.
 end represents the index of the last bit to cut from the hex string.
*/
function getIntFromBits(hex, start, end = undefined) {
    const bin = encUtils.hexToBinary(hex);
    const bits = bin.slice(start, end);
    const int = encUtils.binaryToNumber(bits);
    return int;
}

/*
 Returns true if the given string is a hex string of length hexLength, and false otherwise.
*/
function isHexOfLength(hex, hexLength) {
    const regex = new RegExp('^[0-9a-fA-F]{' + hexLength + '}$');
    return regex.test(hex);
}

/*
 Returns a private stark key based on a given Eth signature.
 The given signature should be a 130 character hex string produced by the user signing a
 predetermined message in order to guarantee getting the same private key each time it is invoked.
*/
function getPrivateKeyFromEthSignature(ethSignature) {
    const ethSignatureFixed = ethSignature.replace(/^0x/, '');
    assert(isHexOfLength(ethSignatureFixed, ETH_SIGNATURE_LENGTH));
    const r = ethSignatureFixed.substring(0, 64);
    return grindKey(r, ec.n);
}

/*
 Returns a public stark key given the private key.
 The private key should be a random hex string of length up to 63 characters.
*/
function privateToStarkKey(privateKey) {
    const privateKeyFixed = privateKey.replace(/^0x/, '');
    assert(privateKeyFixed.length <= STARK_PRIVATE_KEY_LENGTH);
    assert(isHexOfLength(privateKeyFixed, privateKeyFixed.length));
    const keyPair = ec.keyFromPrivate(privateKeyFixed, 'hex');
    return keyPair.getPublic().getX().toJSON();
}

/*
 Derives key-pair from given mnemonic string and path.
 mnemonic should be a sentence comprised of 12 words with single spaces between them.
 path is a formatted string describing the stark key path based on the layer, application and eth
 address.
*/
function getKeyPairFromPath(mnemonic, path) {
    const seed = bip39.mnemonicToSeedSync(mnemonic);
    const keySeed = hdkey
        .fromMasterSeed(seed, 'hex')
        .derivePath(path)
        .getWallet()
        .getPrivateKeyString();
    const starkEcOrder = ec.n;
    return ec.keyFromPrivate(grindKey(keySeed, starkEcOrder), 'hex');
}

/*
 Calculates the stark path based on the layer, application, eth address and a given index.
 layer is a string representing the operating layer (usually 'starkex').
 application is a string representing the relevant application (For a list of valid applications,
 refer to https://starkware.co/starkex/docs/requirementsApplicationParameters.html).
 ethereumAddress is a string representing the ethereum public key from which we derive the stark
 key.
 index represents an index of the possible associated wallets derived from the seed.
*/
function getAccountPath(layer, application, ethereumAddress, index) {
    const layerHash = hash
        .sha256()
        .update(layer)
        .digest('hex');
    const applicationHash = hash
        .sha256()
        .update(application)
        .digest('hex');
    const layerInt = getIntFromBits(layerHash, -31);
    const applicationInt = getIntFromBits(applicationHash, -31);
    // Draws the 31 LSBs of the eth address.
    const ethAddressInt1 = getIntFromBits(ethereumAddress, -31);
    // Draws the following 31 LSBs of the eth address.
    const ethAddressInt2 = getIntFromBits(ethereumAddress, -62, -31);
    return `m/2645'/${layerInt}'/${applicationInt}'/${ethAddressInt1}'/${ethAddressInt2}'/${index}`;
}

/*
 This function receives a key seed and produces an appropriate StarkEx key from a uniform
 distribution.
 Although it is possible to define a StarkEx key as a residue between the StarkEx EC order and a
 random 256bit digest value, the result would be a biased key. In order to prevent this bias, we
 deterministically search (by applying more hashes, AKA grinding) for a value lower than the largest
 256bit multiple of StarkEx EC order.
*/
function grindKey(keySeed, keyValLimit) {
    const sha256EcMaxDigest = new BN(
        '1 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000',
        16
    );
    const maxAllowedVal = sha256EcMaxDigest.sub(sha256EcMaxDigest.mod(keyValLimit));
    let i = 0;
    let key = hashKeyWithIndex(keySeed, i);
    i++;
    // Make sure the produced key is devided by the Stark EC order, and falls within the range
    // [0, maxAllowedVal).
    while (!(key.lt(maxAllowedVal))) {
        key = hashKeyWithIndex(keySeed.toString('hex'), i);
        i++;
    }
    return key.umod(keyValLimit).toString('hex');
}

function hashKeyWithIndex(key, index) {
    return new BN(
        hash
            .sha256()
            .update(
                encUtils.hexToBuffer(
                    encUtils.removeHexPrefix(key) +
                    encUtils.sanitizeBytes(encUtils.numberToHex(index), 2)
                )
            )
            .digest('hex'),
        16
    );
}

module.exports = {
    StarkExEc: ec.n,  // Data.
    getPrivateKeyFromEthSignature, privateToStarkKey, getKeyPairFromPath, getAccountPath, grindKey
    // Function.
};
