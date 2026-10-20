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
        // CASH V9: exporta explícitamente las categorías aunque provengan del catálogo inicial.
        // Las personalizadas ya viven dentro de ledger.categoryItems, con sus imágenes en iconData.
        // No se sustituyen las categorías modificadas por el usuario ni se cambia el almacén del iPhone.
        var snapshot = ledger
        if snapshot.categoryItems == nil {
            snapshot.categoryItems = CashUserCategory.defaults
        }
        // V10: incluir las cinco cuentas de origen incluso si siguen sin editarse.
        if snapshot.accountItems == nil {
            snapshot.accountItems = CashUserAccount.defaults
        }
        guard let categorias = snapshot.categoryItems,
              categorias.count <= 2000,
              categorias.allSatisfy({ ($0.iconData?.count ?? 0) <= 400_000 }) else {
            throw CashStoreError.message("No se pueden exportar categorías o imágenes inválidas.")
        }
        let encodedLedger = try stableLedgerData(snapshot)
        let document = CashPortableBackup(format: formatName, backupVersion: 1,
                                          createdAt: Date(), ledger: snapshot,
                                          ledgerSHA256: digest(encodedLedger))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contents = try encoder.encode(document)
        guard contents.count < maxFileBytes else {
            throw CashStoreError.message("El archivo es demasiado grande. Reduce las imágenes personalizadas antes de exportar.")
        }
        // V9: comprueba ANTES de compartir que el JSON se pueda decodificar y que
        // conserva cada categoría, símbolo, imagen, movimiento y saldo original.
        let comprobacion = try JSONDecoder().decode(CashPortableBackup.self, from: contents)
        let led = comprobacion.ledger
        guard led.categoryItems == snapshot.categoryItems,
              led.operations == snapshot.operations,
              led.openingCents == snapshot.openingCents,
              led.balanceAdjustments == snapshot.balanceAdjustments,
              led.historicalTrackingSince == snapshot.historicalTrackingSince,
              led.accountItems == snapshot.accountItems,
              comprobacion.ledgerSHA256 == digest(try stableLedgerData(led)) else {
            throw CashStoreError.message("El respaldo no superó la comprobación de integridad; no se compartió ningún archivo.")
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
