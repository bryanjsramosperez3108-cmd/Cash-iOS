import Foundation
import SwiftUI

// Persiste en Documents/CashLedger.json mediante escritura atómica.
// Mantiene además una copia de la versión anterior antes de cada modificación.
@MainActor
final class CashStore: ObservableObject {
    @Published private(set) var ledger = CashLedger()
    @Published var notice: String?

    private let fileName = "CashLedger.json"
    private let backupName = "CashLedger.previous.json"
    private let oldKey = "taxes.movements.v1"
    private var storageBlocked = false

    init() { load() }

    private var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var file: URL { documents.appendingPathComponent(fileName) }

    private func load() {
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let raw = try Data(contentsOf: file)
                let decoded = try JSONDecoder().decode(CashLedger.self, from: raw)
                guard decoded.schemaVersion == 2 else {
                    storageBlocked = true
                    notice = "Se encontró una versión de datos no compatible. No se modificó ningún archivo."
                    return
                }
                // Solo se realiza una vez al pasar a V14. Se conserva el ledger
                // original y se registra cuándo empiezan los ajustes fechados.
                if decoded.historicalTrackingSince == nil {
                    var upgraded = decoded
                    upgraded.historicalTrackingSince = Date()
                    try persist(upgraded)
                    ledger = upgraded
                } else {
                    ledger = decoded
                }
            } catch {
                storageBlocked = true
                notice = "No se pudo leer el archivo financiero. Los datos originales siguen almacenados; no guardes movimientos hasta resolverlo: \(error.localizedDescription)"
            }
            return
        }
        // Migración única: lee los mismos datos que guardaba el código original.
        guard let legacyData = UserDefaults.standard.data(forKey: oldKey) else { return }
        guard let converted = migrateOldTaxesMovements(legacyData) else {
            storageBlocked = true
            notice = "No se pudo interpretar el historial anterior. No se modificaron sus datos."
            return
        }
        do {
            // Copia del JSON de TAXES. No borramos su clave de UserDefaults.
            let legacyBackup = documents.appendingPathComponent("Taxes_Legacy_Original.json")
            if !FileManager.default.fileExists(atPath: legacyBackup.path) {
                try legacyData.write(to: legacyBackup, options: .atomic)
            }
            var newLedger = CashLedger()
            newLedger.operations = converted
            newLedger.migratedLegacyCount = converted.count
            newLedger.historicalTrackingSince = Date()
            try persist(newLedger)
            ledger = newLedger
            if !converted.isEmpty {
                notice = "Se conservaron \(converted.count) movimientos de Taxes. Como Taxes no tenía cuentas, fueron asignados provisionalmente a Efectivo. Revisa las cuentas de los movimientos migrados para confirmar que sus saldos son correctos."
            }
        } catch {
            storageBlocked = true
            notice = "La migración no se completó; los movimientos originales permanecen sin cambios. \(error.localizedDescription)"
        }
    }

    private func persist(_ next: CashLedger) throws {
        let encoded = try JSONEncoder().encode(next)
        let manager = FileManager.default
        if manager.fileExists(atPath: file.path) {
            let backup = documents.appendingPathComponent(backupName)
            if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
            try manager.copyItem(at: file, to: backup)
        }
        try encoded.write(to: file, options: .atomic)
    }

    private func commit(_ next: CashLedger) throws {
        guard !storageBlocked else {
            throw CashStoreError.message("El almacenamiento está bloqueado para proteger los datos originales. Contacta soporte antes de guardar nuevas operaciones.")
        }
        var candidate = next
        if candidate.historicalTrackingSince == nil { candidate.historicalTrackingSince = Date() }
        try validate(candidate)
        try persist(candidate)
        ledger = candidate
    }

    // Aritmética exacta con comprobación de desbordamientos.
    private func checkedSum(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        if overflow { throw CashStoreError.message("El importe excede el límite permitido.") }
        return value
    }

    private func currentBalance(_ account: CashAccount, in state: CashLedger) throws -> Int64 {
        try CashHistoricalBalance.balance(account, in: state)
    }

    private func validate(_ state: CashLedger) throws {
        guard Set(state.operations.map(\.id)).count == state.operations.count else {
            throw CashStoreError.message("Hay movimientos duplicados.")
        }
        for operation in state.operations {
            guard operation.cents <= 9_000_000_000_000_000 else {
                throw CashStoreError.message("Importe fuera del límite permitido.")
            }
            guard operation.cents > 0 else { throw CashStoreError.message("El importe debe ser mayor que cero.") }
            if operation.kind == .transfer {
                guard let destination = operation.destination, destination != operation.account else {
                    throw CashStoreError.message("El origen y el destino deben ser diferentes.")
                }
            } else if operation.destination != nil {
                throw CashStoreError.message("Solo las transferencias tienen una cuenta de destino.")
            }
        }
        let records = state.accountItems ?? CashUserAccount.defaults
        guard records.count > 0, records.count <= 100,
              Set(records.map(\.id)).count == records.count,
              records.contains(where: { $0.id == CashAccount.cash.rawValue }),
              records.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 55 && ($0.imageData?.count ?? 0) <= 550_000 && ["original", "blanco", "azul", "rojo", "verde", "grafito"].contains($0.colorStyle) }) else {
            throw CashStoreError.message("Las cuentas contienen datos inválidos o falta Efectivo.")
        }
        let knownAccounts = Set(records.map(\.id))
        // V14: impedir ajustes adulterados, duplicados o a cuentas inexistentes.
        let adjustments = state.balanceAdjustments ?? []
        guard adjustments.count <= 20000,
              Set(adjustments.map(\.id)).count == adjustments.count,
              adjustments.allSatisfy({ knownAccounts.contains($0.accountID) &&
                  $0.differenceCents >= -9_000_000_000_000_000 &&
                  $0.differenceCents <= 9_000_000_000_000_000 &&
                  $0.date.timeIntervalSince1970.isFinite }) else {
            throw CashStoreError.message("El historial de ajustes contiene registros inválidos.")
        }
        guard state.operations.allSatisfy({ knownAccounts.contains($0.account.rawValue) && ($0.destination == nil || knownAccounts.contains($0.destination!.rawValue)) }) else {
            throw CashStoreError.message("Hay movimientos vinculados a cuentas que no existen.")
        }
        guard state.openingCents.keys.allSatisfy({ knownAccounts.contains($0) }) else {
            throw CashStoreError.message("Hay saldos de cuentas que no existen.")
        }
        for record in records {
            let account = CashAccount(rawValue: record.id)
            guard abs(Double(state.openingCents[record.id] ?? 0)) <= 9_000_000_000_000_000 else {
                throw CashStoreError.message("El ajuste de saldo excede el máximo admitido.")
            }
            if try currentBalance(account, in: state) < 0 {
                throw CashStoreError.message("Saldo insuficiente en \(record.name). Revisa sus operaciones y su ajuste de saldo.")
            }
        }
        // No rechazamos un gasto registrado con fecha anterior por un saldo
        // histórico reconstruido. Cada cuenta se verifica contra su saldo actual
        // final (arriba). La fecha solo clasifica el movimiento en el calendario.
        // Esto también impide reiniciar saldos al comenzar un nuevo mes.

    }

    // Se usa al leer una copia externa antes de mostrar confirmación al usuario.
    func checkRestoreCandidate(_ candidate: CashLedger) throws {
        guard candidate.schemaVersion == 2 else {
            throw CashStoreError.message("Este archivo pertenece a una versión de datos no compatible.")
        }
        if let categories = candidate.categoryItems {
            guard categories.count <= 2000,
                  categories.allSatisfy({ ($0.iconData?.count ?? 0) <= 400_000 }) else {
                throw CashStoreError.message("El archivo tiene demasiadas categorías o imágenes demasiado grandes.")
            }
        }
        try validate(candidate)
    }

    // Restauración explícita de todas las cuentas y categorías, tras confirmación.
    // 'persist' conserva el archivo anterior en CashLedger.previous.json.
    func restoreBackupLedger(_ incoming: CashLedger) throws {
        try checkRestoreCandidate(incoming)
        var restored = incoming
        if restored.historicalTrackingSince == nil { restored.historicalTrackingSince = Date() }
        try persist(restored)
        ledger = restored
        storageBlocked = false
        notice = "Datos restaurados correctamente. Se recuperaron \(incoming.operations.count) movimientos."
    }

    func categories(for kind: CashKind) -> [CashUserCategory] {
        (ledger.categoryItems ?? CashUserCategory.defaults).filter { $0.kind == kind }
    }

    func category(for operation: CashOperation) -> CashUserCategory? {
        let id = operation.categoryID ?? CashUserCategory.legacyID(for: operation)
        return (ledger.categoryItems ?? CashUserCategory.defaults).first { $0.id == id }
    }

    func saveCategory(_ item: CashUserCategory) throws {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else {
            throw CashStoreError.message("La categoría debe tener entre 1 y 40 caracteres.")
        }
        guard item.iconData == nil || item.iconData!.count <= 400_000 else {
            throw CashStoreError.message("La imagen de la categoría es demasiado grande.")
        }
        var next = ledger
        var categories = next.categoryItems ?? CashUserCategory.defaults
        guard !categories.contains(where: { $0.kind == item.kind && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame && $0.id != item.id }) else {
            throw CashStoreError.message("Ya existe una categoría con ese nombre.")
        }
        var updated = item
        updated.name = name
        if let index = categories.firstIndex(where: { $0.id == item.id }) {
            // La categoría conserva id y tipo al editar: no altera movimientos anteriores.
            guard categories[index].kind == item.kind else {
                throw CashStoreError.message("No se puede cambiar el tipo de una categoría existente.")
            }
            updated.isBuiltIn = categories[index].isBuiltIn
            categories[index] = updated
        } else {
            updated.isBuiltIn = false
            categories.append(updated)
        }
        next.categoryItems = categories
        try commit(next)
    }

    // Nunca se borran movimientos al eliminar una categoría.
    // Si tiene movimientos, se reasignan a "Otros" del mismo tipo con consentimiento.
    func deleteCategory(_ item: CashUserCategory) throws {
        var next = ledger
        var categories = next.categoryItems ?? CashUserCategory.defaults
        guard categories.contains(where: { $0.id == item.id && $0.kind == item.kind }) else {
            throw CashStoreError.message("La categoría ya no existe.")
        }
        guard categories.filter({ $0.kind == item.kind }).count > 1 else {
            throw CashStoreError.message("No se puede borrar la última categoría de este tipo.")
        }
        let affected = next.operations.indices.filter {
            let op = next.operations[$0]
            return (op.categoryID ?? CashUserCategory.legacyID(for: op)) == item.id
        }
        if !affected.isEmpty {
            guard let alternative = categories.first(where: {
                $0.kind == item.kind && $0.id != item.id &&
                $0.name.localizedCaseInsensitiveCompare("Otros") == .orderedSame
            }) else {
                throw CashStoreError.message("Esta categoría tiene movimientos. Primero crea una categoría 'Otros' del mismo tipo para conservarlos.")
            }
            for index in affected {
                next.operations[index].categoryID = alternative.id
                next.operations[index].category = .other
            }
        }
        categories.removeAll { $0.id == item.id }
        next.categoryItems = categories
        try commit(next)
    }

    func categoryLinkedCount(_ category: CashUserCategory) -> Int {
        ledger.operations.filter {
            ($0.categoryID ?? CashUserCategory.legacyID(for: $0)) == category.id
        }.count
    }

    var accountItems: [CashUserAccount] { ledger.accountItems ?? CashUserAccount.defaults }
    var accounts: [CashAccount] { accountItems.map { CashAccount(rawValue: $0.id) } }
    func accountItem(_ account: CashAccount) -> CashUserAccount? {
        accountItems.first { $0.id == account.rawValue }
    }
    func accountName(_ account: CashAccount) -> String {
        accountItem(account)?.name ?? account.name
    }
    func saveAccount(_ record: CashUserAccount, desiredBalance: Int64) throws {
        let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 55 else {
            throw CashStoreError.message("El nombre de la cuenta debe tener entre 1 y 55 caracteres.")
        }
        guard desiredBalance >= 0 && desiredBalance <= 9_000_000_000_000_000 else {
            throw CashStoreError.message("El saldo debe ser positivo o cero y estar dentro del límite.")
        }
        guard (record.imageData?.count ?? 0) <= 550_000 else {
            throw CashStoreError.message("La fotografía es demasiado grande.")
        }
        var next = ledger
        var items = next.accountItems ?? CashUserAccount.defaults
        guard items.count < 100 || items.contains(where: { $0.id == record.id }) else {
            throw CashStoreError.message("Se alcanzó el máximo de 100 cuentas.")
        }
        guard !items.contains(where: { $0.id != record.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw CashStoreError.message("Ya existe una cuenta con ese nombre.")
        }
        var updated = record
        updated.name = name
        if let index = items.firstIndex(where: { $0.id == record.id }) {
            updated.isBuiltIn = items[index].isBuiltIn
            items[index] = updated
        } else {
            updated.isBuiltIn = false
            items.append(updated)
        }
        next.accountItems = items
        let account = CashAccount(rawValue: updated.id)
        let current = try currentBalance(account, in: next)
        // V14: diferencia fechada, sin crear ingresos/gastos ni alterar el pasado.
        let (difference, overflow) = desiredBalance.subtractingReportingOverflow(current)
        guard !overflow else { throw CashStoreError.message("Ajuste de saldo fuera del límite.") }
        if difference != 0 {
            var entries = next.balanceAdjustments ?? []
            entries.append(CashBalanceAdjustment(accountID: updated.id,
                                                differenceCents: difference, date: Date()))
            next.balanceAdjustments = entries
        }
        try commit(next)
    }

    func deleteAccount(_ account: CashAccount) throws {
        guard account != .cash else {
            throw CashStoreError.message("Efectivo es la cuenta principal y no se puede eliminar.")
        }
        guard let record = accountItem(account) else {
            throw CashStoreError.message("La cuenta ya no existe.")
        }
        guard !ledger.operations.contains(where: { $0.account == account || $0.destination == account }),
              !(ledger.balanceAdjustments ?? []).contains(where: { $0.accountID == account.rawValue }),
              balance(account) == 0 else {
            throw CashStoreError.message("Esta cuenta tiene saldo o movimientos. Transfiere el saldo y conserva su historial antes de eliminarla.")
        }
        var next = ledger
        next.accountItems = accountItems.filter { $0.id != record.id }
        next.openingCents.removeValue(forKey: record.id)
        next.balanceAdjustments?.removeAll { $0.accountID == record.id }
        try commit(next)
    }

    func save(_ operation: CashOperation) throws {
        var next = ledger
        if let index = next.operations.firstIndex(where: { $0.id == operation.id }) {
            next.operations[index] = operation
        } else { next.operations.append(operation) }
        try commit(next)
    }

    func delete(_ operation: CashOperation) throws {
        var next = ledger
        next.operations.removeAll { $0.id == operation.id }
        try commit(next)
    }

    func setOpeningBalances(_ newValues: [String: Int64]) throws {
        var next = ledger
        next.openingCents = newValues
        try commit(next)
    }

    func balance(_ account: CashAccount) -> Int64 {
        (try? currentBalance(account, in: ledger)) ?? 0
    }

    // Saldo inicial, flujos y saldo al final del mes elegido.
    func accountMonthSummary(_ account: CashAccount, month: Date) -> CashAccountMonthSummary? {
        try? CashHistoricalBalance.month(account, in: ledger, date: month)
    }

    // Antes de V14 existían ajustes sin fecha; no inventamos su cronología.
    func historicalBalanceIsEstimated(month: Date) -> Bool {
        guard let trackingDate = ledger.historicalTrackingSince else { return true }
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return true }
        return interval.start <= trackingDate
    }
    var totalBalance: Int64 {
        accounts.reduce(Int64(0)) { $0 &+ balance($1) }
    }
    var sorted: [CashOperation] {
        ledger.operations.sorted {
            if $0.date == $1.date { return $0.id.uuidString > $1.id.uuidString }
            return $0.date > $1.date
        }
    }
    func daily(_ date: Date) -> [CashOperation] {
        sorted.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    func monthly(_ date: Date, kind: CashKind? = nil) -> [CashOperation] {
        sorted.filter {
            Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month) && (kind == nil || $0.kind == kind)
        }
    }
    func monthlyTotal(_ kind: CashKind, month: Date) -> Int64 {
        monthly(month, kind: kind).reduce(Int64(0)) { $0 &+ $1.cents }
    }
    func categories(_ kind: CashKind, month: Date) -> [(CashUserCategory, Int64)] {
        categories(for: kind).compactMap { category in
            let value = monthly(month, kind: kind)
                .filter { ($0.categoryID ?? CashUserCategory.legacyID(for: $0)) == category.id }
                .reduce(Int64(0)) { $0 &+ $1.cents }
            return value > 0 ? (category, value) : nil
        }.sorted { $0.1 > $1.1 }
    }
    func biggest(_ kind: CashKind, month: Date) -> CashOperation? {
        monthly(month, kind: kind).max(by: { $0.cents < $1.cents })
    }
}

enum CashStoreError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
