/* eslint-disable no-unused-expressions */
const chai = require('chai');
const {
    getPerpetualLimitOrderMessage,
    getPerpetualConditionalTransferMessage,
    getPerpetualTransferMessage,
    getPerpetualWithdrawalMessage
} = require('.././perpetual_messages.js');
const { expect } = chai;

describe('Limit order message generation', () => {
    it('should hash message correctly', () => {
        const precomputedMessageHashes = require(
            '../../perpetual_messages_precomputed.json'
        );
        const precomputedLimitOrderHashes = precomputedMessageHashes.limit_order;
        for (const expectedMessageHash in precomputedLimitOrderHashes) {
            if ({}.hasOwnProperty.call(precomputedLimitOrderHashes, expectedMessageHash)) {
                const messageData = precomputedLimitOrderHashes[expectedMessageHash];
                const messageHash = getPerpetualLimitOrderMessage(
                    messageData.assetIdSynthetic,
                    messageData.assetIdCollateral,
                    messageData.isBuyingSynthetic,
                    messageData.assetIdFee,
                    messageData.amountSynthetic,
                    messageData.amountCollateral,
                    messageData.amountFee,
                    messageData.nonce,
                    messageData.positionId,
                    messageData.expirationTimestamp
                );
                expect('0x' + messageHash).to.equal(expectedMessageHash);
            }
        }
    });
});

describe('Conditional-Transfer message generation', () => {
    it('should hash message correctly', () => {
        const precomputedMessageHashes = require('../../perpetual_messages_precomputed.json');
        const precomputedCondTransferHashes = precomputedMessageHashes.conditional_transfer;
        for (const expectedMessageHash in precomputedCondTransferHashes) {
            if ({}.hasOwnProperty.call(precomputedCondTransferHashes, expectedMessageHash)) {
                const messageData = precomputedCondTransferHashes[expectedMessageHash];
                const messageHash = getPerpetualConditionalTransferMessage(
                    messageData.assetId,
                    messageData.assetIdFee,
                    messageData.receiverPublicKey,
                    messageData.condition,
                    messageData.senderPositionId,
                    messageData.receiverPositionId,
                    messageData.srcFeePositionId,
                    messageData.nonce,
                    messageData.amount,
                    messageData.maxAmountFee,
                    messageData.expirationTimestamp
                );
                expect('0x' + messageHash).to.equal(expectedMessageHash);
            }
        }
    });
});

describe('Transfer message generation', () => {
    it('should hash message correctly', () => {
        const precomputedMessageHashes = require('../../perpetual_messages_precomputed.json');
        const precomputedTransferHashes = precomputedMessageHashes.transfer;
        for (const expectedMessageHash in precomputedTransferHashes) {
            if ({}.hasOwnProperty.call(precomputedTransferHashes, expectedMessageHash)) {
                const messageData = precomputedTransferHashes[expectedMessageHash];
                const messageHash = getPerpetualTransferMessage(
                    messageData.assetId,
                    messageData.assetIdFee,
                    messageData.receiverPublicKey,
                    messageData.senderPositionId,
                    messageData.receiverPositionId,
                    messageData.feePositionId,
                    messageData.nonce,
                    messageData.amount,
                    messageData.maxAmountFee,
                    messageData.expirationTimestamp
                );
                expect('0x' + messageHash).to.equal(expectedMessageHash);
            }
        }
    });
});

describe('Withdrawal message generation', () => {
    it('should hash message correctly', () => {
        const precomputedMessageHashes = require('../../perpetual_messages_precomputed.json');
        const precomputedWithdrawalHashes = precomputedMessageHashes.withdrawal;
        for (const expectedMessageHash in precomputedWithdrawalHashes) {
            if ({}.hasOwnProperty.call(precomputedWithdrawalHashes, expectedMessageHash)) {
                const messageData = precomputedWithdrawalHashes[expectedMessageHash];
                const messageHash = getPerpetualWithdrawalMessage(
                    messageData.assetIdCollateral,
                    messageData.positionId,
                    messageData.nonce,
                    messageData.expirationTimestamp,
                    messageData.amount
                );
                expect('0x' + messageHash).to.equal(expectedMessageHash);
            }
        }
    });
});
