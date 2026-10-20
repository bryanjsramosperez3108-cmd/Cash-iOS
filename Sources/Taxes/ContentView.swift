import SwiftUI
import UIKit

// Cash sustituye únicamente la interfaz; mantenemos el target "Taxes"
// y su bundle ID para conservar los datos y la firma de la app instalada.
enum CashTheme {
    static let background = Color(red: 8/255, green: 9/255, blue: 13/255)
    static let secondary = Color(red: 18/255, green: 20/255, blue: 27/255)
    static let card = Color(red: 25/255, green: 28/255, blue: 37/255)
    static let raised = Color(red: 35/255, green: 39/255, blue: 51/255)
    static let muted = Color(red: 156/255, green: 163/255, blue: 175/255)
    static let green = Color(red: 48/255, green: 209/255, blue: 88/255)
    static let red = Color(red: 1, green: 69/255, blue: 58/255)
    static let blue = Color(red: 10/255, green: 132/255, blue: 1)
    static let stroke = Color.white.opacity(0.075)
    static let radius: CGFloat = 22
    static func color(_ kind: CashKind) -> Color {
        switch kind { case .income: return green; case .expense: return red; case .transfer: return blue }
    }
}

struct CashCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CashTheme.card, in: RoundedRectangle(cornerRadius: CashTheme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CashTheme.radius).strokeBorder(CashTheme.stroke))
    }
}

struct CashSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading) }
}

struct CashBrandImage: View {
    let filename: String
    var maxHeight: CGFloat = 72
    var body: some View {
        Group {
            if let path = Bundle.main.path(forResource: filename, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Image(systemName: "building.columns.fill")
                    .resizable().scaledToFit().foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .leading)
        .accessibilityLabel(filename)
    }
}

struct CashSplash: View {
    @State private var revealed = false
    @State private var illuminated = false

