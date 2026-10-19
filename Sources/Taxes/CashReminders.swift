import SwiftUI
import UserNotifications

// Dos avisos locales y opcionales cada día. No requiere servidor ni conexión.
// Cash no modifica datos financieros cuando muestra notificaciones.
struct CashReminderSettings: View {
    @AppStorage("cash.reminders.morningEnabled.v1") private var morningEnabled = false
    @AppStorage("cash.reminders.eveningEnabled.v1") private var eveningEnabled = false
    @AppStorage("cash.reminders.morningMinutes.v1") private var morningMinutes = 8 * 60
    @AppStorage("cash.reminders.eveningMinutes.v1") private var eveningMinutes = 20 * 60
    @State private var notificationError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Recordar registrar ingresos y gastos", isOn: $morningEnabled)
                    .tint(CashTheme.blue)
                    .onChange(of: morningEnabled) { _, _ in synchronize() }
                if morningEnabled {
                    DatePicker("Hora del primer aviso", selection: clock(isMorning: true), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Primer recordatorio")
            } footer: {
                Text("Una notificación cada día para mantener actualizados tus movimientos.")
            }

            Section {
                Toggle("Recordar revisar los movimientos del día", isOn: $eveningEnabled)
                    .tint(CashTheme.blue)
                    .onChange(of: eveningEnabled) { _, _ in synchronize() }
                if eveningEnabled {
                    DatePicker("Hora del segundo aviso", selection: clock(isMorning: false), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Segundo recordatorio")
            } footer: {
                Text("Un aviso diario distinto, dedicado a revisar tus operaciones pendientes.")
            }

            Section {
                Text("Los horarios se guardan en este iPhone. iOS puede demorar una notificación según los modos de concentración, permisos y gestión del sistema.")
                    .font(.footnote)
                    .foregroundStyle(CashTheme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(CashTheme.background)
        .navigationTitle("Notificaciones")
        .navigationBarTitleDisplayMode(.inline)
        .alert("No fue posible activar los avisos", isPresented: Binding(
            get: { notificationError != nil },
            set: { if !$0 { notificationError = nil } }
        )) {
            Button("Entendido") { notificationError = nil }
        } message: {
            Text(notificationError ?? "")
        }
        .task { await updateRequests(askPermission: false) }
    }

    // El selector de hora usa Date, pero conservamos solo horas/minutos.
    private func clock(isMorning: Bool) -> Binding<Date> {
        Binding(get: {
            let minutes = isMorning ? morningMinutes : eveningMinutes
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = minutes / 60
            components.minute = minutes % 60
            return Calendar.current.date(from: components) ?? Date()
        }, set: { chosen in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: chosen)
            let value = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
            if isMorning { morningMinutes = value } else { eveningMinutes = value }
            synchronize()
        })
    }

    private func synchronize() {
        Task { @MainActor in await updateRequests(askPermission: true) }
    }

    @MainActor
    private func updateRequests(askPermission: Bool) async {
        let center = UNUserNotificationCenter.current()
        let ids = ["cash.reminder.morning.v1", "cash.reminder.evening.v1"]

        do {
            var authorized = false
            if askPermission && (morningEnabled || eveningEnabled) {
                authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } else {
                let settings = await center.notificationSettings()
                authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
            guard authorized || (!morningEnabled && !eveningEnabled) else {
                center.removePendingNotificationRequests(withIdentifiers: ids)
                notificationError = "Activa las notificaciones de Cash en Ajustes del iPhone para recibir los avisos diarios."
                return
            }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            if morningEnabled {
                try await schedule(
                    center: center, id: ids[0], minutes: morningMinutes,
                    title: "Cash · Actualiza tus finanzas",
                    body: "Recuerda anotar los ingresos y gastos de hoy."
                )
            }
            if eveningEnabled {
                try await schedule(
                    center: center, id: ids[1], minutes: eveningMinutes,
                    title: "Cash · Revisa tu día",
                    body: "Comprueba que tus gastos, ingresos y transferencias estén completos."
                )
            }
        } catch {
            notificationError = error.localizedDescription
        }
    }

    @MainActor
    private func schedule(center: UNUserNotificationCenter,
                          id: String, minutes: Int, title: String, body: String) async throws {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
    }
}
