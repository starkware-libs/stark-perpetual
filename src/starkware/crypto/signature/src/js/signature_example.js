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

const starkwareAssets = require('./asset.js');
const starkwareKeyDerivation = require('./key_derivation.js');
const starkwareCrypto = require('./signature.js');
const assert = require('assert');
const testData = require('../../test/config/signature_test_data.json');

//=================================================================================================
// Example: Generating a STARK key from an Ethereum signature:
//=================================================================================================
{
    const expectedStarkKey = '5b20c8eea0dab0e62278f967feb1ef58d910cb7d5653cc33b0447355ea5d640';
    const ethSignature = '0x21fbf0696d5e0aa2ef41a2b4ffb623bcaf070461d61cf7251c74161f82fec3a43' +
        '70854bc0a34b3ab487c1bc021cd318c734c51ae29374f2beb0e6f2dd49b4bf41c';
    const privateStarkKey = starkwareKeyDerivation.getPrivateKeyFromEthSignature(ethSignature);
    const starkKey = starkwareKeyDerivation.privateToStarkKey(privateStarkKey);
    assert(
        starkKey === expectedStarkKey,
        `Got: ${starkKey}.
        Expected: ${expectedStarkKey}`
    );
}

//=================================================================================================
// Example: Calculating asset type and asset ID:
//=================================================================================================
{
    const expectedAssetType = '0x352386d5b7c781d47ecd404765307d74edc4d43b0490b8e03c71ac7a7429653';
    const assetData = {
        type: 'ERC20',
        data: {
            quantum: '10000',
            tokenAddress: '0xdAC17F958D2ee523a2206206994597C13D831ec7'
        }
    };
    const assetType = starkwareAssets.getAssetType(assetData);
    assert(
        assetType === expectedAssetType,
        `Got: ${assetType}.
        Expected: ${expectedAssetType}`
    );
    // For ERC20 tokens the asset type and asset ID are interchangeable.
    const assetId = starkwareAssets.getAssetId(assetData);
    assert(
        assetId === expectedAssetType,
        `Got: ${assetId}.
        Expected: ${expectedAssetType}`
    );
}

//=================================================================================================
// Example: Signing a StarkEx Order With Fee:
//=================================================================================================
{
    const privateKey = testData.meta_data.party_a_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(
        publicKeyX.toString(16) === testData.settlement.party_a_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.settlement.party_a_order.public_key.substring(2)}`
    );

    const { party_a_order: partyAOrder } = testData.settlement;
    const feeInfo = testData.fee_info_user;
    const msgHash = starkwareCrypto.getLimitOrderMsgHashWithFee(
        partyAOrder.vault_id_sell, // - vault_sell (uint64)
        partyAOrder.vault_id_buy, // - vault_buy (uint64)
        partyAOrder.amount_sell, // - amount_sell (uint63 decimal str)
        partyAOrder.amount_buy, // - amount_buy (uint63 decimal str)
        partyAOrder.token_sell, // - token_sell (hex str with 0x prefix < prime)
        partyAOrder.token_buy, // - token_buy (hex str with 0x prefix < prime)
        partyAOrder.nonce, // - nonce (uint31)
        partyAOrder.expiration_timestamp, // - expiration_timestamp (uint22)
        feeInfo.token_id, // - token (hex str with 0x prefix < prime)
        feeInfo.source_vault_id, // - fee_source_vault_id (uint31)
        feeInfo.fee_limit // - amount (uint63 decimal str)
    );

    assert(msgHash === testData.meta_data.party_a_order_with_fee.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` +
        testData.meta_data.party_a_order_with_fee.message_hash.substring(2));

    // The following is the JSON representation of an order:
    console.log('Order With Fee JSON representation: ');
    // Fee info is added to the order, and will also be seen in the JSON of Settlement.
    partyAOrder.fee_info = feeInfo; // eslint-disable-line
    console.log(partyAOrder);
    console.log('\n');
}

