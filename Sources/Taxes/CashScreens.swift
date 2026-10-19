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
        HStack(spacing: 12) {
            CashCategoryIcon(category: store.category(for: item), fallback: icon)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 42, height: 42)
                .foregroundStyle(CashTheme.color(item.kind))
                .background(CashTheme.color(item.kind).opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.kind == .transfer ?
                     "\(item.account.name) → \(item.destination?.name ?? "Destino")" :
                     "\(store.category(for: item)?.name ?? item.category.title) · \(item.account.name)")
                    .font(.caption2).foregroundStyle(CashTheme.muted).lineLimit(2)
                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(CashTheme.muted)
            }
            Spacer(minLength: 3)
            Text((item.kind == .expense ? "−" : item.kind == .income ? "+" : "") + CashMoney.formatted(item.cents))
                .font(.subheadline.weight(.bold)).foregroundStyle(CashTheme.color(item.kind))
                .lineLimit(1).minimumScaleFactor(0.66).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(CashTheme.muted)
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
                                Button { edit(item) } label: { CashRow(item: item) }.buttonStyle(.plain)
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
             item.account.name.localizedCaseInsensitiveContains(search) ||
             (item.destination?.name.localizedCaseInsensitiveContains(search) ?? false))
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
                                Button { edit(item) } label: { CashRow(item: item) }.buttonStyle(.plain)
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
                        Text(account.name).font(.subheadline).foregroundStyle(CashTheme.muted)
                    }
                    CashCard {
                        HStack {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            Spacer()
                            Text(CashMoney.month(month)).font(.headline)
                            Spacer()
                            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(CashTheme.blue)
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
            .navigationTitle(account.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedMovement) { movement in
            CashEditor(store: store,
                       draft: CashDraft(operation: movement, kind: movement.kind, date: movement.date))
        }
    }

    private func shift(_ amount: Int) {
        month = Calendar.current.date(byAdding: .month, value: amount, to: month) ?? month
    }
}

struct CashAnalysis: View {
    @ObservedObject var store: CashStore
    let edit: (CashOperation) -> Void
    @State private var month = Date()
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 17) {
                    cashPie
                    HStack(spacing: 12) {
                        metric("Ingresos", kind: .income)
                        metric("Gastos", kind: .expense)
                    }
                    CashCard {
                        Text("Balance del mes").foregroundStyle(CashTheme.muted)
                        Text(CashMoney.formatted(store.monthlyTotal(.income, month: month) - store.monthlyTotal(.expense, month: month)))
                            .font(.title.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    CashSectionTitle("Mayor ingreso del mes")
                    biggest(.income)
                    CashSectionTitle("Mayor gasto del mes")
                    biggest(.expense)
                    CashSectionTitle("Gastos por categoría")
                    breakdown(.expense)
                    CashSectionTitle("Ingresos por categoría")
                    breakdown(.income)
                }.frame(maxWidth: .infinity).padding(16)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle("Análisis")
        }
    }
    private var cashPie: some View {
        let income = store.monthlyTotal(.income, month: month)
        let expenses = store.monthlyTotal(.expense, month: month)
        let total = Double(income) + Double(expenses)
        let incomeShare = total > 0 ? Double(income) / total : 0.0
        return CashCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Ingresos y gastos")
                        .font(.title3.bold())
                    Spacer(minLength: 12)
                }
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
                            Text("Sin movimientos")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(CashTheme.muted)
                    } else if expenses == 0 {
                        Circle().fill(CashTheme.green)
                    } else if income == 0 {
                        Circle().fill(CashTheme.red)
                    } else {
                        CashPieSlice(startDegrees: -90,
                                     endDegrees: -90 + 360 * incomeShare)
                            .fill(CashTheme.green)
                        CashPieSlice(startDegrees: -90 + 360 * incomeShare,
                                     endDegrees: 270)
                            .fill(CashTheme.red)
                    }
                }
                .frame(width: 208, height: 208)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Gráfica de pastel. Ingresos \(CashMoney.formatted(income)). Gastos \(CashMoney.formatted(expenses))")

                // Los importes sólo se muestran en las tarjetas de métricas
                // que aparecen debajo de esta gráfica; sin valores repetidos.
            }
        }
    }
    private func metric(_ title: String, kind: CashKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: kind == .income ? "arrow.down.left" : "arrow.up.right")
                .font(.caption.bold()).foregroundStyle(CashTheme.color(kind))
            Text(CashMoney.formatted(store.monthlyTotal(kind, month: month)))
                .font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(CashTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func biggest(_ kind: CashKind) -> some View {
        CashCard {
            if let item = store.biggest(kind, month: month) {
                Button { edit(item) } label: { CashRow(item: item) }.buttonStyle(.plain)
                if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(CashTheme.muted) }
            } else { CashEmpty(title: "Sin datos este mes", icon: "chart.bar.xaxis") }
        }
    }
    private func breakdown(_ kind: CashKind) -> some View {
        CashCard {
            let data = store.categories(kind, month: month)
            let maximum = max(data.first?.1 ?? 0, 1)
            if data.isEmpty { CashEmpty(title: "Sin datos este mes", icon: "chart.bar") }
            else {
                ForEach(data, id: \.0.id) { item in
                    let category = item.0
                    let amount = item.1
                    VStack(spacing: 8) {
                        HStack {
                            Label(category.title, systemImage: category.symbol).font(.subheadline)
                            Spacer()
                            Text(CashMoney.formatted(amount)).font(.caption.bold())
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            Capsule().fill(CashTheme.raised)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(CashTheme.color(kind))
                                        .frame(width: geo.size.width * CGFloat(Double(amount) / Double(maximum)))
                                }
                        }.frame(height: 7)
                    }.padding(.vertical, 7)
                }
            }
        }
    }
    private func shift(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month) ?? month
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
