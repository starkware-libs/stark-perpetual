namespace TransactionType:
    const DEPOSIT = 0
    const FORCED_TRADE = 1
    const FORCED_WITHDRAWAL = 2
    const FUNDING_TICK = 3
    const ORACLE_PRICES_TICK = 4
    const TRADE = 5
    const TRANSFER = 6
    const LIQUIDATE = 7
    const WITHDRAWAL = 8
    const DELEVERAGE = 9
    const CONDITIONAL_TRANSFER = 10
end

struct Transaction:
    member tx_type : felt
    member tx : felt*
end

struct Transactions:
    member len : felt
    member data : Transaction*
end
