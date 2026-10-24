import Foundation

/// Anexa a una copia JSON del respaldo de CASH el catálogo completo que BUDGET necesita.
/// El objeto `ledger` y el archivo principal CashLedger.json NO se modifican.
/// La aplicación original debe conservar su formato de restauración intacto.
enum CashBudgetBackupEnricher {
    static func enhanceExport(at url: URL, ledger: CashLedger) throws {
        let originalBytes = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: originalBytes) as? [String: Any] else {
            throw NSError(domain: "CashBudgetExport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "El respaldo no es un objeto JSON."])
        }
        // Se obtiene el modelo real desde su serialización, sin depender de nombres de propiedades Swift.
        let ledgerBytes = try JSONEncoder().encode(ledger)
        guard let stored = try JSONSerialization.jsonObject(with: ledgerBytes) as? [String: Any] else { return }
        let records = extractRecords(stored)
        let known = records.reduce(into: [String: [String: Any]]()) { result, record in
            let id = string(record, keys: ["id", "uuid", "categoryId", "categoryID", "rawValue", "key"])
            guard !id.isEmpty else { return }
            // La última ficha de una categoría personalizada prevalece sobre nombres genéricos.
            result[canonical(id)] = normalizedCategory(record, identifier: id)
        }
        var catalog = known
        for operation in operations(stored) {
            let type = string(operation, keys: ["kind", "type", "operationType", "movementType"]).lowercased()
            let kind: String = type.contains("income") || type.contains("ingreso") ? "income" :
                (type.contains("expense") || type.contains("gasto") ? "expense" : "")
            let baseID = string(operation, keys: ["categoryId", "categoryID", "category", "categoryRawValue"])
            let customID = string(operation, keys: ["userCategoryId", "userCategoryID", "customCategoryId", "customCategoryID", "incomeCategoryId", "incomeCategoryID", "selectedCategoryId"])
            for id in [baseID, customID] where !id.isEmpty {
                let key = canonical(id)
                if catalog[key] == nil {
                    let title = displayForBuiltin(id)
                    catalog[key] = ["id": id, "name": title, "displayName": title,
                                    "kind": kind, "icon": defaultIcon(for: id, name: title)]
                }
                if !kind.isEmpty, var entry = catalog[key] {
                    let present = string(entry, keys: ["kind", "type"]).lowercased()
                    if present.isEmpty { entry["kind"] = kind; catalog[key] = entry }
                }
            }
        }
        let values = catalog.values.sorted {
            string($0, keys: ["name"]).localizedStandardCompare(string($1, keys: ["name"])) == .orderedAscending
        }
        let income = values.filter { string($0, keys: ["kind"]).lowercased().contains("income") }
        let expense = values.filter { string($0, keys: ["kind"]).lowercased().contains("expense") }
        // Metadatos extra en el contenedor EXTERIOR: Codable ignora las claves adicionales
        // al restaurar `CashPortableBackup`. No se altera ni recalcula su checksum del ledger.
        root["budgetExportVersion"] = 2
        root["budgetCategoriesCount"] = values.count
        root["categoryDefinitions"] = values
        root["incomeCategories"] = income
        root["expenseCategories"] = expense
        // Asociaciones UUID -> nombre/icono. Las listas anteriores son la fuente principal.
        root["budgetCategoryCatalog"] = Dictionary(uniqueKeysWithValues: values.compactMap { element -> (String, [String: Any])? in
            let id = string(element, keys: ["id"])
            return id.isEmpty ? nil : (id, element)
        })
        let enriched = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try enriched.write(to: url, options: .atomic)
    }

    private static func extractRecords(_ ledger: [String: Any]) -> [[String: Any]] {
        let keys = ["categories", "incomeCategories", "expenseCategories", "categoryCatalog", "categoryDefinitions", "expenseCategoryCatalog", "incomeCategoryCatalog", "userCategories", "customCategories", "userIncomeCategories", "userExpenseCategories"]
        var result: [[String: Any]] = []
        for key in keys {
            guard let value = field(ledger, [key]) else { continue }
            if let items = value as? [[String: Any]] { result += items }
            else if let items = value as? [String: Any] {
                for (id, entry) in items {
                    if var dict = entry as? [String: Any] {
                        if field(dict, ["id", "uuid", "categoryId"]) == nil { dict["id"] = id }
                        result.append(dict)
                    } else if let title = entry as? String {
                        result.append(["id": id, "name": title])
                    }
                }
            }
        }
        return result
    }

