import SwiftUI

struct CashEmpty: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 29)).foregroundStyle(CashTheme.muted)
            Text(title).font(.subheadline).foregroundStyle(CashTheme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

struct CashRow: View {
    let item: CashOperation
    @EnvironmentObject private var store: CashStore
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CashCategoryIcon(category: store.category(for: item), fallback: icon)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 42, height: 42)
                .foregroundStyle(CashTheme.color(item.kind))
                .background(CashTheme.color(item.kind).opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !item.note.isEmpty && item.note != item.title {
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(CashTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Text(item.kind == .transfer ?
                     "\(store.accountName(item.account)) → \(item.destination.map { store.accountName($0) } ?? "Destino")" :
                     "\(store.category(for: item)?.name ?? item.category.title) · \(store.accountName(item.account))")
                    .font(.caption2)
                    .foregroundStyle(CashTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(CashTheme.muted)
            }
            Spacer(minLength: 3)
            VStack(alignment: .trailing, spacing: 6) {
                Text((item.kind == .expense ? "−" : item.kind == .income ? "+" : "") + CashMoney.formatted(item.cents))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CashTheme.color(item.kind))
                    .lineLimit(1).minimumScaleFactor(0.66).monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(CashTheme.muted)
            }
            .frame(maxWidth: 142, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
    private var icon: String {
        switch item.kind {
        case .income: return "arrow.down.left"
        case .expense: return "arrow.up.right"
        case .transfer: return "arrow.left.arrow.right"
        }
    }
}

struct CashCalendar: View {
    @ObservedObject var store: CashStore
    let edit: (CashOperation) -> Void
    let add: (CashKind, Date) -> Void
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    private let weekdays = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 19) {
                    HStack {
                        Text("Organiza tu mes").font(.subheadline).foregroundStyle(CashTheme.muted)
                        Spacer()
                        Button("Hoy") { selectedDate = Date(); visibleMonth = Date() }
                            .font(.subheadline.bold())
                    }
                    CashCard {
                        monthHeader
                        LazyVGrid(columns: columns, spacing: 7) {
                            ForEach(weekdays.indices, id: \.self) { index in
                                Text(weekdays[index]).font(.caption2.bold())
                                    .foregroundStyle(CashTheme.muted).frame(maxWidth: .infinity)
                            }
                            ForEach(0..<42, id: \.self) { index in
                                if let date = dates[index] {
                                    dateCell(date)
                                } else {
                                    Color.clear.frame(height: 53)
                                }
                            }
                        }
                    }
                    CashSectionTitle(selectedDate.formatted(.dateTime.day().month(.wide)).capitalized)
                    CashCard {
                        let items = store.daily(selectedDate)
                        if items.isEmpty {
                            CashEmpty(title: "Día sin movimientos", icon: "calendar.badge.plus")
                        } else {
                            ForEach(items) { item in
                                Button { edit(item) } label: { CashMovementOrganizedRow(item: item, store: store) }.buttonStyle(.plain)
                                if item.id != items.last?.id { Divider().overlay(CashTheme.stroke) }
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        CashQuickAction(title: "Nuevo ingreso", symbol: "plus", color: CashTheme.green) { add(.income, selectedDate) }
                        CashQuickAction(title: "Nuevo gasto", symbol: "minus", color: CashTheme.red) { add(.expense, selectedDate) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).padding(.bottom, 20)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle("Calendario")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(CashMoney.month(visibleMonth)).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
            Spacer()
            Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain).foregroundStyle(CashTheme.blue).padding(.bottom, 17)
    }
    private var dates: [Date?] {
        let cal = Calendar.current
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: visibleMonth)),
              let range = cal.range(of: .day, in: .month, for: first) else { return Array(repeating: nil, count: 42) }
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        return (0..<42).map { index in
            let day = index - offset + 1
            return range.contains(day) ? cal.date(byAdding: .day, value: day - 1, to: first) : nil
        }
    }
    private func dateCell(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let today = Calendar.current.isDateInToday(date)
        let items = store.daily(date)
        return Button { selectedDate = date } label: {
            VStack(spacing: 6) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.subheadline.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? .white : .white.opacity(0.9))
                    .frame(width: 33, height: 33)
                    .background(selected ? CashTheme.blue : .clear, in: Circle())
                    .overlay(Circle().strokeBorder(today && !selected ? CashTheme.blue : .clear, lineWidth: 1.5))
                HStack(spacing: 3) {
                    if items.contains(where: { $0.kind == .income }) { Circle().fill(CashTheme.green).frame(width: 5, height: 5) }
                    if items.contains(where: { $0.kind == .expense }) { Circle().fill(CashTheme.red).frame(width: 5, height: 5) }
                    if items.contains(where: { $0.kind == .transfer }) { Circle().fill(CashTheme.blue).frame(width: 5, height: 5) }
                }.frame(height: 6)
            }
            .frame(maxWidth: .infinity).frame(height: 53)
            .background(selected ? CashTheme.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
    private func changeMonth(_ amount: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: amount, to: visibleMonth) ?? visibleMonth
        selectedDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: visibleMonth)) ?? visibleMonth
    }
}

