import Foundation

// Conservamos los raw values de Taxes para decodificar movimientos anteriores.
enum CashKind: String, Codable, CaseIterable, Identifiable {
    case income, expense, transfer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .income: return "Ingreso"
        case .expense: return "Gasto"
        case .transfer: return "Transferencia"
        }
    }
}

enum CashCategory: String, Codable, CaseIterable, Identifiable {
    case salary, sales, extra, food, transport, home, bills, shopping, health, leisure, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .salary: return "Salario"
        case .sales: return "Ventas"
        case .extra: return "Ingreso extra"
        case .food: return "Alimentación"
        case .transport: return "Transporte"
        case .home: return "Hogar"
        case .bills: return "Servicios"
        case .shopping: return "Compras"
        case .health: return "Salud"
        case .leisure: return "Entretenimiento"
        case .other: return "Otros"
        }
    }
    var symbol: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .sales: return "bag.fill"
        case .extra: return "sparkles"
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .home: return "house.fill"
        case .bills: return "bolt.fill"
        case .shopping: return "basket.fill"
        case .health: return "cross.case.fill"
        case .leisure: return "gamecontroller.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
    static func options(_ kind: CashKind) -> [CashCategory] {
        switch kind {
        case .income: return [.salary, .sales, .extra, .other]
        case .expense: return [.food, .transport, .home, .bills, .shopping, .health, .leisure, .other]
        case .transfer: return [.other]
        }
    }
}

// V10: los valores de las cuentas siguen codificándose como cadenas simples
// ("cash", "bac", etc.), exactamente como en los respaldos V3-V9.
struct CashAccount: RawRepresentable, Hashable, Codable, Identifiable, CaseIterable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                debugDescription: "Identificador de cuenta vacío")
        }
        self.rawValue = value
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawValue)
    }
    var id: String { rawValue }
    static let cash = Self(rawValue: "cash")
    static let occidente = Self(rawValue: "occidente")
    static let bac = Self(rawValue: "bac")
    static let atlantida = Self(rawValue: "atlantida")
    static let sagrada = Self(rawValue: "sagrada")
    static var allCases: [Self] { [.cash, .occidente, .bac, .atlantida, .sagrada] }
    var name: String {
        switch rawValue {
        case "cash": "Efectivo"
        case "occidente": "Banco de Occidente"
        case "bac": "BAC"
        case "atlantida": "Banco Atlántida"
        case "sagrada": "Cooperativa Sagrada Familia"
        default: rawValue
        }
    }
    var symbol: String { self == .cash ? "banknote.fill" : "building.columns.fill" }
}

// V10: identidad visual editable, incluida en CashLedger y su respaldo JSON.
struct CashUserAccount: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var imageData: Data? = nil
    // "original", "blanco", "azul", "rojo", "verde", "grafito"
    var colorStyle: String = "original"
    // Opcional para permitir restaurar sin cambios los JSON antiguos (V3-V10).
    var imageFillsCard: Bool? = nil
    var isBuiltIn: Bool = false

    static var defaults: [CashUserAccount] {
        CashAccount.allCases.map {
            CashUserAccount(id: $0.rawValue, name: $0.name, isBuiltIn: true)
        }
    }
}

// Un movimiento lleva importes en centavos enteros; nunca almacenamos Double.
struct CashOperation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: CashKind
    var title: String
    var cents: Int64
    var date: Date
    var category: CashCategory
    var account: CashAccount
    var destination: CashAccount? // Exclusivo de transferencias.
    var note: String
    // Nil en los movimientos anteriores a esta actualización: se infiere del enum legacy.
    var categoryID: String? = nil
}

struct CashLedger: Codable {
    var schemaVersion: Int = 2
    var openingCents: [String: Int64] = [:]
    var operations: [CashOperation] = []
    var migratedLegacyCount: Int = 0
    // Opcional para preservar la decodificación de CashLedger.json versión 2 ya existente.
    var categoryItems: [CashUserCategory]? = nil
    // Opcional: los respaldos antiguos sin esta clave siguen siendo válidos.
    var accountItems: [CashUserAccount]? = nil
    // V14: ajustes NUEVOS con fecha real; nil en copias de seguridad V3-V13.
    var balanceAdjustments: [CashBalanceAdjustment]? = nil
    // Fecha desde la que Cash registra cambios manuales con fecha.
    // Si falta, el historial anterior debe tratarse como reconstruido.
    var historicalTrackingSince: Date? = nil
}