    private static func normalizedCategory(_ record: [String: Any], identifier id: String) -> [String: Any] {
        let title = string(record, keys: ["name", "displayName", "title", "nombre", "label", "customName", "categoryName"])
        let name = title.isEmpty ? displayForBuiltin(id) : title
        let rawType = string(record, keys: ["kind", "type", "categoryType", "movementType"]).lowercased()
        let kind = rawType.contains("income") || rawType.contains("ingreso") || id.lowercased().hasPrefix("income.") ? "income" :
            (rawType.contains("expense") || rawType.contains("gasto") || id.lowercased().hasPrefix("expense.") ? "expense" : "")
        let icon = string(record, keys: ["sfSymbol", "symbol", "symbolName", "systemImage", "icon", "iconName", "iconSymbol", "imageName", "iconSystemName"])
        var normalized: [String: Any] = [
            "id": id, "name": name, "displayName": name,
            "icon": icon.isEmpty ? defaultIcon(for: id, name: name) : icon,
            "sfSymbol": icon.isEmpty ? defaultIcon(for: id, name: name) : icon,
            "kind": kind
        ]
        if let color = field(record, ["colorHex", "hexColor", "iconColor", "color", "tintHex"]) as? String {
            normalized["colorHex"] = color
        }
        return normalized
    }

    private static func operations(_ ledger: [String: Any]) -> [[String: Any]] {
        for key in ["operations", "movements", "transactions", "entries"] {
            if let records = field(ledger, [key]) as? [[String: Any]] { return records }
        }
        return []
    }

    private static func field(_ object: [String: Any], _ keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key], !(value is NSNull) { return value }
            if let original = object.keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }),
               let value = object[original], !(value is NSNull) { return value }
        }
        return nil
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String {
        guard let raw = field(object, keys) else { return "" }
        if let value = raw as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = raw as? NSNumber { return value.stringValue }
        if let record = raw as? [String: Any] {
            return string(record, keys: ["rawValue", "id", "name", "value", "systemName", "symbolName"])
        }
        return ""
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func displayForBuiltin(_ identifier: String) -> String {
        let value = identifier.lowercased()
        let known: [String: String] = [
            "income.salary": "Salario", "income.gift": "Regalo", "income.other": "Otros",
            "expense.food": "Alimentación", "expense.order": "Otros", "expense.other": "Otros",
            "expense.leisure": "Entretenimiento", "expense.clothing": "Ropa",
            "expense.transport": "Transporte", "expense.health": "Salud",
            "expense.shopping": "Compras", "expense.tithe": "Diezmo"
        ]
        if let name = known[value] { return name }
        // Un UUID sin catálogo NO se transforma en un nombre inventado.
        let compact = identifier.replacingOccurrences(of: "-", with: "")
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if compact.count == 32 && compact.unicodeScalars.allSatisfy({ hex.contains($0) }) {
            return "Categoría sin nombre"
        }
        let raw = identifier.replacingOccurrences(of: "income.", with: "")
            .replacingOccurrences(of: "expense.", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return raw.isEmpty ? "Sin categoría" : raw.prefix(1).uppercased() + raw.dropFirst()
    }

    private static func defaultIcon(for id: String, name: String) -> String {
        let key = (id + " " + name).lowercased()
        if key.contains("bodega") { return "cart.fill" }
        if key.contains("bus") { return "bus.fill" }
        if key.contains("comput") { return "laptopcomputer" }
        if key.contains("recarga") { return "dollarsign.square.fill" }
        if key.contains("regalo") || key.contains("gift") { return "gift.fill" }
        if key.contains("venta") { return "bag.fill" }
        if key.contains("sueldo") || key.contains("salary") { return "briefcase.fill" }
        if key.contains("ahorro") { return "building.columns.fill" }
        return "tag.fill"
    }
}
