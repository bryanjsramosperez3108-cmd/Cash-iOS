import Foundation

// Aritmética histórica pura: no cambia el ledger ni recalcula saldos guardados.
// Funciona con los JSON V3-V13: openingCents sigue siendo una base heredada.
enum CashHistoricalBalance {
    enum CalculationError: LocalizedError {
        case overflow
        var errorDescription: String? { "El cálculo del saldo excede el importe permitido." }
    }

    private static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow { throw CalculationError.overflow }
        return result
    }

    // before=nil devuelve el saldo ACTUAL de Cash como antes de V14.
    // before=primer día del mes siguiente devuelve el cierre de un mes.
    static func balance(_ account: CashAccount, in ledger: CashLedger, before: Date? = nil) throws -> Int64 {
        var value = ledger.openingCents[account.rawValue] ?? 0
        for operation in ledger.operations where before.map({ operation.date < $0 }) ?? true {
            switch operation.kind {
            case .income where operation.account == account:
                value = try add(value, operation.cents)
            case .expense where operation.account == account:
                value = try add(value, -operation.cents)
            case .transfer:
                if operation.account == account { value = try add(value, -operation.cents) }
                if operation.destination == account { value = try add(value, operation.cents) }
            default: break
            }
        }
        for change in ledger.balanceAdjustments ?? []
        where change.accountID == account.rawValue && (before.map { change.date < $0 } ?? true) {
            value = try add(value, change.differenceCents)
        }
        return value
    }

    static func month(_ account: CashAccount, in ledger: CashLedger, date: Date,
                      calendar: Calendar = .current) throws -> CashAccountMonthSummary? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        let start = interval.start
        let end = interval.end
        var income: Int64 = 0
        var expense: Int64 = 0
        var transferIn: Int64 = 0
        var transferOut: Int64 = 0
        var adjustments: Int64 = 0
        for item in ledger.operations where item.date >= start && item.date < end {
            switch item.kind {
            case .income where item.account == account:
                income = try add(income, item.cents)
            case .expense where item.account == account:
                expense = try add(expense, item.cents)
            case .transfer:
                if item.account == account { transferOut = try add(transferOut, item.cents) }
                if item.destination == account { transferIn = try add(transferIn, item.cents) }
            default: break
            }
        }
        for change in ledger.balanceAdjustments ?? []
        where change.accountID == account.rawValue && change.date >= start && change.date < end {
            adjustments = try add(adjustments, change.differenceCents)
        }
        return CashAccountMonthSummary(
            opening: try balance(account, in: ledger, before: start),
            income: income, expense: expense,
            transferIn: transferIn, transferOut: transferOut,
            adjustments: adjustments,
            closing: try balance(account, in: ledger, before: end)
        )
    }
}

struct CashAccountMonthSummary {
    let opening: Int64
    let income: Int64
    let expense: Int64
    let transferIn: Int64
    let transferOut: Int64
    let adjustments: Int64
    let closing: Int64
}