struct CashQuickAction: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(color.opacity(0.35)))
        }.buttonStyle(.plain)
    }
}

struct CashAdd: View {
    let add: (CashKind, Date) -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    VStack(spacing: 15) {
                        action("Nuevo ingreso", symbol: "arrow.down.left", color: CashTheme.green, kind: .income)
                        action("Nuevo gasto", symbol: "arrow.up.right", color: CashTheme.red, kind: .expense)
                        action("Realizar transferencia", symbol: "arrow.left.arrow.right", color: CashTheme.blue, kind: .transfer)
                    }
                    // Conserva los botones grandes que ya funcionan.
                    .frame(height: max(150, (geometry.size.height - 110) / 3) * 3 + 30)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    // Espacio final táctil real para desplazarse arriba y abajo.
                    .padding(.bottom, max(160, geometry.size.height * 0.22))
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.always)
                .scrollIndicators(.visible)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle("Añadir")
        }
    }

    private func action(_ title: String, symbol: String, color: Color, kind: CashKind) -> some View {
        Button { add(kind, Date()) } label: {
            HStack(spacing: 17) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 70, height: 70)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 3)
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CashTheme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(CashTheme.card, in: RoundedRectangle(cornerRadius: CashTheme.radius))
            .overlay(RoundedRectangle(cornerRadius: CashTheme.radius)
                .strokeBorder(color.opacity(0.22)))
        }.buttonStyle(.plain)
    }
}

enum CashFilter: String, CaseIterable, Identifiable {
    case all = "Todos", income = "Ingresos", expense = "Gastos", transfer = "Transferencias"
    var id: String { rawValue }
    var kind: CashKind? {
        switch self { case .all: return nil; case .income: return .income; case .expense: return .expense; case .transfer: return .transfer }
    }
}

// V11: solo la pestaña Movimientos: fecha e importe arriba,
// concepto completo al centro, categoría y cuenta identificadas abajo.
private struct CashMovementOrganizedRow: View {
    let item: CashOperation
    @ObservedObject var store: CashStore
    // Solo los destacados de Análisis muestran el concepto abreviado.
    var compactConcept: Bool = false

