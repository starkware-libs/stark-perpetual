namespace TransactionType {
    const DEPOSIT = 0;
    const FORCED_TRADE = 1;
    const FORCED_WITHDRAWAL = 2;
    const FUNDING_TICK = 3;
    const ORACLE_PRICES_TICK = 4;
    const TRADE = 5;
    const TRANSFER = 6;
    const LIQUIDATE = 7;
    const WITHDRAWAL = 8;
    const DELEVERAGE = 9;
    const CONDITIONAL_TRANSFER = 10;
}

struct Transaction {
    tx_type: felt,
    tx: felt*,
}

struct Transactions {
    len: felt,
    data: Transaction*,
}