// No son ingresos ni gastos: únicamente corrigen el saldo de una cuenta.
struct CashBalanceAdjustment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var accountID: String
    var differenceCents: Int64
    var date: Date
}

struct CashUserCategory: Identifiable, Codable, Equatable {
    var id: String
    var kind: CashKind
    var name: String
    var symbol: String
    // Se almacena imagen reducida para no sobrecargar el archivo de finanzas.
    var iconData: Data? = nil
    var isBuiltIn: Bool = false

    var title: String { name }
    static var defaults: [CashUserCategory] {
        var items: [CashUserCategory] = []
        for kind in [CashKind.income, .expense] {
            for category in CashCategory.options(kind) {
                items.append(.init(id: "\(kind.rawValue).\(category.rawValue)", kind: kind,
                                   name: category.title, symbol: category.symbol, isBuiltIn: true))
            }
        }
        items.append(.init(id: "transfer.internal", kind: .transfer,
                           name: "Entre cuentas", symbol: "arrow.left.arrow.right", isBuiltIn: true))
        return items
    }
    static func legacyID(for operation: CashOperation) -> String {
        if operation.kind == .transfer { return "transfer.internal" }
        return "\(operation.kind.rawValue).\(operation.category.rawValue)"
    }
}


// Modelo idéntico al guardado por TAXES; para migración sin eliminar datos.
private enum LegacyKind: String, Codable { case income, expense }
private struct LegacyMovement: Codable {
    var id: UUID
    var title: String
    var amount: Double
    var date: Date
    var kind: LegacyKind
    var category: CashCategory
    var note: String
}

enum CashMoney {
    static let locale = Locale(identifier: "es_HN")

    static func formatted(_ cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let decimal = NSDecimalNumber(value: cents).dividing(by: NSDecimalNumber(value: 100))
        return "L " + (formatter.string(from: decimal) ?? "0.00")
    }

    // Acepta 1234,50 o 1234.50, opcionalmente con separadores de miles.
    // Devuelve nil si existen más de dos decimales o el monto excede el límite.
    static func parse(_ source: String) -> Int64? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "L", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !value.isEmpty, !value.contains("-"), !value.contains("+") else { return nil }
        let comma = value.lastIndex(of: ",")
        let period = value.lastIndex(of: ".")
        let decimalCharacter: Character?
        if let comma, let period {
            decimalCharacter = comma > period ? "," : "."
        } else if let index = comma ?? period {
            let digitsAfter = value.distance(from: value.index(after: index), to: value.endIndex)
            decimalCharacter = digitsAfter <= 2 ? value[index] : nil
        } else {
            decimalCharacter = nil
        }
        var normalized = ""
        for character in value {
            if character.isNumber && character.isASCII { normalized.append(character) }
            else if character == decimalCharacter { normalized.append(".") }
            else if character == "," || character == "." { continue }
            else { return nil }
        }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty,
              parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.count == 1 || parts[1].count <= 2,
              let whole = Int64(parts[0]), whole <= 90_000_000_000_000 else { return nil }
        let fraction: Int64
        if parts.count == 2 {
            let raw = String(parts[1]); fraction = Int64(raw.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        } else { fraction = 0 }
        let (scaled, overflow) = whole.multipliedReportingOverflow(by: 100)
        guard !overflow else { return nil }
        let (sum, extraOverflow) = scaled.addingReportingOverflow(fraction)
        return extraOverflow ? nil : sum
    }

    static func editable(_ cents: Int64) -> String {
        let whole = cents / 100
        let fraction = abs(cents % 100)
        return "\(whole).\(String(format: "%02d", fraction))"
    }

    static func legacyCents(_ amount: Double) -> Int64? {
        guard amount.isFinite, amount > 0 else { return nil }
        return parse(String(format: "%.2f", amount))
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year()).capitalized
    }
}

// Expuesto internamente para que CashStore pueda migrar el modelo anterior.
func migrateOldTaxesMovements(_ data: Data) -> [CashOperation]? {
    guard let old = try? JSONDecoder().decode([LegacyMovement].self, from: data) else { return nil }
    var result: [CashOperation] = []
    for record in old {
        // Migración integral: un registro inválido detiene la operación; no se descarta en silencio.
        guard let cents = CashMoney.legacyCents(record.amount) else { return nil }
        result.append(CashOperation(id: record.id,
                         kind: record.kind == .income ? .income : .expense,
                         title: record.title, cents: cents, date: record.date,
                         category: record.category, account: .cash,
                         destination: nil, note: record.note))
    }
    return result
}
