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

const starkwareCrypto = require('starkware_crypto');
const { assertInRange } = require('starkware_crypto');
const BN = require('bn.js');


// 2^64.
const Bn64 = new BN('10000000000000000', 16);

// 2^32.
const Bn32 = new BN('100000000', 16);

// 2^128.
const Bn128 = new BN('100000000000000000000000000000000', 16);

// 2^250.
const Bn250 = new BN('400000000000000000000000000000000000000000000000000000000000000', 16);

// 2^251.
const Bn251 = new BN('800000000000000000000000000000000000000000000000000000000000000', 16);

const zeroBn = new BN('0', 16);

const LimitOrderWithFees = '3';
const Transfer = '4';
const ConditionalTransfer = '5';
const Withdrawal = '6';


function getPerpetualWithdrawalMessage(
        assetIdCollateral,
        positionId,
        nonce,
        expirationTimestamp,
        amount,
        hash = starkwareCrypto.pedersen
) {
    const assetIdCollateralBn = new BN(assetIdCollateral, 10);
    const positionIdBn = new BN(positionId, 10);
    const nonceBn = new BN(nonce, 10);
    const amountBn = new BN(amount, 10);
    const expirationTimestampBn = new BN(expirationTimestamp, 10);

    // 0 <= assetIdCollateral < 2^250
    assertInRange(assetIdCollateralBn, zeroBn, Bn250, 'assetIdCollateral');
    // 0 <= nonce < 2^32
    assertInRange(nonceBn, zeroBn, Bn32, 'nonce');
    // 0 <= positionId < 2^64
    assertInRange(positionIdBn, zeroBn, Bn64, 'positionId');
    // 0 <= expirationTimestamp < 2^32
    assertInRange(expirationTimestampBn, zeroBn, Bn32, 'expirationTimestamp');
    // 0 <= amount < 2^64
    assertInRange(amountBn, zeroBn, Bn64, 'amount');

    let packedMsg = new BN(Withdrawal, 10);
    packedMsg = packedMsg.ushln(64).add(positionIdBn);
    packedMsg = packedMsg.ushln(32).add(nonceBn);
    packedMsg = packedMsg.ushln(64).add(amountBn);
    packedMsg = packedMsg.ushln(32).add(expirationTimestampBn);
    packedMsg = packedMsg.ushln(49);

    return hash([assetIdCollateral, packedMsg]);
}

function perpetualTransfersRangeChecks(
        assetIdBn,
        assetIdFeeBn,
        receiverPublicKeyBn,
        senderPositionIdBn,
        receiverPositionIdBn,
        srcFeePositionIdBn,
        nonceBn,
        amountBn,
        maxAmountFeeBn,
        expirationTimestampBn,
        conditionBn = new BN(0, 10)
) {
    assertInRange(assetIdBn, zeroBn, Bn250, 'assetId'); // 0 <= assetId < 2^250
    // 0 <= assetIdFee < 2^250
    assertInRange(assetIdFeeBn, zeroBn, Bn250, 'assetIdFee');
    // 0 <= receiverPublicKey < 2^251
    assertInRange(receiverPublicKeyBn, zeroBn, Bn251, 'receiverPublicKey');
    // 0 <= senderPositionId < 2^64
    assertInRange(senderPositionIdBn, zeroBn, Bn64, 'senderPositionId');
    // 0 <= receiverPositionId < 2^64
    assertInRange(receiverPositionIdBn, zeroBn, Bn64, 'receiverPositionId');
    // 0 <= srcFeePositionId < 2^64
    assertInRange(srcFeePositionIdBn, zeroBn, Bn64, 'srcFeePositionId');
    assertInRange(nonceBn, zeroBn, Bn32, 'nonce'); // 0 <= nonce < 2^32
    assertInRange(amountBn, zeroBn, Bn64, 'amount'); // 0 <= amount < 2^64
    // 0 <= maxAmountFee < 2^64
    assertInRange(maxAmountFeeBn, zeroBn, Bn64, 'maxAmountFee');
    // 0 <= expirationTimestamp < 2^32
    assertInRange(expirationTimestampBn, zeroBn, Bn32, 'expirationTimestamp');
    // 0 <= condition < 2^251
    assertInRange(conditionBn, zeroBn, Bn251, 'condition');
}