    private var categoryTitle: String {
        store.category(for: item)?.name ?? item.category.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(item.date.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CashTheme.muted)
                Spacer(minLength: 4)
                Text((item.kind == .expense ? "−" : item.kind == .income ? "+" : "")
                     + CashMoney.formatted(item.cents))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CashTheme.color(item.kind))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            HStack(alignment: .top, spacing: 11) {
                CashCategoryIcon(category: store.category(for: item), fallback: "tag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CashTheme.color(item.kind))
                    .frame(width: 38, height: 38)
                    .background(CashTheme.color(item.kind).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .lineLimit(compactConcept ? 2 : nil)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: !compactConcept)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !compactConcept && !item.note.isEmpty && item.note != item.title {
                        Text(item.note)
                            .font(.caption)
                            .foregroundStyle(CashTheme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6) // Centrar visualmente el concepto respecto al icono.
            }
            Divider().overlay(CashTheme.stroke)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { categoryMetadata; accountMetadata }
                VStack(alignment: .leading, spacing: 8) { categoryMetadata; accountMetadata }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var categoryMetadata: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "tag.fill").foregroundStyle(CashTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.kind == .transfer ? "TIPO" : "CATEGORÍA")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CashTheme.muted)
                Text(item.kind == .transfer ? "Transferencia" : categoryTitle)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accountMetadata: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "wallet.pass.fill").foregroundStyle(CashTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.kind == .transfer ? "ORIGEN → DESTINO" : "CUENTA")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(CashTheme.muted)
                Text(item.kind == .transfer
                     ? "\(store.accountName(item.account)) → \(item.destination.map { store.accountName($0) } ?? "Destino")"
                     : store.accountName(item.account))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CashMovements: View {
    @ObservedObject var store: CashStore
    let edit: (CashOperation) -> Void
    @State private var filter: CashFilter = .all
    @State private var search = ""
    var items: [CashOperation] {
        store.sorted.filter { item in
            (filter.kind == nil || item.kind == filter.kind) &&
            (search.isEmpty || item.title.localizedCaseInsensitiveContains(search) ||
             (store.category(for: item)?.name ?? item.category.title).localizedCaseInsensitiveContains(search) ||
             store.accountName(item.account).localizedCaseInsensitiveContains(search) ||
             (item.destination.map { store.accountName($0).localizedCaseInsensitiveContains(search) } ?? false))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Filtrar movimientos", selection: $filter) {
                        ForEach(CashFilter.allCases) { option in Text(option.rawValue).tag(option) }
                    }.pickerStyle(.menu)
                    CashCard {
                        if items.isEmpty {
                            CashEmpty(title: "No hay movimientos para este filtro", icon: "tray")
                        } else {
                            ForEach(items) { item in
                                Button { edit(item) } label: { CashMovementOrganizedRow(item: item, store: store) }.buttonStyle(.plain)
                                if item.id != items.last?.id { Divider().overlay(CashTheme.stroke) }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .searchable(text: $search, prompt: "Buscar concepto, cuenta o categoría")
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle("Movimientos")
        }
    }
}

struct CashMonthDetail: View {
    @ObservedObject var store: CashStore
    let kind: CashKind
    let month: Date
    @State private var selectedMovement: CashOperation?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    CashCard {
                        Text(kind == .income ? "INGRESOS DEL MES" : "GASTOS DEL MES")
                            .font(.caption.bold()).foregroundStyle(CashTheme.color(kind))
                        Text(CashMoney.formatted(store.monthlyTotal(kind, month: month)))
                            .font(.largeTitle.bold()).monospacedDigit()
                        Text(CashMoney.month(month)).foregroundStyle(CashTheme.muted)
                    }
                    CashCard {
                        let items = store.monthly(month, kind: kind)
                        if items.isEmpty { CashEmpty(title: "Sin movimientos", icon: "calendar") }
                        else {
                            ForEach(items) { item in
                                Button { selectedMovement = item } label: { CashRow(item: item) }.buttonStyle(.plain)
                                if item.id != items.last?.id { Divider().overlay(CashTheme.stroke) }
                            }
                        }
                    }
                }.padding(16)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle(kind == .income ? "Ingresos del mes" : "Gastos del mes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedMovement) { movement in
            CashEditor(store: store,
                       draft: CashDraft(operation: movement, kind: movement.kind,
                                        date: movement.date))
        }
    }
}


// Al tocar la tarjeta de una cuenta: lista de movimientos y transferencias
// correspondientes al mes visualizado en Inicio. No altera el saldo del banco.
struct CashAccountDetail: View {
    @ObservedObject var store: CashStore
    let account: CashAccount
    let initialMonth: Date
    @State private var month: Date
    @State private var selectedMovement: CashOperation?
    @Environment(\.dismiss) private var dismiss

    init(store: CashStore, account: CashAccount, initialMonth: Date) {
        self.store = store
        self.account = account
        self.initialMonth = initialMonth
        _month = State(initialValue: initialMonth)
    }