//=================================================================================================
// Example: StarkEx Transfer:
//=================================================================================================
{
    const privateKey = testData.meta_data.transfer_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(publicKeyX.toString(16) === testData.transfer_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.transfer_order.public_key.substring(2)}`);

    const transfer = testData.transfer_order;
    const msgHash = starkwareCrypto.getTransferMsgHash(
        transfer.amount, // - amount (uint63 decimal str)
        transfer.nonce, // - nonce (uint31)
        transfer.sender_vault_id, // - sender_vault_id (uint31)
        transfer.token, // - token (hex str with 0x prefix < prime)
        transfer.target_vault_id, // - target_vault_id (uint31)
        transfer.target_public_key, // - target_public_key (hex str with 0x prefix < prime)
        transfer.expiration_timestamp // - expiration_timestamp (uint22)
    );

    assert(msgHash === testData.meta_data.transfer_order.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` +
        testData.meta_data.transfer_order.message_hash.substring(2));

    // The following is the JSON representation of a transfer:
    console.log('Transfer JSON representation: ');
    console.log(transfer);
    console.log('\n');
}

//=================================================================================================
// Example: StarkEx Conditional Transfer:
//=================================================================================================
{
    const privateKey = testData.meta_data.conditional_transfer_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(publicKeyX.toString(16) === testData.conditional_transfer_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.conditional_transfer_order.public_key.substring(2)}`);

    const transfer = testData.conditional_transfer_order;
    const msgHash = starkwareCrypto.getTransferMsgHash(
        transfer.amount, // - amount (uint63 decimal str)
        transfer.nonce, // - nonce (uint31)
        transfer.sender_vault_id, // - sender_vault_id (uint31)
        transfer.token, // - token (hex str with 0x prefix < prime)
        transfer.target_vault_id, // - target_vault_id (uint31)
        transfer.target_public_key, // - target_public_key (hex str with 0x prefix < prime)
        transfer.expiration_timestamp, // - expiration_timestamp (uint22)
        transfer.condition // - condition (hex str with 0x prefix < prime)
    );

    assert(msgHash === testData.meta_data.conditional_transfer_order.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` +
        testData.meta_data.conditional_transfer_order.message_hash.substring(2));

    // The following is the JSON representation of a transfer:
    console.log('Conditional Transfer JSON representation: ');
    console.log(transfer);
    console.log('\n');
}

//=================================================================================================
// Example: StarkEx Transfer With Fee:
//=================================================================================================
{
    const privateKey = testData.meta_data.transfer_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(publicKeyX.toString(16) === testData.transfer_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.transfer_order.public_key.substring(2)}`);

    const transfer = testData.transfer_order;
    const feeInfo = testData.fee_info_user;
    const msgHash = starkwareCrypto.getTransferMsgHashWithFee(
        transfer.amount, // - amount (uint63 decimal str)
        transfer.nonce, // - nonce (uint31)
        transfer.sender_vault_id, // - sender_vault_id (uint64)
        transfer.token, // - token (hex str with 0x prefix < prime)
        transfer.target_vault_id, // - target_vault_id (uint64)
        transfer.target_public_key, // - target_public_key (hex str with 0x prefix < prime)
        transfer.expiration_timestamp, // - expiration_timestamp (uint22)
        feeInfo.token_id, // - token (hex str with 0x prefix < prime)
        feeInfo.source_vault_id, // - fee_source_vault_id (uint64)
        feeInfo.fee_limit // - amount (uint63 decimal str)
    );

    assert(msgHash === testData.meta_data.transfer_order_with_fee.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` +
        testData.meta_data.transfer_order.message_hash.substring(2));

    // The following is the JSON representation of a transfer:
    console.log('Transfer With Fee JSON representation: ');
    console.log(transfer);
    console.log('\n');
}