function getPerpetualTransferMessage(
        assetId,
        assetIdFee,
        receiverPublicKey,
        senderPositionId,
        receiverPositionId,
        srcFeePositionId,
        nonce,
        amount,
        maxAmountFee,
        expirationTimestamp,
        hash = starkwareCrypto.pedersen
) {
    const assetIdBn = new BN(assetId, 10);
    const assetIdFeeBn = new BN(assetIdFee, 10);
    const receiverPublicKeyBn = new BN(receiverPublicKey, 10);
    const senderPositionIdBn = new BN(senderPositionId, 10);
    const receiverPositionIdBn = new BN(receiverPositionId, 10);
    const srcFeePositionIdBn = new BN(srcFeePositionId, 10);
    const nonceBn = new BN(nonce, 10);
    const amountBn = new BN(amount, 10);
    const maxAmountFeeBn = new BN(maxAmountFee, 10);
    const expirationTimestampBn = new BN(expirationTimestamp, 10);

    perpetualTransfersRangeChecks(
        assetIdBn,
        assetIdFeeBn,
        receiverPublicKeyBn,
        senderPositionIdBn,
        receiverPositionIdBn,
        srcFeePositionIdBn,
        nonceBn,
        amountBn,
        maxAmountFeeBn,
        expirationTimestampBn
    );

    let msg = hash([assetIdBn, assetIdFeeBn]);
    msg = hash([msg, receiverPublicKeyBn]);
    let packedMsg0 = new BN(senderPositionIdBn, 10);
    packedMsg0 = packedMsg0.ushln(64).add(receiverPositionIdBn);
    packedMsg0 = packedMsg0.ushln(64).add(srcFeePositionIdBn);
    packedMsg0 = packedMsg0.ushln(32).add(nonceBn);
    msg = hash([msg, packedMsg0]);
    let packedMsg1 = new BN(Transfer, 10);
    packedMsg1 = packedMsg1.ushln(64).add(amountBn);
    packedMsg1 = packedMsg1.ushln(64).add(maxAmountFeeBn);
    packedMsg1 = packedMsg1.ushln(32).add(expirationTimestampBn);
    packedMsg1 = packedMsg1.ushln(81);  // Padding.
    return hash([msg, packedMsg1]);
}

function getPerpetualConditionalTransferMessage(
        assetId,
        assetIdFee,
        receiverPublicKey,
        condition,
        senderPositionId,
        receiverPositionId,
        srcFeePositionId,
        nonce,
        amount,
        maxAmountFee,
        expirationTimestamp,
        hash = starkwareCrypto.pedersen
) {
    const assetIdBn = new BN(assetId, 10);
    const assetIdFeeBn = new BN(assetIdFee, 10);
    const receiverPublicKeyBn = new BN(receiverPublicKey, 10);
    const conditionBn = new BN(condition, 10);
    const senderPositionIdBn = new BN(senderPositionId, 10);
    const receiverPositionIdBn = new BN(receiverPositionId, 10);
    const srcFeePositionIdBn = new BN(srcFeePositionId, 10);
    const nonceBn = new BN(nonce, 10);
    const amountBn = new BN(amount, 10);
    const maxAmountFeeBn = new BN(maxAmountFee, 10);
    const expirationTimestampBn = new BN(expirationTimestamp, 10);

    perpetualTransfersRangeChecks(
        assetIdBn,
        assetIdFeeBn,
        receiverPublicKeyBn,
        senderPositionIdBn,
        receiverPositionIdBn,
        srcFeePositionIdBn,
        nonceBn,
        amountBn,
        maxAmountFeeBn,
        expirationTimestampBn,
        conditionBn
    );

    let msg = hash([assetIdBn, assetIdFeeBn]);
    msg = hash([msg, receiverPublicKeyBn]);
    msg = hash([msg, conditionBn]);
    let packedMsg0 = new BN(senderPositionIdBn, 10);
    packedMsg0 = packedMsg0.ushln(64).add(receiverPositionIdBn);
    packedMsg0 = packedMsg0.ushln(64).add(srcFeePositionIdBn);
    packedMsg0 = packedMsg0.ushln(32).add(nonceBn);
    msg = hash([msg, packedMsg0]);
    let packedMsg1 = new BN(ConditionalTransfer, 10);
    packedMsg1 = packedMsg1.ushln(64).add(amountBn);
    packedMsg1 = packedMsg1.ushln(64).add(maxAmountFeeBn);
    packedMsg1 = packedMsg1.ushln(32).add(expirationTimestampBn);
    packedMsg1 = packedMsg1.ushln(81);  // Padding.
    return hash([msg, packedMsg1]);
}