    // Se carga una sola vez; evita volver a decodificar el PNG en cada frame.
    private static let cachedLogo: UIImage? = {
        guard let path = Bundle.main.path(forResource: "CashLogo", ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CashTheme.background.ignoresSafeArea()

                // Animación liviana: sin blur animado ni gradientes giratorios.
                Circle()
                    .fill(RadialGradient(
                        colors: [CashTheme.blue.opacity(0.24), CashTheme.blue.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 15,
                        endRadius: 175
                    ))
                    .frame(width: min(geometry.size.width * 0.95, 370),
                           height: min(geometry.size.width * 0.95, 370))
                    .scaleEffect(illuminated ? 1.04 : 0.82)
                    .opacity(illuminated ? 1 : 0.25)

                Circle()
                    .strokeBorder(CashTheme.blue.opacity(0.36), lineWidth: 2)
                    .frame(width: min(geometry.size.width * 0.94, 365),
                           height: min(geometry.size.width * 0.94, 365))
                    .scaleEffect(illuminated ? 1 : 0.83)
                    .opacity(revealed ? 0.80 : 0)

                VStack(spacing: 16) {
                    Spacer()
                    Group {
                        if let image = Self.cachedLogo {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            Image(systemName: "wallet.pass.fill")
                                .resizable().scaledToFit().foregroundStyle(CashTheme.blue)
                        }
                    }
                    .frame(width: min(geometry.size.width * 0.86, 356),
                           height: min(geometry.size.width * 0.86, 356))
                    .scaleEffect(revealed ? 1 : 0.76)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? -5 : 16)
                    .shadow(color: CashTheme.blue.opacity(illuminated ? 0.30 : 0), radius: 16)
                    Text("Cash")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 12)
                    Spacer()
                    Text("Powered by Bryan Ramos")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CashTheme.muted)
                        .padding(.bottom, 25)
                        .opacity(revealed ? 1 : 0)
                }
                .padding(.horizontal, 12)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { revealed = true }
            withAnimation(.easeInOut(duration: 1.45)) { illuminated = true }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CashDraft: Identifiable {
    let id = UUID()
    var operation: CashOperation?
    var kind: CashKind
    var date: Date
}

struct CashMonthlyRoute: Identifiable {
    let id = UUID()
    var kind: CashKind
    var month: Date
}

struct CashAccountRoute: Identifiable {
    let id = UUID()
    let account: CashAccount
    let month: Date
}

struct ContentView: View {
    @StateObject private var store = CashStore()
    @State private var draft: CashDraft?
    @State private var accountRoute: CashAccountRoute?
    @State private var monthRoute: CashMonthlyRoute?
    @State private var showSettings = false
    @State private var showingSplash = true
    var body: some View {
        ZStack {
            TabView {
                Tab("Inicio", systemImage: "house.fill") {
                    CashHome(store: store, splashVisible: showingSplash, showSettings: { showSettings = true }, showMonth: { kind, month in
                        monthRoute = CashMonthlyRoute(kind: kind, month: month)
                    }, showAccount: { account, month in
                        accountRoute = CashAccountRoute(account: account, month: month)
                    })
                }
                Tab("Calendario", systemImage: "calendar") {
                    CashCalendar(store: store, edit: edit, add: add)
                }
                Tab("Añadir", systemImage: "plus.circle.fill") {
                    CashAdd(add: add)
                }
                Tab("Movimientos", systemImage: "list.bullet.rectangle.fill") {
                    CashMovements(store: store, edit: edit)
                }
                Tab("Análisis", systemImage: "chart.bar.fill") {
                    CashAnalysis(store: store, edit: edit)
                }
            }
            .tint(CashTheme.blue)
            if showingSplash {
                CashSplash().transition(.opacity)
                    .zIndex(2)
                    .task {
                        try? await Task.sleep(for: .milliseconds(2000))
                        withAnimation(.easeOut(duration: 0.20)) { showingSplash = false }
                    }
            }
        }
        .preferredColorScheme(.dark)
        .environmentObject(store)
        .sheet(item: $draft) { item in
            CashEditor(store: store, draft: item)
        }
        .sheet(item: $monthRoute) { route in
            CashMonthDetail(store: store, kind: route.kind, month: route.month)
        }
        .sheet(item: $accountRoute) { route in
            CashAccountDetail(store: store, account: route.account, initialMonth: route.month)
        }
        .sheet(isPresented: $showSettings) {
            CashSettings(store: store)
        }
        .alert("Aviso de datos", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("Entendido") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }
    private func add(_ kind: CashKind, _ date: Date) {
        draft = CashDraft(operation: nil, kind: kind, date: Date())
    }
    private func edit(_ operation: CashOperation) {
        draft = CashDraft(operation: operation, kind: operation.kind, date: operation.date)
    }
}

// Transición de texto numérico: solo anima una representación visual.
// Los importes reales se obtienen siempre del CashStore en centavos enteros.
private struct CashCountingAmount: View, Animatable {
    let actualCents: Int64
    var fraction: Double

    nonisolated var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        let displayedCents: Int64
        if fraction >= 1 {
            displayedCents = actualCents
        } else if fraction <= 0 {
            displayedCents = 0
        } else {
            let estimate = (Double(actualCents) * fraction).rounded(.towardZero)
            displayedCents = Int64(estimate)
        }
        return Text(CashMoney.formatted(displayedCents))
            .contentTransition(.numericText())
    }
}

struct CashHome: View {
    @ObservedObject var store: CashStore
    let splashVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showSettings: () -> Void
    let showMonth: (CashKind, Date) -> Void
    let showAccount: (CashAccount, Date) -> Void
    @State private var month = Date()
    @State private var balanceAnimationProgress = 0.0
    @State private var animationTask: Task<Void, Never>?
    // Preferencia independiente y persistente del SALDO TOTAL.
    @AppStorage("cash.hideTotalBalance.v1") private var hideTotalBalance = false
    // Lista de bancos ocultos persistida entre aperturas (sin afectar Efectivo).
    @AppStorage("cash.hiddenBankBalances.v1") private var hiddenBankCodes = ""

    private func isHidden(_ account: CashAccount) -> Bool {
        guard account != .cash else { return false }
        return Set(hiddenBankCodes.split(separator: ",").map { String($0) }).contains(account.rawValue)
    }