    private var items: [CashOperation] {
        store.monthly(month).filter { item in
            item.account == account || (item.kind == .transfer && item.destination == account)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 15) {
                    CashCard {
                        Text("SALDO ACTUAL DISPONIBLE")
                            .font(.caption.bold())
                            .foregroundStyle(CashTheme.muted)
                        Text(CashMoney.formatted(store.balance(account)))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(store.accountName(account)).font(.subheadline).foregroundStyle(CashTheme.muted)
                    }
                    CashCard {
                        HStack {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            Text(CashMoney.month(month)).font(.headline)
                            Spacer()
                            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                                .disabled(isCurrentMonth)
                                .opacity(isCurrentMonth ? 0.3 : 1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(CashTheme.blue)
                    }
                    if let summary = store.accountMonthSummary(account, month: month) {
                        CashCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(isCurrentMonth ? "SALDO REGISTRADO EN ESTE MES" : "SALDO AL CIERRE DEL MES")
                                    .font(.caption.bold()).foregroundStyle(CashTheme.muted)
                                Text(CashMoney.formatted(summary.closing))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                                Divider().overlay(CashTheme.stroke)
                                monthAmountRow("Saldo inicial", amount: summary.opening)
                                monthAmountRow("Ingresos", amount: summary.income)
                                monthAmountRow("Gastos", amount: -summary.expense)
                                monthAmountRow("Transferencias recibidas", amount: summary.transferIn)
                                monthAmountRow("Transferencias enviadas", amount: -summary.transferOut)
                                if summary.adjustments != 0 {
                                    monthAmountRow("Ajustes de saldo", amount: summary.adjustments)
                                }
                                if store.historicalBalanceIsEstimated(month: month) {
                                    Label("Cierre reconstruido: los ajustes de saldo anteriores a V14 no tenían fecha y podrían afectar el historial.", systemImage: "info.circle")
                                        .font(.caption2).foregroundStyle(CashTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    CashSectionTitle("Movimientos de la cuenta")
                    CashCard {
                        if items.isEmpty {
                            CashEmpty(title: "Sin movimientos en este mes", icon: "tray")
                        } else {
                            ForEach(items) { item in
                                Button { selectedMovement = item } label: {
                                    CashRow(item: item)
                                }.buttonStyle(.plain)
                                if item.id != items.last?.id { Divider().overlay(CashTheme.stroke) }
                            }
                        }
                    }
                    Text("Las transferencias se muestran tanto en la cuenta de origen como en la de destino. No se contabilizan como ingreso o gasto.")
                        .font(.caption2)
                        .foregroundStyle(CashTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle(store.accountName(account))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedMovement) { movement in
            CashEditor(store: store,
                       draft: CashDraft(operation: movement, kind: movement.kind, date: movement.date))
        }
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private func monthAmountRow(_ label: String, amount: Int64) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(CashTheme.muted)
            Spacer(minLength: 8)
            Text(CashMoney.formatted(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func shift(_ amount: Int) {
        let next = Calendar.current.date(byAdding: .month, value: amount, to: month) ?? month
        let now = Date()
        let year = Calendar.current.component(.year, from: next)
        let monthNumber = Calendar.current.component(.month, from: next)
        let nowYear = Calendar.current.component(.year, from: now)
        let nowMonth = Calendar.current.component(.month, from: now)
        guard year < nowYear || (year == nowYear && monthNumber <= nowMonth) else { return }
        month = next
    }
}

// CASH V8: menús de categorías mensuales. No modifica la contabilidad ni los datos.
struct CashAnalysis: View {
    @ObservedObject var store: CashStore
    let edit: (CashOperation) -> Void
    @State private var month = Date()
    @State private var expensesExpanded = false
    @State private var incomesExpanded = false
    @State private var selectedCategory: CashAnalysisCategoryRoute?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 17) {
                    cashPie
                    HStack(spacing: 12) {
                        metric("Ingresos", kind: .income)
                        metric("Gastos", kind: .expense)
                    }

                    // Primero las categorías, para evitar desplazarse por toda la lista.
                    categoryMenu(.expense)
                    categoryMenu(.income)

                    // Indicadores de cierre al final de la pantalla.
                    CashCard {
                        Text("Balance del mes").foregroundStyle(CashTheme.muted)
                        Text(CashMoney.formatted(store.monthlyTotal(.income, month: month) - store.monthlyTotal(.expense, month: month)))
                            .font(.title.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    CashSectionTitle("Mayor ingreso del mes")
                    biggest(.income)
                    CashSectionTitle("Mayor gasto del mes")
                    biggest(.expense)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle("Análisis")
        }
        .sheet(item: $selectedCategory) { route in
            CashAnalysisCategoryDetail(store: store, route: route)
        }
    }

    private var cashPie: some View {
        let income = store.monthlyTotal(.income, month: month)
        let expenses = store.monthlyTotal(.expense, month: month)
        let total = Double(income) + Double(expenses)
        let incomeShare = total > 0 ? Double(income) / total : 0.0
        return CashCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ingresos y gastos").font(.title3.bold())
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(CashMoney.month(month)).font(.headline)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(CashTheme.blue)

                ZStack {
                    if total <= 0 {
                        Circle().fill(CashTheme.raised)
                        VStack(spacing: 7) {
                            Image(systemName: "chart.pie")
                            Text("Sin movimientos").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(CashTheme.muted)
                    } else if expenses == 0 {
                        Circle().fill(CashTheme.green)
                    } else if income == 0 {
                        Circle().fill(CashTheme.red)
                    } else {
                        CashPieSlice(startDegrees: -90, endDegrees: -90 + 360 * incomeShare)
                            .fill(CashTheme.green)
                        CashPieSlice(startDegrees: -90 + 360 * incomeShare, endDegrees: 270)
                            .fill(CashTheme.red)
                    }
                }
                .frame(width: 208, height: 208)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Gráfica de pastel. Ingresos \(CashMoney.formatted(income)). Gastos \(CashMoney.formatted(expenses))")
            }
        }
    }

    private func metric(_ title: String, kind: CashKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: kind == .income ? "arrow.down.left" : "arrow.up.right")
                .font(.caption.bold()).foregroundStyle(CashTheme.color(kind))
            Text(CashMoney.formatted(store.monthlyTotal(kind, month: month)))
                .font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CashTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    // Desplegado muestra todas las categorías; contraído solo las tres mayores.
    private func categoryMenu(_ kind: CashKind) -> some View {
        let data = store.categories(kind, month: month).sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }
        let expanded = kind == .expense ? expensesExpanded : incomesExpanded
        let visible = expanded ? data : Array(data.prefix(3))
        let title = kind == .expense ? "Gastos del mes" : "Ingresos del mes"

        return CashCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if kind == .expense { expensesExpanded.toggle() }
                        else { incomesExpanded.toggle() }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind == .expense ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                            .foregroundStyle(CashTheme.color(kind))
                            .font(.title3)
                        Text(title).font(.headline)
                        Spacer(minLength: 4)
                        Text("\(data.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CashTheme.muted)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CashTheme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Contraer categorías" : "Mostrar todas las categorías")

                if data.isEmpty {
                    CashEmpty(title: "Sin \(kind == .expense ? "gastos" : "ingresos") en este mes", icon: "tray")
                } else {
                    let maximum = max(data.first?.1 ?? 0, 1)
                    ForEach(visible, id: \.0.id) { item in
                        Button {
                            selectedCategory = CashAnalysisCategoryRoute(kind: kind,
                                                                          category: item.0,
                                                                          month: month)
                        } label: {
                            VStack(spacing: 8) {
                                HStack(spacing: 10) {
                                    CashCategoryIcon(category: item.0, fallback: item.0.symbol)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(CashTheme.color(kind))
                                        .frame(width: 34, height: 34)
                                        .background(CashTheme.color(kind).opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                    Text(item.0.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(CashMoney.formatted(item.1))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(CashTheme.muted)
                                }
                                GeometryReader { geo in
                                    Capsule().fill(CashTheme.raised)
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(CashTheme.color(kind))
                                                .frame(width: geo.size.width * CGFloat(Double(item.1) / Double(maximum)))
                                        }
                                }
                                .frame(height: 6)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if data.count > 3 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if kind == .expense { expensesExpanded.toggle() }
                                else { incomesExpanded.toggle() }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(expanded ? "Ver menos" : "Ver todas las \(data.count) categorías")
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.bold())
                                Spacer()
                            }
                            .foregroundStyle(CashTheme.blue)
                            .padding(.top, 7)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func biggest(_ kind: CashKind) -> some View {
        CashCard {
            if let item = store.biggest(kind, month: month) {
                Button { edit(item) } label: {
                    CashMovementOrganizedRow(item: item, store: store, compactConcept: true)
                }
                .buttonStyle(.plain)
            } else {
                CashEmpty(title: "Sin datos este mes", icon: "chart.bar.xaxis")
            }
        }
    }

    private func shift(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
    }
}

private struct CashAnalysisCategoryRoute: Identifiable {
    let id = UUID()
    let kind: CashKind
    let category: CashUserCategory
    let month: Date
}

private struct CashAnalysisCategoryDetail: View {
    @ObservedObject var store: CashStore
    let route: CashAnalysisCategoryRoute
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMovement: CashOperation?

    private var items: [CashOperation] {
        store.monthly(route.month, kind: route.kind).filter { item in
            (item.categoryID ?? CashUserCategory.legacyID(for: item)) == route.category.id
        }
    }

    private var amount: Int64 {
        items.reduce(Int64(0)) { $0 &+ $1.cents }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    CashCard {
                        Text(route.category.name).font(.title3.bold())
                        Text(CashMoney.month(route.month))
                            .font(.subheadline)
                            .foregroundStyle(CashTheme.muted)
                        Text(CashMoney.formatted(amount))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(CashTheme.color(route.kind))
                        Text("\(items.count) \(items.count == 1 ? "movimiento" : "movimientos")")
                            .font(.caption)
                            .foregroundStyle(CashTheme.muted)
                    }
                    CashSectionTitle("Movimientos y fechas")
                    CashCard {
                        if items.isEmpty {
                            CashEmpty(title: "Sin movimientos en esta categoría", icon: "tray")
                        } else {
                            ForEach(items) { item in
                                Button { selectedMovement = item } label: {
                                    // Diseño clásico V9: concepto completo, fecha, cuenta e importe.
                                    // Sin repetir el nombre de la categoría dentro de cada movimiento.
                                    CashConceptoCompletoV9(item: item, category: store.category(for: item), store: store)
                                }
                                .buttonStyle(.plain)
                                if item.id != items.last?.id { Divider().overlay(CashTheme.stroke) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle(route.kind == .expense ? "Gastos de la categoría" : "Ingresos de la categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedMovement) { item in
            CashEditor(store: store,
                       draft: CashDraft(operation: item, kind: item.kind, date: item.date))
        }
    }
}


// V9: solo se utiliza en el detalle de movimientos por categoría de Análisis.
// No altera CashRow en Inicio, Calendario ni Movimientos.
private struct CashConceptoCompletoV9: View {
    let item: CashOperation
    let category: CashUserCategory?
    @ObservedObject var store: CashStore

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                CashCategoryIcon(category: category, fallback: category?.symbol ?? "tag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CashTheme.color(item.kind))
                    .frame(width: 40, height: 40)
                    .background(CashTheme.color(item.kind).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !item.note.isEmpty && item.note != item.title {
                        Text(item.note)
                            .font(.caption)
                            .foregroundStyle(CashTheme.muted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(CashTheme.muted)
                    Text(store.accountName(item.account))
                        .font(.caption2)
                        .foregroundStyle(CashTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text((item.kind == .expense ? "−" : item.kind == .income ? "+" : "")
                     + CashMoney.formatted(item.cents))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CashTheme.color(item.kind))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(CashTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// Pastel vectorial nativo, sin dependencias adicionales de Charts.
private struct CashPieSlice: Shape {
    let startDegrees: Double
    let endDegrees: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var shape = Path()
        shape.move(to: center)
        shape.addArc(center: center, radius: radius,
                     startAngle: .degrees(startDegrees),
                     endAngle: .degrees(endDegrees),
                     clockwise: false)
        shape.closeSubpath()
        return shape
    }
}