function getPerpetualLimitOrderMessage(
        assetIdSynthetic,
        assetIdCollateral,
        isBuyingSynthetic,
        assetIdFee,
        amountSynthetic,
        amountCollateral,
        maxAmountFee,
        nonce,
        positionId,
        expirationTimestamp,
        hash = starkwareCrypto.pedersen
) {
    const assetIdSyntheticBn = new BN(assetIdSynthetic, 10);
    const assetIdCollateralBn = new BN(assetIdCollateral, 10);
    const assetIdFeeBn = new BN(assetIdFee, 10);
    const maxAmountFeeBn = new BN(maxAmountFee, 10);
    const nonceBn = new BN(nonce, 10);
    const positionIdBn = new BN(positionId, 10);
    const expirationTimestampBn = new BN(expirationTimestamp, 10);

    let assetIdSell = 0, assetIdBuy = 0, amountSell = 0, amountBuy = 0;
    if (isBuyingSynthetic) {
        assetIdSell = new BN(assetIdCollateral, 10);
        assetIdBuy = new BN(assetIdSynthetic, 10);
        amountSell = new BN(amountCollateral, 10);
        amountBuy = new BN(amountSynthetic, 10);
    } else {
        assetIdSell = new BN(assetIdSynthetic, 10);
        assetIdBuy = new BN(assetIdCollateral, 10);
        amountSell = new BN(amountSynthetic, 10);
        amountBuy = new BN(amountCollateral, 10);
    }
    // 0 <= assetIdSynthetic < 2^128
    assertInRange(assetIdSyntheticBn, zeroBn, Bn128, 'assetIdSynthetic');
    // 0 <= assetIdCollateral < 2^250
    assertInRange(assetIdCollateralBn, zeroBn, Bn250, 'assetIdCollateral');
    // 0 <= assetIdFee < 2^250
    assertInRange(assetIdFeeBn, zeroBn, Bn250, 'assetIdFee');
    // 0 <= amountSell < 2^64
    assertInRange(amountSell, zeroBn, Bn64, 'amountSell');
    // 0 <= amountBuy < 2^64
    assertInRange(amountBuy, zeroBn, Bn64, 'amountBuy');
    // 0 <= maxAmountFee < 2^64
    assertInRange(maxAmountFeeBn, zeroBn, Bn64, 'maxAmountFee');
    // 0 <= nonce < 2^32
    assertInRange(nonceBn, zeroBn, Bn32, 'nonce');
    // 0 <= positionId < 2^64
    assertInRange(positionIdBn, zeroBn, Bn64, 'positionId');
    // 0 <= expirationTimestamp < 2^32
    assertInRange(expirationTimestampBn, zeroBn, Bn32, 'expirationTimestamp');

    let msg = hash([assetIdSell, assetIdBuy]);
    msg = hash([msg, assetIdFeeBn]);
    let packedMsg0 = new BN(amountSell, 10);
    packedMsg0 = packedMsg0.ushln(64).add(amountBuy);
    packedMsg0 = packedMsg0.ushln(64).add(maxAmountFeeBn);
    packedMsg0 = packedMsg0.ushln(32).add(nonceBn);
    msg = hash([msg, packedMsg0]);
    let packedMsg1 = new BN(LimitOrderWithFees, 10);
    packedMsg1 = packedMsg1.ushln(64).add(positionIdBn);
    packedMsg1 = packedMsg1.ushln(64).add(positionIdBn);
    packedMsg1 = packedMsg1.ushln(64).add(positionIdBn);
    packedMsg1 = packedMsg1.ushln(32).add(expirationTimestampBn);
    packedMsg1 = packedMsg1.ushln(17);
    return hash([msg, packedMsg1]);
}

module.exports = {
    getPerpetualWithdrawalMessage, getPerpetualTransferMessage, getPerpetualLimitOrderMessage,
    getPerpetualConditionalTransferMessage  // Function.
};

