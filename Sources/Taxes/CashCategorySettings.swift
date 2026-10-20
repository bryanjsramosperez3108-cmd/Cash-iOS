import SwiftUI
import UIKit
import UniformTypeIdentifiers
// Iconos elegidos desde Fotos: comprimidos y guardados dentro del libro contable.
// Selector de Fotos mediante UIKit, sin dependencia de PhotosPickerItem.
struct CashCategoryIcon: View {
    let category: CashUserCategory?
    var fallback = "tag.fill"

    var body: some View {
        Group {
            if let data = category?.iconData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: category?.symbol ?? fallback)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
        }
        .accessibilityLabel(category?.name ?? "Categoría")
    }
}

struct CashSettings: View {
    @ObservedObject var store: CashStore
    @Environment(\.dismiss) private var dismiss
    @State private var sharingBackup: CashBackupFile?
    @State private var importingBackup = false
    @State private var pendingRestore: CashPortableBackup?
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Administrar categorías") {
                    NavigationLink {
                        CashCategoryManager(store: store, kind: .income)
                    } label: {
                        Label("Categorías de ingresos", systemImage: "arrow.down.left.circle.fill")
                            .foregroundStyle(CashTheme.green)
                    }
                    NavigationLink {
                        CashCategoryManager(store: store, kind: .expense)
                    } label: {
                        Label("Categorías de gastos", systemImage: "arrow.up.right.circle.fill")
                            .foregroundStyle(CashTheme.red)
                    }
                    NavigationLink {
                        CashCategoryManager(store: store, kind: .transfer)
                    } label: {
                        Label("Categorías de transferencias", systemImage: "arrow.left.arrow.right.circle.fill")
                            .foregroundStyle(CashTheme.blue)
                    }
                }
                Section("Añadir cuentas") {
                    NavigationLink {
                        CashAccountManager(store: store)
                    } label: {
                        Label("Administrar mis cuentas", systemImage: "building.columns.circle.fill")
                            .foregroundStyle(CashTheme.blue)
                    }
                    Text("Crea nuevas cuentas y modifica el nombre, la imagen y el saldo disponible de las existentes.")
                        .font(.caption).foregroundStyle(CashTheme.muted)
                }
                Section {
                    ForEach(store.accounts) { account in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.accountName(account))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(CashTheme.muted)
                            Text("SALDO DISPONIBLE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(CashTheme.blue)
                            Text(CashMoney.formatted(store.balance(account)))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Mis cuentas")
                }
                Section("Recordatorios") {
                    NavigationLink {
                        CashReminderSettings()
                    } label: {
                        Label("Notificaciones diarias", systemImage: "bell.badge.fill")
                            .foregroundStyle(CashTheme.blue)
                    }
                }
                Section {
                    Button(action: createBackup) {
                        Label("Crear copia de seguridad", systemImage: "square.and.arrow.up")
                    }
                    let categoriasRespaldo = store.ledger.categoryItems ?? CashUserCategory.defaults
                    Text("Categorías incluidas en el respaldo: \(categoriasRespaldo.filter { $0.kind == .income }.count) de ingresos, \(categoriasRespaldo.filter { $0.kind == .expense }.count) de gastos y \(categoriasRespaldo.filter { $0.kind == .transfer }.count) de transferencias. Imágenes personalizadas: \(categoriasRespaldo.filter { $0.iconData != nil }.count).")
                        .font(.caption)
                        .foregroundStyle(CashTheme.muted)
                    Button {
                        importingBackup = true
                    } label: {
                        Label("Restaurar datos desde archivo", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Copias de seguridad")
                } footer: {
                    Text("El JSON conserva las categorías de ingresos, gastos y transferencias, incluidos sus nombres, símbolos e imágenes personalizadas. Contiene también saldos y movimientos. No está cifrado: guárdalo de forma privada. Restaurar reemplaza todos los datos actuales.")
                }
                Section("Información") {
                    LabeledContent("Aplicación", value: "Cash")
                    LabeledContent("Moneda", value: "Lempira hondureño (HNL)")
                    LabeledContent("Movimientos", value: "\(store.ledger.operations.count)")
                    Text("© 2026 Bryan Ramos. Todos los derechos reservados.")
                        .font(.caption).foregroundStyle(CashTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CashTheme.background)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } } }
            .sheet(item: $sharingBackup) { file in
                CashBackupShareSheet(fileURL: file.url)
            }
            .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
                Task { @MainActor in
                    do {
                        let url = try result.get()
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let loaded = try CashBackupService.load(url)
                        try store.checkRestoreCandidate(loaded.ledger)
                        // Esperar a que se cierre el selector de Archivos antes de abrir confirmación.
                        try? await Task.sleep(for: .milliseconds(350))
                        pendingRestore = loaded
                    } catch {
                        backupError = error.localizedDescription
                    }
                }
            }
            .confirmationDialog("¿Restaurar los datos?", isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ), titleVisibility: .visible) {
                Button("Cancelar", role: .cancel) { pendingRestore = nil }
                Button("Restaurar datos y sustituir los actuales", role: .destructive) {
                    guard let incoming = pendingRestore else { return }
                    pendingRestore = nil
                    do { try store.restoreBackupLedger(incoming.ledger) }
                    catch { backupError = error.localizedDescription }
                }
            } message: {
                if let incoming = pendingRestore {
                    Text("Copia: \(incoming.createdAt.formatted(date: .abbreviated, time: .shortened)). \(incoming.ledger.operations.count) movimientos. Reemplazará TODAS las cuentas, operaciones y categorías de este iPhone. Cash guardará primero una copia local del archivo anterior. ¿Continuar?")
                }
            }
            .alert("No se pudo completar la operación", isPresented: Binding(
                get: { backupError != nil }, set: { if !$0 { backupError = nil } }
            )) {
                Button("Entendido") { backupError = nil }
            } message: {
                Text(backupError ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func createBackup() {
        do {
            let url = try CashBackupService.createFile(from: store.ledger)
            sharingBackup = CashBackupFile(url: url)
        } catch { backupError = error.localizedDescription }
    }
}

struct CashCategoryManager: View {
    @ObservedObject var store: CashStore
    let kind: CashKind
    @State private var editing: CashUserCategory?
    @State private var deleting: CashUserCategory?
    @State private var deletionError: String?
    private var title: String {
        switch kind {
        case .income: "Categorías de ingresos"
        case .expense: "Categorías de gastos"
        case .transfer: "Categorías de transferencias"
        }
    }
    var body: some View {
        List {
            Section {
                ForEach(store.categories(for: kind)) { item in
                    Button { editing = item } label: {
                        HStack(spacing: 12) {
                            CashCategoryIcon(category: item)
                                .foregroundStyle(CashTheme.color(kind))
                                .background(CashTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                            Text(item.name).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(CashTheme.muted)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleting = item } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("Desliza una categoría a la izquierda para eliminarla. Sus movimientos se conservarán y, si es necesario, pasarán a 'Otros'.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = CashUserCategory(id: UUID().uuidString, kind: kind,
                                               name: "", symbol: "tag.fill")
                } label: { Label("Añadir categoría", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { item in
            CashCategoryEditor(store: store, item: item)
        }
        .confirmationDialog("¿Eliminar categoría?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Cancelar", role: .cancel) { deleting = nil }
            Button("Eliminar categoría", role: .destructive) {
                guard let item = deleting else { return }
                deleting = nil
                do { try store.deleteCategory(item) }
                catch { deletionError = error.localizedDescription }
            }
        } message: {
            if let item = deleting {
                let count = store.categoryLinkedCount(item)
                Text(count == 0 ? "Solo se eliminará la categoría; no se borrará ningún movimiento." : "Se conservarán los \(count) movimientos y se reasignarán a la categoría 'Otros' del mismo tipo. Esta acción no se puede deshacer.")
            }
        }
        .alert("No se pudo eliminar", isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
        )) { Button("Entendido") { deletionError = nil } }
        message: { Text(deletionError ?? "") }
    }
}

struct CashCategoryEditor: View {
    @ObservedObject var store: CashStore
    let item: CashUserCategory
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var iconData: Data?
    @State private var showingPhotoLibrary = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    @State private var saving = false

    // Símbolos SF Symbols, agrupados por actividades habituales de finanzas.
    private let symbols: [String] = [
        "tag.fill", "number", "star.fill", "heart.fill", "gift.fill", "crown.fill",
        "dollarsign.circle.fill", "banknote.fill", "creditcard.fill", "wallet.pass.fill", "building.columns.fill", "chart.line.uptrend.xyaxis",
        "briefcase.fill", "person.crop.circle.fill", "person.2.fill", "graduationcap.fill", "doc.text.fill", "pencil.and.list.clipboard",
        "bag.fill", "cart.fill", "basket.fill", "storefront.fill", "shippingbox.fill", "barcode",
        "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill", "birthday.cake.fill", "wineglass.fill", "carrot.fill",
        "car.fill", "bus.fill", "tram.fill", "bicycle", "airplane", "fuelpump.fill",
        "house.fill", "building.2.fill", "bed.double.fill", "sofa.fill", "lamp.desk.fill", "key.fill",
        "bolt.fill", "lightbulb.fill", "wifi", "iphone.gen3", "desktopcomputer", "tv.fill",
        "cross.case.fill", "stethoscope", "pills.fill", "bandage.fill", "figure.walk", "dumbbell.fill",
        "gamecontroller.fill", "music.note", "film.fill", "ticket.fill", "book.fill", "camera.fill",
        "pawprint.fill", "leaf.fill", "tree.fill", "sun.max.fill", "drop.fill", "flame.fill",
        "hammer.fill", "wrench.adjustable.fill", "paintbrush.fill", "scissors", "bag.badge.plus", "checkmark.seal.fill",
        "arrow.left.arrow.right", "arrow.up.right", "arrow.down.left", "arrow.triangle.2.circlepath", "repeat", "calendar",
        "globe.americas.fill", "location.fill", "map.fill", "envelope.fill", "phone.fill", "bell.fill",
        "hand.raised.fill", "hands.clap.fill", "shield.lefthalf.filled", "lock.fill", "flag.fill", "sparkles",
        "pencil.circle.fill", "paperplane.fill", "paperclip", "doc.fill", "doc.richtext", "folder.fill",
        "tray.full.fill", "archivebox.fill", "bookmark.fill", "note.text", "list.bullet.clipboard.fill", "text.book.closed.fill",
        "newspaper.fill", "magazine.fill", "book.closed.fill", "graduationcap.circle.fill", "person.crop.rectangle.stack.fill", "person.3.fill",
        "person.fill.checkmark", "person.badge.plus", "figure.run", "figure.yoga", "figure.pool.swim", "figure.dance",
        "sportscourt.fill", "soccerball", "basketball.fill", "baseball.fill", "tennisball.fill", "trophy.fill",
        "medal.fill", "flag.checkered", "theatermasks.fill", "headphones", "hifispeaker.fill", "mic.fill",
        "guitars.fill", "radio.fill", "music.mic", "photo.fill", "camera.aperture", "video.fill",
        "film.stack.fill", "play.rectangle.fill", "television.fill", "laptopcomputer", "keyboard.fill", "printer.fill",
        "externaldrive.fill", "server.rack", "wifi.router.fill", "battery.100percent", "powerplug.fill", "bolt.car.fill",
        "car.side.fill", "car.2.fill", "suv.side.fill", "truck.box.fill", "ferry.fill", "sailboat.fill",
        "figure.walk.motion", "map.pin.and.ellipse", "mappin.circle.fill", "location.circle.fill", "building.2.crop.circle.fill", "house.lodge.fill",
        "house.circle.fill", "door.left.hand.closed", "chair.lounge.fill", "washer.fill", "refrigerator.fill", "oven.fill",
        "frying.pan.fill", "popcorn.fill", "fork.knife.circle.fill", "mug.fill", "water.waves", "fish.fill",
        "dog.fill", "cat.fill", "tortoise.fill", "bird.fill", "ant.fill", "ladybug.fill",
        "camera.macro", "leaf.circle.fill", "globe.europe.africa.fill", "globe.asia.australia.fill", "cloud.sun.fill", "cloud.rain.fill",
        "snowflake", "moon.stars.fill", "umbrella.fill", "wind", "thermometer.sun.fill", "sun.horizon.fill",
        "mountain.2.fill", "tent.fill", "backpack.fill", "suitcase.rolling.fill", "creditcard.circle.fill", "dollarsign.square.fill",
        "eurosign.circle.fill", "sterlingsign.circle.fill", "yensign.circle.fill", "percent", "percent.circle.fill", "cart.badge.plus",
        "shippingbox.circle.fill", "giftcard.fill", "tag.circle.fill", "barcode.viewfinder", "qrcode", "cash.register",
        "receipt", "checkmark.circle.fill", "checkmark.square.fill", "xmark.shield.fill", "key.horizontal.fill", "lock.shield.fill",
        "heart.text.square.fill", "heart.circle.fill", "medical.thermometer.fill", "syringe.fill", "facemask.fill", "pills.circle.fill",
        "cross.vial.fill", "figure.mind.and.body", "brain.head.profile", "allergens.fill", "bed.double.circle.fill", "clock.fill",
        "alarm.fill", "timer", "hourglass", "calendar.badge.clock", "calendar.badge.plus", "calendar.circle.fill",
        "clock.arrow.circlepath", "arrowshape.turn.up.right.fill", "arrowshape.turn.up.left.fill", "arrow.up.right.circle.fill", "arrow.down.left.circle.fill", "arrow.left.arrow.right.circle.fill",
        "arrow.triangle.2.circlepath.circle.fill", "arrow.uturn.backward.circle.fill", "arrow.clockwise.circle.fill", "chart.bar.fill", "chart.pie.fill", "chart.xyaxis.line",
        "chart.line.uptrend.xyaxis.circle.fill", "chart.line.downtrend.xyaxis", "building.columns.circle.fill", "wallet.bifold.fill", "centsign.circle.fill", "volleyball.fill",
        "sparkles.rectangle.stack.fill"
    ]

    init(store: CashStore, item: CashUserCategory) {
        self.store = store
        self.item = item
        _name = State(initialValue: item.name)
        _symbol = State(initialValue: item.symbol)
        _iconData = State(initialValue: item.iconData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identidad de la categoría") {
                    HStack(spacing: 14) {
                        CashCategoryIcon(category: CashUserCategory(id: item.id, kind: item.kind,
                                                                   name: name, symbol: symbol, iconData: iconData))
                            .foregroundStyle(CashTheme.color(item.kind))
                        TextField("Nombre de la categoría", text: $name)
                            .textInputAutocapitalization(.words)
                    }
                    Button {
                        showingPhotoLibrary = true
                    } label: {
                        Label(iconData == nil ? "Elegir imagen de Fotos" : "Cambiar imagen", systemImage: "photo.on.rectangle")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.photoLibrary))
                    if iconData != nil {
                        Button("Quitar imagen personalizada", systemImage: "xmark.circle") { iconData = nil }
                    }
                }
                Section("O elegir un símbolo") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 13) {
                        ForEach(symbols, id: \.self) { suggestion in
                            Button {
                                symbol = suggestion
                                iconData = nil
                            } label: {
                                Image(systemName: suggestion)
                                    .font(.system(size: 21))
                                    .foregroundStyle(symbol == suggestion && iconData == nil ? .white : CashTheme.muted)
                                    .frame(maxWidth: .infinity, minHeight: 43)
                                    .background(symbol == suggestion && iconData == nil ? CashTheme.blue : CashTheme.raised,
                                                in: RoundedRectangle(cornerRadius: 11))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                if store.categories(for: item.kind).contains(where: { $0.id == item.id }) {
                    Section {
                        Button("Eliminar categoría", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CashTheme.background)
            .navigationTitle(item.name.isEmpty ? "Nueva categoría" : "Editar categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Guardar")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Guardar categoría")
                }
            }
            .sheet(isPresented: $showingPhotoLibrary) {
                CashPhotoLibraryPicker { image in
                    // Reducir el peso de la fotografía antes de guardarla en el registro local.
                    let maximum: CGFloat = 320
                    let factor = min(1, maximum / max(image.size.width, image.size.height))
                    let size = CGSize(width: max(1, image.size.width * factor),
                                      height: max(1, image.size.height * factor))
                    let reduced = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.72) { _ in
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    iconData = reduced
                }
            }
            .confirmationDialog("¿Eliminar esta categoría?", isPresented: $confirmDelete) {
                Button("Eliminar categoría", role: .destructive) { delete() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Los movimientos no se eliminarán. Si esta categoría contiene operaciones, Cash las trasladará a 'Otros' del mismo tipo.")
            }
            .alert("Revisa la categoría", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) {
                Button("Entendido") { errorText = nil }
            } message: { Text(errorText ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        do {
            var updated = item
            updated.name = name
            updated.symbol = symbol
            updated.iconData = iconData
            try store.saveCategory(updated)
            dismiss()
        } catch {
            errorText = error.localizedDescription
            saving = false
        }
    }

    private func delete() {
        do {
            try store.deleteCategory(item)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}


// Selector UIKit compatible con iOS, evitando PhotosPickerItem del SDK PhotosUI.
struct CashPhotoLibraryPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .photoLibrary
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage) -> Void
        var dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