//=================================================================================================
// Example: StarkEx Conditional Transfer With Fee:
//=================================================================================================
{
    const privateKey = testData.meta_data.conditional_transfer_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(publicKeyX.toString(16) === testData.conditional_transfer_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.conditional_transfer_order.public_key.substring(2)}`);

    const transfer = testData.conditional_transfer_order;
    const feeInfo = testData.fee_info_user;
    const msgHash = starkwareCrypto.getTransferMsgHashWithFee(
        transfer.amount, // - amount (uint63 decimal str)
        transfer.nonce, // - nonce (uint31)
        transfer.sender_vault_id, // - sender_vault_id (uint64)
        transfer.token, // - token (hex str with 0x prefix < prime)
        transfer.target_vault_id, // - target_vault_id (uint64)
        transfer.target_public_key, // - target_public_key (hex str with 0x prefix < prime)
        transfer.expiration_timestamp, // - expiration_timestamp (uint22)
        feeInfo.token_id, // - token (hex str with 0x prefix < prime)
        feeInfo.source_vault_id, // - fee_source_vault_id (uint64)
        feeInfo.fee_limit, // - amount (uint63 decimal str)
        transfer.condition // - condition (hex str with 0x prefix < prime)
    );

    assert(
        msgHash ===
        testData.meta_data.conditional_transfer_order_with_fee.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` +
        testData.meta_data.conditional_transfer_order.message_hash.substring(2)
    );

    // The following is the JSON representation of a transfer:
    console.log('Conditional Transfer With Fee JSON representation: ');
    console.log(transfer);
    console.log('\n');
}

//=================================================================================================
// Example: And adding a matching order to create a settlement:
//=================================================================================================
{
    const privateKey = testData.meta_data.party_b_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(publicKeyX.toString(16) === testData.settlement.party_b_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.settlement.party_b_order.public_key.substring(2)}`);

    const { party_b_order: partyBOrder } = testData.settlement;
    const msgHash = starkwareCrypto.getLimitOrderMsgHash(
        partyBOrder.vault_id_sell, // - vault_sell (uint31)
        partyBOrder.vault_id_buy, // - vault_buy (uint31)
        partyBOrder.amount_sell, // - amount_sell (uint63 decimal str)
        partyBOrder.amount_buy, // - amount_buy (uint63 decimal str)
        partyBOrder.token_sell, // - token_sell (hex str with 0x prefix < prime)
        partyBOrder.token_buy, // - token_buy (hex str with 0x prefix < prime)
        partyBOrder.nonce, // - nonce (uint31)
        partyBOrder.expiration_timestamp // - expiration_timestamp (uint22)
    );

    assert(msgHash === testData.meta_data.party_b_order.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` + testData.meta_data.party_b_order.message_hash.substring(2));

    const msgSignature = starkwareCrypto.sign(keyPair, msgHash);
    const { r, s } = msgSignature;

    assert(starkwareCrypto.verify(publicKey, msgHash, msgSignature));
    assert(r.toString(16) === partyBOrder.signature.r.substring(2),
        `Got: ${r.toString(16)}. Expected: ${partyBOrder.signature.r.substring(2)}`);
    assert(s.toString(16) === partyBOrder.signature.s.substring(2),
        `Got: ${s.toString(16)}. Expected: ${partyBOrder.signature.s.substring(2)}`);

    // The following is the JSON representation of a settlement:
    console.log('Settlement JSON representation: ');
    console.log(testData.settlement);
}

