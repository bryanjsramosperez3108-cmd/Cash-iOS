import SwiftUI

struct CashEditor: View {
    @ObservedObject var store: CashStore
    let draft: CashDraft
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CashKind
    @State private var title: String
    @State private var amount: String
    @State private var date: Date
    @State private var account: CashAccount
    @State private var destination: CashAccount
    @State private var categoryID: String
    @State private var note: String
    @State private var showDeleteSheet = false
    @State private var deleteAfterSheetDismiss = false
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var calendarExpanded = false
    @State private var datePickerMonth: Date

    init(store: CashStore, draft: CashDraft) {
        self.store = store
        self.draft = draft
        let initial = draft.operation
        _kind = State(initialValue: draft.kind)
        _title = State(initialValue: initial?.title ?? "")
        _amount = State(initialValue: initial.map { CashMoney.editable($0.cents) } ?? "")
        _date = State(initialValue: initial?.date ?? Date())
        _datePickerMonth = State(initialValue: initial?.date ?? Date())
        _account = State(initialValue: initial?.account ?? .cash)
        _destination = State(initialValue: initial?.destination ?? .bac)
        let options = store.categories(for: draft.kind)
        _categoryID = State(initialValue: initial?.categoryID ?? initial.map { CashUserCategory.legacyID(for: $0) } ?? options.first?.id ?? "")
        _note = State(initialValue: initial?.note ?? "")
    }
    private var cents: Int64? { CashMoney.parse(amount) }
    private var isValid: Bool {
        guard let cents, cents > 0, !categoryID.isEmpty else { return false }
        if kind == .transfer { return account != destination }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Operación") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(CashKind.allCases) { option in Text(option.title).tag(option) }
                    }
                    .onChange(of: kind) { _, newKind in
                        categoryID = store.categories(for: newKind).first?.id ?? ""
                    }
                    HStack {
                        Text("L").font(.title2.bold()).foregroundStyle(CashTheme.color(kind))
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                }
                if kind == .transfer {
                    Section("Transferencia") {
                        Picker("Cuenta de origen", selection: $account) {
                            ForEach(store.accounts) { account in Text(store.accountName(account)).tag(account) }
                        }
                        Picker("Cuenta de destino", selection: $destination) {
                            ForEach(store.accounts) { account in Text(store.accountName(account)).tag(account) }
                        }
                        Picker("Categoría", selection: $categoryID) {
                            ForEach(store.categories(for: .transfer)) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        Text("Disponible hoy: \(CashMoney.formatted(store.balance(account)))")
                            .font(.footnote).foregroundStyle(CashTheme.muted)
                        if account == destination {
                            Text("La cuenta de origen y destino deben ser diferentes.")
                                .foregroundStyle(CashTheme.red).font(.footnote)
                        }
                    }
                } else {
                    Section("Detalles") {
                        TextField("Concepto", text: $title)
                            .textInputAutocapitalization(.sentences)
                        Picker(kind == .income ? "Cuenta destino" : "Cuenta de origen", selection: $account) {
                            ForEach(store.accounts) { account in Text(store.accountName(account)).tag(account) }
                        }
                        Picker("Categoría", selection: $categoryID) {
                            ForEach(store.categories(for: kind)) { option in
                                Label(option.name, systemImage: option.symbol).tag(option.id)
                            }
                        }
                        if kind == .expense {
                            Text("Saldo disponible hoy: \(CashMoney.formatted(store.balance(account)))")
                                .font(.caption).foregroundStyle(CashTheme.muted)
                        }
                    }
                }
                Section("Fecha") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.19)) {
                            if !calendarExpanded { datePickerMonth = date }
                            calendarExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Fecha del movimiento").foregroundStyle(.white)
                            Spacer()
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(CashTheme.blue)
                            Image(systemName: calendarExpanded ? "chevron.up" : "calendar")
                                .foregroundStyle(CashTheme.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    if calendarExpanded {
                        CashInlineDateCalendar(selection: $date, visibleMonth: $datePickerMonth) {
                            // Cambiar de MES no cierra el calendario; elegir DÍA sí.
                            withAnimation(.easeInOut(duration: 0.18)) {
                                calendarExpanded = false
                            }
                        }
                    }
                    if kind == .transfer {
                        TextField("Observaciones de transferencia (opcional)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView().tint(.white) }
                            Text(kind == .transfer ? "Realizar transferencia" :
                                 draft.operation == nil ? "Guardar movimiento" : "Guardar cambios")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!isValid || isSaving)
                    .buttonStyle(.borderedProminent)
                    .tint(CashTheme.color(kind))
                }
                if draft.operation != nil {
                    Section {
                        Button("Eliminar esta operación", systemImage: "trash", role: .destructive) {
                            showDeleteSheet = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 9)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CashTheme.background)
            .navigationTitle(draft.operation == nil ? kind.title : "Editar movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .sheet(isPresented: $showDeleteSheet, onDismiss: {
                if deleteAfterSheetDismiss {
                    deleteAfterSheetDismiss = false
                    delete()
                }
            }) {
                CashDeleteConfirmation {
                    deleteAfterSheetDismiss = true
                    showDeleteSheet = false
                }
            }
            .alert("No se pudo guardar", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) {
                Button("Entendido") { errorText = nil }
            } message: { Text(errorText ?? "") }
        }
        .preferredColorScheme(.dark)
    }
    private func save() {
        guard !isSaving, isValid, let cents else { return }
        isSaving = true
        let finalTitle: String
        if kind == .transfer {
            finalTitle = "Transferencia"
        } else {
            finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let operation = CashOperation(id: draft.operation?.id ?? UUID(), kind: kind, title: finalTitle,
                                      cents: cents, date: date, category: draft.operation?.category ?? .other,
                                      account: account, destination: kind == .transfer ? destination : nil,
                                      note: note, categoryID: categoryID)
        do {
            try store.save(operation)
            // Reproducir solo tras un NUEVO ingreso o gasto guardado con éxito.
            // Nunca al editar, al fallar una validación o al transferir dinero.
            if draft.operation == nil && (kind == .income || kind == .expense) {
                CashSoundPlayer.shared.play(for: kind)
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
            isSaving = false
        }
    }
    private func delete() {
        guard let previous = draft.operation else { return }
        do {
            try store.delete(previous)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}


// Calendario incorporado al formulario. La navegación de meses NO altera
// la selección; solo pulsar un número de día establece la fecha y lo cierra.
private struct CashInlineDateCalendar: View {
    @Binding var selection: Date
    @Binding var visibleMonth: Date
    let didSelectDay: () -> Void

    private let weekdays = ["L", "M", "M", "J", "V", "S", "D"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 36)
                }
                Spacer()
                Text(visibleMonth.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 40, height: 36)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(CashTheme.blue)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays.indices, id: \.self) { index in
                    Text(weekdays[index])
                        .font(.caption2.bold()).foregroundStyle(CashTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<42, id: \.self) { index in
                    if let value = calendarDates[index] {
                        Button {
                            selection = value
                            didSelectDay()
                        } label: {
                            Text("\(Calendar.current.component(.day, from: value))")
                                .font(.subheadline.weight(Calendar.current.isDate(value, inSameDayAs: selection) ? .bold : .regular))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 37)
                                .background(Calendar.current.isDate(value, inSameDayAs: selection) ? CashTheme.blue : .clear,
                                            in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(value.formatted(date: .complete, time: .omitted))
                    } else {
                        Color.clear.frame(height: 37)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var calendarDates: [Date?] {
        let calendar = Calendar.current
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth)),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return Array(repeating: nil, count: 42)
        }
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        return (0..<42).map { index in
            let day = index - offset + 1
            return range.contains(day) ? calendar.date(byAdding: .day, value: day - 1, to: first) : nil
        }
    }

    private func moveMonth(_ number: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: number, to: visibleMonth) ?? visibleMonth
    }
}

// Confirmación explícita: el botón destructivo queda anclado ABAJO y
// separado del texto de advertencia; evita borrados por toques accidentales.
private struct CashDeleteConfirmation: View {
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 43))
                .foregroundStyle(CashTheme.red)
                .padding(.top, 22)
            Text("¿Eliminar esta operación?")
                .font(.title3.bold())
            Text("Se eliminará el movimiento y se recalcularán los saldos de las cuentas. Esta acción no se puede deshacer.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(CashTheme.muted)
                .padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .background(CashTheme.secondary.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text("Eliminar definitivamente")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(CashTheme.red, in: RoundedRectangle(cornerRadius: 15))
                }
                Button("Cancelar") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .background(CashTheme.secondary)
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
