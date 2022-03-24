from services.perpetual.cairo.definitions.perpetual_error_code import PerpetualErrorCode
from services.perpetual.cairo.execute_batch_utils import (
    validate_funding_indices_in_general_config, validate_general_config)
from services.perpetual.cairo.oracle.oracle_price import (
    TimeBounds, check_oracle_prices, signed_prices_to_prices)
from services.perpetual.cairo.output.program_input import ProgramInput
from services.perpetual.cairo.output.program_output import PerpetualOutputs
from services.perpetual.cairo.state.state import CarriedState
from services.perpetual.cairo.transactions.batch_config import BatchConfig, batch_config_new
from services.perpetual.cairo.transactions.conditional_transfer import (
    ConditionalTransfer, execute_conditional_transfer)
from services.perpetual.cairo.transactions.deleverage import Deleverage, execute_deleverage
from services.perpetual.cairo.transactions.deposit import Deposit, execute_deposit
from services.perpetual.cairo.transactions.forced_trade import ForcedTrade, execute_forced_trade
from services.perpetual.cairo.transactions.forced_withdrawal import (
    ForcedWithdrawal, execute_forced_withdrawal)
from services.perpetual.cairo.transactions.funding_tick import FundingTick, execute_funding_tick
from services.perpetual.cairo.transactions.liquidate import Liquidate, execute_liquidate
from services.perpetual.cairo.transactions.oracle_prices_tick import (
    OraclePricesTick, execute_oracle_prices_tick)
from services.perpetual.cairo.transactions.trade import Trade, execute_trade
from services.perpetual.cairo.transactions.transaction import (
    Transaction, Transactions, TransactionType)
from services.perpetual.cairo.transactions.transfer import Transfer, execute_transfer
from services.perpetual.cairo.transactions.withdrawal import Withdrawal, execute_withdrawal
from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.math import assert_le
from starkware.cairo.common.registers import get_fp_and_pc

func execute_transaction(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*, batch_config : BatchConfig*,
        tx : Transaction*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    local tx_type = tx.tx_type
    alloc_locals

    if tx_type == TransactionType.ORACLE_PRICES_TICK:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state,
            outputs) = execute_oracle_prices_tick(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, OraclePricesTick*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.FUNDING_TICK:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state,
            outputs) = execute_funding_tick(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, FundingTick*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    # For every other transaction, we need to check that the funding timestamp is up to date
    # with respect to the system time.
    %{ error_code = ids.PerpetualErrorCode.INVALID_FUNDING_TICK_TIMESTAMP %}
    assert_le{range_check_ptr=range_check_ptr}(
        carried_state.system_time,
        carried_state.global_funding_indices.funding_timestamp +
        batch_config.general_config.timestamp_validation_config.funding_validity_period)
    %{ del error_code %}

    if tx_type == TransactionType.TRADE:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_trade(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, Trade*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.DEPOSIT:
        # Deposit.
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_deposit(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, Deposit*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.TRANSFER:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_transfer(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, Transfer*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.CONDITIONAL_TRANSFER:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state,
            outputs) = execute_conditional_transfer(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, ConditionalTransfer*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.LIQUIDATE:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_liquidate(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, Liquidate*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.DELEVERAGE:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_deleverage(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, Deleverage*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.WITHDRAWAL:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_withdrawal(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, Withdrawal*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.FORCED_WITHDRAWAL:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state,
            outputs) = execute_forced_withdrawal(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, ForcedWithdrawal*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    if tx_type == TransactionType.FORCED_TRADE:
        let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state,
            outputs) = execute_forced_trade(
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            batch_config=batch_config,
            outputs=outputs,
            tx=cast(tx.tx, ForcedTrade*))
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    assert 1 = 0
    jmp rel 0
end

func execute_batch_transactions(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*, batch_config : BatchConfig*,
        n_txs : felt, tx : Transaction*) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    if n_txs == 0:
        # No transactions left.
        return (
            pedersen_ptr=pedersen_ptr,
            range_check_ptr=range_check_ptr,
            ecdsa_ptr=ecdsa_ptr,
            carried_state=carried_state,
            outputs=outputs)
    end

    let (pedersen_ptr, range_check_ptr, ecdsa_ptr, carried_state, outputs) = execute_transaction(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
        batch_config=batch_config,
        tx=tx)

    return execute_batch_transactions(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
        batch_config=batch_config,
        n_txs=n_txs - 1,
        tx=tx + Transaction.SIZE)
end

func execute_batch(
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, program_input : ProgramInput*, outputs : PerpetualOutputs*,
        txs : Transactions*, end_system_time) -> (
        pedersen_ptr : HashBuiltin*, range_check_ptr, ecdsa_ptr : SignatureBuiltin*,
        carried_state : CarriedState*, outputs : PerpetualOutputs*):
    alloc_locals
    let (local __fp__, _) = get_fp_and_pc()

    let (range_check_ptr) = validate_general_config(
        range_check_ptr=range_check_ptr, general_config=program_input.general_config)

    # Time bound to check for oracle price signature timestamps.
    local time_bounds : TimeBounds
    assert time_bounds.min_time = (
        carried_state.system_time -
        program_input.general_config.timestamp_validation_config.price_validity_period)
    assert time_bounds.max_time = end_system_time

    # Validate minimal and maximal oracle price signatures. Refer to the documentation of
    # OraclePricesTick for more details.
    let (range_check_ptr, ecdsa_ptr, pedersen_ptr) = check_oracle_prices(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        pedersen_ptr=pedersen_ptr,
        n_oracle_prices=program_input.n_signed_oracle_prices,
        asset_oracle_prices=program_input.signed_min_oracle_prices,
        time_bounds=&time_bounds,
        general_config=program_input.general_config)
    let (local range_check_ptr, local ecdsa_ptr, local pedersen_ptr) = check_oracle_prices(
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        pedersen_ptr=pedersen_ptr,
        n_oracle_prices=program_input.n_signed_oracle_prices,
        asset_oracle_prices=program_input.signed_max_oracle_prices,
        time_bounds=&time_bounds,
        general_config=program_input.general_config)

    # Convert Signed prices to prices.
    let (local signed_min_oracle_prices) = signed_prices_to_prices(
        n_oracle_prices=program_input.n_signed_oracle_prices,
        asset_oracle_prices=program_input.signed_min_oracle_prices)
    let (signed_max_oracle_prices) = signed_prices_to_prices(
        n_oracle_prices=program_input.n_signed_oracle_prices,
        asset_oracle_prices=program_input.signed_max_oracle_prices)

    # Create BatchConfig.
    let (batch_config : BatchConfig*) = batch_config_new(
        general_config=program_input.general_config,
        signed_min_oracle_prices=signed_min_oracle_prices,
        signed_max_oracle_prices=signed_max_oracle_prices,
        n_oracle_prices=program_input.n_signed_oracle_prices,
        min_expiration_timestamp=program_input.minimum_expiration_timestamp)

    # Execute all txs.
    let (local pedersen_ptr, local range_check_ptr, local ecdsa_ptr, local carried_state,
        local outputs) = execute_batch_transactions(
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs,
        batch_config=batch_config,
        n_txs=txs.len,
        tx=txs.data)

    # Post batch validations.
    validate_funding_indices_in_general_config(
        global_funding_indices=carried_state.global_funding_indices,
        general_config=program_input.general_config)

    assert carried_state.system_time = end_system_time

    return (
        pedersen_ptr=pedersen_ptr,
        range_check_ptr=range_check_ptr,
        ecdsa_ptr=ecdsa_ptr,
        carried_state=carried_state,
        outputs=outputs)
end
