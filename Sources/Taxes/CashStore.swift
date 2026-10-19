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
                ledger = decoded
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
        try validate(next)
        try persist(next)
        ledger = next
    }

    // Aritmética exacta con comprobación de desbordamientos.
    private func checkedSum(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        if overflow { throw CashStoreError.message("El importe excede el límite permitido.") }
        return value
    }

    private func currentBalance(_ account: CashAccount, in state: CashLedger) throws -> Int64 {
        var result = state.openingCents[account.rawValue] ?? 0
        for operation in state.operations {
            switch operation.kind {
            case .income where operation.account == account:
                result = try checkedSum(result, operation.cents)
            case .expense where operation.account == account:
                result = try checkedSum(result, -operation.cents)
            case .transfer:
                if operation.account == account { result = try checkedSum(result, -operation.cents) }
                if operation.destination == account { result = try checkedSum(result, operation.cents) }
            default: break
            }
        }
        return result
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
        for account in CashAccount.allCases {
            guard (state.openingCents[account.rawValue] ?? 0) <= 9_000_000_000_000_000 else {
                throw CashStoreError.message("El saldo inicial de \(account.name) excede el límite permitido.")
            }
            guard (state.openingCents[account.rawValue] ?? 0) >= 0 else {
                throw CashStoreError.message("El saldo inicial de \(account.name) no puede ser negativo.")
            }
            if try currentBalance(account, in: state) < 0 {
                throw CashStoreError.message("Saldo insuficiente en \(account.name) según su balance actual. Revisa ingresos, gastos y transferencias.")
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
        try persist(incoming)
        ledger = incoming
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

    func deleteCategory(_ item: CashUserCategory) throws {
        guard !item.isBuiltIn else {
            throw CashStoreError.message("Las categorías originales se pueden editar, pero no eliminar.")
        }
        guard !ledger.operations.contains(where: { ($0.categoryID ?? CashUserCategory.legacyID(for: $0)) == item.id }) else {
            throw CashStoreError.message("Esta categoría tiene movimientos asociados. Puedes cambiar su nombre o imagen, pero no eliminarla.")
        }
        var next = ledger
        next.categoryItems = (next.categoryItems ?? CashUserCategory.defaults).filter { $0.id != item.id }
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
    var totalBalance: Int64 {
        CashAccount.allCases.reduce(Int64(0)) { $0 &+ balance($1) }
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