//=================================================================================================
// Test: valid transfer with sender_vault_id=2**63+10 :
//=================================================================================================
{
    const transfer = testData.transfer_order_2nd_valid_range;
    const feeInfo = testData.fee_info_user;

    const msgHash = starkwareCrypto.getTransferMsgHashWithFee(
        transfer.amount, // - amount (uint63 decimal str)
        transfer.nonce, // - nonce (uint31)
        transfer.sender_vault_id, // - sender_vault_id (uint64)
        transfer.token, // - token (hex str with 0x prefix < prime)
        transfer.target_vault_id, // - target_vault_id (uint64)
        transfer.target_public_key, // - target_public_key (hex str with 0x prefix < prime)
        transfer.expiration_timestamp, // - expiration_timestamp (uint22)
        feeInfo.token_id, // - token (hex str with 0x prefix < prime)
        feeInfo.source_vault_id, // - fee_source_vault_id (uint64)
        feeInfo.fee_limit, // - amount (uint63 decimal str)
        transfer.condition // - condition (hex str with 0x prefix < prime)
    );

    assert(
        msgHash ===
        testData.meta_data.transfer_order_2nd_valid_range.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` +
        testData.meta_data.transfer_order_2nd_valid_range.message_hash.substring(2)
    );

    // The following is the JSON representation of a transfer with sender_vault_id in the second
    // valid range:
    console.log('Transfer JSON representation: ');
    console.log(transfer);
    console.log('\n');
}

//=================================================================================================
// Example: Signing a StarkEx Order without fees (DEPRECATED since StarkEx v4.5):
//=================================================================================================
{
    const privateKey = testData.meta_data.party_a_order.private_key.substring(2);
    const keyPair = starkwareCrypto.ec.keyFromPrivate(privateKey, 'hex');
    const publicKey = starkwareCrypto.ec.keyFromPublic(keyPair.getPublic(true, 'hex'), 'hex');
    const publicKeyX = publicKey.pub.getX();

    assert(
        publicKeyX.toString(16) === testData.settlement.party_a_order.public_key.substring(2),
        `Got: ${publicKeyX.toString(16)}.
        Expected: ${testData.settlement.party_a_order.public_key.substring(2)}`
    );

    const { party_a_order: partyAOrder } = testData.settlement;
    const msgHash = starkwareCrypto.getLimitOrderMsgHash(
        partyAOrder.vault_id_sell, // - vault_sell (uint31)
        partyAOrder.vault_id_buy, // - vault_buy (uint31)
        partyAOrder.amount_sell, // - amount_sell (uint63 decimal str)
        partyAOrder.amount_buy, // - amount_buy (uint63 decimal str)
        partyAOrder.token_sell, // - token_sell (hex str with 0x prefix < prime)
        partyAOrder.token_buy, // - token_buy (hex str with 0x prefix < prime)
        partyAOrder.nonce, // - nonce (uint31)
        partyAOrder.expiration_timestamp // - expiration_timestamp (uint22)
    );

    assert(msgHash === testData.meta_data.party_a_order.message_hash.substring(2),
        `Got: ${msgHash}. Expected: ` + testData.meta_data.party_a_order.message_hash.substring(2));

    const msgSignature = starkwareCrypto.sign(keyPair, msgHash);
    const { r, s } = msgSignature;

    assert(starkwareCrypto.verify(publicKey, msgHash, msgSignature));
    assert(r.toString(16) === partyAOrder.signature.r.substring(2),
        `Got: ${r.toString(16)}. Expected: ${partyAOrder.signature.r.substring(2)}`);
    assert(s.toString(16) === partyAOrder.signature.s.substring(2),
        `Got: ${s.toString(16)}. Expected: ${partyAOrder.signature.s.substring(2)}`);

    // The following is the JSON representation of an order:
    console.log('Order JSON representation: ');
    console.log(partyAOrder);
    console.log('\n');


    //=============================================================================================
    // Example: StarkEx key serialization:
    //=============================================================================================

    const pubXStr = publicKey.pub.getX().toString('hex');
    const pubYStr = publicKey.pub.getY().toString('hex');

    // Verify Deserialization.
    const pubKeyDeserialized = starkwareCrypto.ec.keyFromPublic({ x: pubXStr, y: pubYStr }, 'hex');
    assert(starkwareCrypto.verify(pubKeyDeserialized, msgHash, msgSignature));
}