    private func toggleHidden(_ account: CashAccount) {
        guard account != .cash else { return }
        var ids = Set(hiddenBankCodes.split(separator: ",").map { String($0) })
        if ids.contains(account.rawValue) { ids.remove(account.rawValue) }
        else { ids.insert(account.rawValue) }
        hiddenBankCodes = ids.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cash").font(.system(size: 37, weight: .heavy, design: .rounded))
                                Text("Tus finanzas, en orden").font(.subheadline).foregroundStyle(CashTheme.muted)
                            }
                            Spacer(minLength: 8)
                            Button(action: showSettings) {
                                Image(systemName: "gearshape.fill").font(.title3)
                                    .frame(width: 45, height: 45)
                                    .background(CashTheme.raised, in: Circle())
                            }.accessibilityLabel("Configuración")
                        }
                        CashSectionTitle("Mis cuentas")
                        institution(.cash)
                        ForEach(store.accounts.filter { $0 != .cash }) { account in
                            institution(account)
                        }
                        totalBalance
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                    .frame(width: geometry.size.width)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(CashTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        // Al entrar a Inicio, el contador recorre 0 -> saldo real durante 2 s.
        // No toca los datos: es únicamente una transición de interfaz.
        .onAppear { if !splashVisible { animateBalances() } }
        // CashHome existe detrás del splash; iniciamos el conteo al terminar
        // el splash para que el usuario realmente vea los ~2 segundos.
        .onChange(of: splashVisible) { _, isSplashVisible in
            if !isSplashVisible { animateBalances() }
        }
        .onDisappear { animationTask?.cancel(); animationTask = nil }
    }

    private func animateBalances() {
        animationTask?.cancel()
        if reduceMotion {
            balanceAnimationProgress = 1
            return
        }
        balanceAnimationProgress = 0
        animationTask = Task { @MainActor in
            // Da tiempo a pintar el primer fotograma en cero antes de animar.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 2.0)) {
                balanceAnimationProgress = 1
            }
        }
    }

