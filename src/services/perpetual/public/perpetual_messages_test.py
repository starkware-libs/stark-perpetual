import json
import os
from typing import Dict

import pytest

from services.perpetual.public.perpetual_messages import (
    get_conditional_transfer_msg, get_limit_order_msg, get_transfer_msg, get_withdrawal_msg)


@pytest.fixture(scope='module')
def perpetual_messages_file() -> Dict[str, dict]:
    json_file = os.path.join(
        os.path.dirname(__file__),
        'perpetual_messages_precomputed.json')
    return json.load(open(json_file))


def test_limit_order_precomputed(perpetual_messages_file: Dict[str, dict]):
    # Tests that the get_limit_order_msg function produces hashed messages as expected.
    for expectedMessageHash, messageData in perpetual_messages_file['limit_order'].items():
        messageHash = get_limit_order_msg(
            messageData['assetIdSynthetic'],
            messageData['assetIdCollateral'],
            messageData['isBuyingSynthetic'],
            messageData['assetIdFee'],
            messageData['amountSynthetic'],
            messageData['amountCollateral'],
            messageData['amountFee'],
            messageData['nonce'],
            messageData['positionId'],
            messageData['expirationTimestamp']
        )
        assert hex(messageHash) == expectedMessageHash


def test_conditional_transfer_precomputed(perpetual_messages_file: Dict[str, dict]):
    # Tests that the get_transfer_msg function produces hashed messages as expected.
    for expectedMessageHash, messageData in perpetual_messages_file['conditional_transfer'].items():
        messageHash = get_conditional_transfer_msg(
            messageData['assetId'],
            messageData['assetIdFee'],
            messageData['receiverPublicKey'],
            messageData['condition'],
            messageData['senderPositionId'],
            messageData['receiverPositionId'],
            messageData['srcFeePositionId'],
            messageData['nonce'],
            messageData['amount'],
            messageData['maxAmountFee'],
            messageData['expirationTimestamp']
        )
        assert hex(messageHash) == expectedMessageHash


def test_transfer_precomputed(perpetual_messages_file: Dict[str, dict]):
    # Tests that the get_transfer_msg function produces hashed messages as expected.
    for expectedMessageHash, messageData in perpetual_messages_file['transfer'].items():
        messageHash = get_transfer_msg(
            messageData['assetId'],
            messageData['assetIdFee'],
            messageData['receiverPublicKey'],
            messageData['senderPositionId'],
            messageData['receiverPositionId'],
            messageData['feePositionId'],
            messageData['nonce'],
            messageData['amount'],
            messageData['maxAmountFee'],
            messageData['expirationTimestamp']
        )
        assert hex(messageHash) == expectedMessageHash


def test_withdrawal_precomputed(perpetual_messages_file: Dict[str, dict]):
    # Tests that the get_withdrawal_msg function produces hashed messages as expected.
    for expectedMessageHash, messageData in perpetual_messages_file['withdrawal'].items():
        messageHash = get_withdrawal_msg(
            messageData['assetIdCollateral'],
            messageData['positionId'],
            messageData['nonce'],
            messageData['expirationTimestamp'],
            messageData['amount']
        )
        assert hex(messageHash) == expectedMessageHash
