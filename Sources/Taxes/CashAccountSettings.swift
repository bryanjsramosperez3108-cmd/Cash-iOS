import SwiftUI
import UIKit

// V10: las cuentas son editables sin cambiar sus identificadores ni los movimientos.
struct CashAccountManager: View {
    @ObservedObject var store: CashStore
    @State private var editing: CashUserAccount?
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(store.accountItems) { profile in
                    Button { editing = profile } label: {
                        HStack(spacing: 12) {
                            CashAccountAvatar(account: CashAccount(rawValue: profile.id), profile: profile)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Disponible: \(CashMoney.formatted(store.balance(CashAccount(rawValue: profile.id))))")
                                    .font(.caption)
                                    .foregroundStyle(CashTheme.muted)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "pencil")
                                .foregroundStyle(CashTheme.blue)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Mis cuentas")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashTheme.background)
        .navigationTitle("Añadir cuentas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = CashUserAccount(id: "custom.\(UUID().uuidString)", name: "", colorStyle: "azul")
                } label: {
                    Label("Nueva cuenta", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { profile in
            CashAccountEditor(store: store, original: profile)
        }
        .alert("No se pudo completar", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("Entendido") { errorText = nil } }
        message: { Text(errorText ?? "") }
    }
}

private struct CashAccountAvatar: View {
    let account: CashAccount
    let profile: CashUserAccount

    var body: some View {
        Group {
            if let data = profile.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if !account.assetName.isEmpty && account != .cash {
                CashBrandImage(filename: account.assetName, maxHeight: 45)
            } else {
                Image(systemName: account.symbol).font(.title2)
                    .foregroundStyle(CashTheme.blue)
            }
        }
        .frame(width: 55, height: 48)
        .padding(3)
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
        .accessibilityHidden(true)
    }
}

struct CashAccountEditor: View {
    @ObservedObject var store: CashStore
    let original: CashUserAccount
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String
    @State private var imageData: Data?
    @State private var colorStyle: String
    @State private var showingPhotos = false
    @State private var selectedPhoto: UIImage?
    @State private var photoDraft: CashPickedAccountPhoto?
    @State private var imageFillsCard: Bool
    @State private var wantsDeletion = false
    @State private var pendingSave = false
    @State private var errorText: String?
    @State private var saving = false

    private static let styles: [(String, String)] = [
        ("original", "Original"),
        ("blanco", "Blanco"),
        ("azul", "Azul"),
        ("rojo", "Rojo"),
        ("verde", "Verde"),
        ("grafito", "Grafito")
    ]

    init(store: CashStore, original: CashUserAccount) {
        self.store = store
        self.original = original
        _name = State(initialValue: original.name)
        _amount = State(initialValue: CashMoney.editable(store.balance(CashAccount(rawValue: original.id))))
        _imageData = State(initialValue: original.imageData)
        _colorStyle = State(initialValue: original.colorStyle)
        _imageFillsCard = State(initialValue: original.imageFillsCard ?? false)
    }

    private var account: CashAccount { CashAccount(rawValue: original.id) }
    private var isExisting: Bool { store.accountItems.contains(where: { $0.id == original.id }) }
    private var parsedAmount: Int64? { CashMoney.parse(amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identidad de la cuenta") {
                    TextField("Nombre de la cuenta", text: $name)
                        .textInputAutocapitalization(.words)
                    preview
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    Button {
                        showingPhotos = true
                    } label: {
                        Label(imageData == nil ? "Elegir fotografía" : "Cambiar fotografía", systemImage: "photo.on.rectangle")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.photoLibrary))
                    if imageData != nil {
                        Toggle("Usar fotografía como fondo completo", isOn: $imageFillsCard)
                            .tint(CashTheme.blue)
                        Button("Ajustar encuadre y zoom", systemImage: "arrow.up.left.and.arrow.down.right") {
                            // La imagen ya recortada puede reajustarse tantas veces como se necesite.
                            if let data = imageData, let image = UIImage(data: data) {
                                photoDraft = CashPickedAccountPhoto(image: image)
                            }
                        }
                    }
                    if imageData != nil {
                        Button("Quitar fotografía personalizada", systemImage: "xmark.circle") {
                            imageData = nil
                        }
                    }
                    Picker("Color de la tarjeta", selection: $colorStyle) {
                        ForEach(Self.styles, id: \.0) { style in
                            Text(style.1).tag(style.0)
                        }
                    }
                }
                Section {
                    HStack(spacing: 10) {
                        Text("L").font(.title2.bold()).foregroundStyle(CashTheme.blue)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                } header: {
                    Text("Saldo disponible")
                } footer: {
                    Text("Ajustar el saldo no crea ingresos ni gastos y conserva el historial.")
                }
                if isExisting && account != .cash {
                    Section {
                        Button(role: .destructive) { wantsDeletion = true } label: {
                            Label("Eliminar cuenta", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                        }
                    } footer: {
                        Text("Solo puede eliminarse una cuenta sin saldo y sin operaciones asociadas.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CashTheme.background)
            .navigationTitle(isExisting ? "Editar cuenta" : "Nueva cuenta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") { checkAndSave() }
                        .fontWeight(.semibold)
                        .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedAmount == nil)
                }
            }
            .sheet(isPresented: $showingPhotos, onDismiss: {
                if let image = selectedPhoto {
                    selectedPhoto = nil
                    photoDraft = CashPickedAccountPhoto(image: image)
                }
            }) {
                CashPhotoLibraryPicker { image in
                    // Guardar el original solo temporalmente; la pantalla de zoom
                    // lo recorta y compacta ANTES de persistirlo.
                    selectedPhoto = image
                }
            }
            .sheet(item: $photoDraft) { draft in
                CashAccountPhotoAdjuster(image: draft.image,
                                         initialFullCard: imageFillsCard) { data, fullCard in
                    imageData = data
                    imageFillsCard = fullCard
                }
            }
            .confirmationDialog("¿Eliminar esta cuenta?", isPresented: $wantsDeletion, titleVisibility: .visible) {
                Button("Eliminar definitivamente", role: .destructive) { deleteAccount() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("La cuenta solo se eliminará si su saldo es cero y no tiene ingresos, gastos ni transferencias. No se borrarán movimientos.")
            }
            .confirmationDialog("¿Ajustar el saldo disponible?", isPresented: $pendingSave, titleVisibility: .visible) {
                Button("Guardar cuenta y ajustar saldo") { save() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Se actualizará el saldo visible sin crear ingresos ni gastos ni modificar las operaciones ya registradas.")
            }
            .alert("Revisa la cuenta", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) { Button("Entendido") { errorText = nil } }
            message: { Text(errorText ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private var preview: some View {
        CashEditableAccountPreview(account: account,
                                   name: name,
                                   amount: amount,
                                   imageData: imageData,
                                   style: colorStyle,
                                   imageFillsCard: imageFillsCard)
    }

    private func deleteAccount() {
        do {
            try store.deleteAccount(account)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func checkAndSave() {
        guard let value = parsedAmount, value >= 0 else {
            errorText = "Introduce un saldo válido."; return
        }
        if isExisting && value != store.balance(account) {
            pendingSave = true
        } else { save() }
    }

    private func save() {
        guard let value = parsedAmount else { errorText = "Saldo inválido."; return }
        saving = true
        do {
            var changed = original
            changed.name = name
            changed.imageData = imageData
            changed.imageFillsCard = imageFillsCard
            changed.colorStyle = colorStyle
            try store.saveAccount(changed, desiredBalance: value)
            dismiss()
        } catch {
            saving = false
            errorText = error.localizedDescription
        }
    }
}