    // Todas las tarjetas mantienen idénticas dimensiones; el saldo es el
    // elemento principal. BAC y Atlántida conservan exactamente su apariencia.
    // Occidente y Sagrada usan una superficie blanca completa para integrar
    // el fondo de sus logotipos, sin una tarjeta blanca secundaria.
    private func institution(_ account: CashAccount) -> some View {
        let profile = store.accountItem(account)
        let style = profile?.colorStyle ?? "original"
        let fillsWithPhoto = (profile?.imageFillsCard ?? false) && profile?.imageData != nil
        let isWhite = !fillsWithPhoto && (style == "blanco" || (style == "original" && (account == .occidente || account == .sagrada)))
        let foreground: Color = isWhite ? CashTheme.background : .white
        let cardColors: [Color] = {
            switch style {
            case "blanco": return [.white, .white]
            case "azul": return [CashTheme.blue, Color(red: 0.06, green: 0.23, blue: 0.63)]
            case "rojo": return [CashTheme.red, Color(red: 0.52, green: 0.02, blue: 0.13)]
            case "verde": return [CashTheme.green, Color(red: 0.04, green: 0.29, blue: 0.18)]
            case "grafito": return [CashTheme.raised, CashTheme.background]
            default: return account.bankColors
            }
        }()

        return Button { showAccount(account, month) } label: {
            VStack(alignment: .leading, spacing: 13) {
                if fillsWithPhoto {
                    Color.clear.frame(height: 74)
                } else if let data = profile?.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 74)
                } else if account == .cash {
                    // Decoración abstracta, NO contiene el ícono de Cash.
                    HStack(alignment: .center, spacing: 7) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(.white.opacity(0.60))
                                .frame(width: 7, height: 7)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(.white.opacity(0.56))
                    }
                    .frame(height: 74)
                } else if !account.assetName.isEmpty {
                    CashBrandImage(filename: account.assetName, maxHeight: 74)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 74)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 47, weight: .medium))
                        .foregroundStyle(foreground.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 74)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.accountName(account))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(foreground.opacity(isWhite ? 0.83 : 0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.73)
                    Text(account == .cash ? "EFECTIVO DISPONIBLE" : "SALDO DISPONIBLE")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(isWhite ? CashTheme.blue : .white.opacity(0.84))
                    Group {
                        if isHidden(account) {
                            Text("L ******")
                        } else {
                            CashCountingAmount(actualCents: store.balance(account),
                                               fraction: balanceAnimationProgress)
                        }
                    }
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 218)
            .background {
                ZStack(alignment: .topTrailing) {
                    if fillsWithPhoto, let data = profile?.imageData, let image = UIImage(data: data) {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .overlay(LinearGradient(colors: [.black.opacity(0.12),
                                                                 .black.opacity(0.26), .black.opacity(0.82)],
                                                        startPoint: .top, endPoint: .bottom))
                        }
                    } else if isWhite {
                        Color.white
                    } else if account == .cash {
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.49, blue: 0.98),
                                     Color(red: 0.06, green: 0.24, blue: 0.68)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        Circle()
                            .strokeBorder(.white.opacity(0.14), lineWidth: 2)
                            .frame(width: 192, height: 192)
                            .offset(x: 49, y: -102)
                        Circle()
                            .fill(.white.opacity(0.07))
                            .frame(width: 116, height: 116)
                            .offset(x: -8, y: 56)
                    } else {
                        LinearGradient(colors: cardColors,
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CashTheme.radius, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: CashTheme.radius)
                .strokeBorder(isWhite ? Color.black.opacity(0.07) : Color.white.opacity(0.13)))
            .contentShape(RoundedRectangle(cornerRadius: CashTheme.radius))
        }
        .buttonStyle(.plain)
        // El ojo no está anidado dentro del botón de la tarjeta:
        // tocarlo SOLO oculta/muestra el saldo y no abre movimientos.
        .overlay(alignment: .topTrailing) {
            if account != .cash {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { toggleHidden(account) }
                } label: {
                    Image(systemName: isHidden(account) ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isWhite ? CashTheme.background : .white)
                        .frame(width: 44, height: 44)
                        .background(isWhite ? Color.black.opacity(0.065) : Color.black.opacity(0.23), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(11)
                .accessibilityLabel(isHidden(account) ? "Mostrar saldo de \(store.accountName(account))" : "Ocultar saldo de \(store.accountName(account))")
            }
        }
        .accessibilityLabel(isHidden(account) ? "\(store.accountName(account)), saldo oculto. Ver movimientos del mes" : "\(store.accountName(account)), saldo disponible \(CashMoney.formatted(store.balance(account))). Ver movimientos del mes")
    }
    private var totalBalance: some View {
        CashCard {
            HStack(spacing: 8) {
                Label("SALDO TOTAL DISPONIBLE", systemImage: "sum")
                    .font(.caption.bold())
                    .tracking(0.5)
                    .foregroundStyle(CashTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                Spacer(minLength: 5)
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        hideTotalBalance.toggle()
                    }
                } label: {
                    Image(systemName: hideTotalBalance ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(CashTheme.raised, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hideTotalBalance ? "Mostrar saldo total" : "Ocultar saldo total")
            }
            Group {
                if hideTotalBalance {
                    Text("L ******")
                } else {
                    CashCountingAmount(actualCents: store.totalBalance,
                                       fraction: balanceAnimationProgress)
                }
            }
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.top, 5)
            .accessibilityLabel(hideTotalBalance ? "Saldo total oculto" :
                                "Saldo total disponible " + CashMoney.formatted(store.totalBalance))
        }
    }

}

extension CashAccount {
    var assetName: String {
        switch rawValue {
        case "cash": return "CashLogo"
        case "occidente": return "Banco_Occidente"
        case "bac": return "BAC"
        case "atlantida": return "Banco_Atlantida"
        case "sagrada": return "Cooperativa_Sagrada_Familia"
        default: return ""
        }
    }
    var bankColors: [Color] {
        switch rawValue {
        case "cash": return [CashTheme.blue, CashTheme.secondary]
        case "occidente": return [Color(red: 0.06, green: 0.21, blue: 0.13), Color(red: 0.03, green: 0.10, blue: 0.10)]
        case "bac": return [Color(red: 0.91, green: 0.02, blue: 0.18), Color(red: 0.57, green: 0.01, blue: 0.12)]
        case "atlantida": return [Color(red: 0.80, green: 0.07, blue: 0.15), Color(red: 0.44, green: 0.03, blue: 0.10)]
        case "sagrada": return [Color(red: 0.10, green: 0.34, blue: 0.22), Color(red: 0.04, green: 0.20, blue: 0.13)]
        default: return [CashTheme.blue, CashTheme.secondary]
        }
    }
    var accent: Color {
        switch rawValue {
        case "occidente": return .orange
        case "bac": return CashTheme.red
        case "atlantida": return .red
        case "sagrada": return CashTheme.green
        default: return CashTheme.blue
        }
    }
}
