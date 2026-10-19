import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

// Respaldo portátil sin conexión a bancos ni a servidores.
// Incluye todas las cuentas, movimientos y categorías personalizadas.
struct CashPortableBackup: Codable {
    let format: String
    let backupVersion: Int
    let createdAt: Date
    let ledger: CashLedger
    let ledgerSHA256: String
}

struct CashBackupFile: Identifiable {
    let id = UUID()
    let url: URL
}

enum CashBackupService {
    private static let formatName = "Cash.PortableBackup"
    private static let maxFileBytes = 40_000_000

    private static func stableLedgerData(_ ledger: CashLedger) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ledger)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func createFile(from ledger: CashLedger) throws -> URL {
        guard ledger.schemaVersion == 2 else {
            throw CashStoreError.message("La versión de tus datos no es compatible con las copias de seguridad.")
        }
        let encodedLedger = try stableLedgerData(ledger)
        let document = CashPortableBackup(format: formatName, backupVersion: 1,
                                          createdAt: Date(), ledger: ledger,
                                          ledgerSHA256: digest(encodedLedger))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contents = try encoder.encode(document)
        guard contents.count < maxFileBytes else {
            throw CashStoreError.message("El archivo es demasiado grande. Reduce las imágenes personalizadas antes de exportar.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "Cash-Respaldo-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try contents.write(to: url, options: .atomic)
        return url
    }

    static func load(_ url: URL) throws -> CashPortableBackup {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.intValue > maxFileBytes {
            throw CashStoreError.message("El archivo supera el tamaño máximo permitido (40 MB).")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maxFileBytes else {
            throw CashStoreError.message("El archivo supera el tamaño máximo permitido.")
        }
        let document = try JSONDecoder().decode(CashPortableBackup.self, from: data)
        guard document.format == formatName, document.backupVersion == 1 else {
            throw CashStoreError.message("Este archivo no es una copia de seguridad compatible de Cash.")
        }
        let digestActual = try digest(stableLedgerData(document.ledger))
        guard digestActual == document.ledgerSHA256 else {
            throw CashStoreError.message("El respaldo está alterado o dañado. No se restauró ningún dato.")
        }
        return document
    }
}

struct CashBackupShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
