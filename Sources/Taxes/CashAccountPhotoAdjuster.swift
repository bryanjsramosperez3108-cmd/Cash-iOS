import SwiftUI
import UIKit

// V11: la selección desde Fotos no se guarda directamente. Antes de guardar,
// el usuario ajusta la imagen y Cash exporta una versión liviana y recortada.
struct CashPickedAccountPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct CashAccountPhotoAdjuster: View {
    let image: UIImage
    let onApply: (Data, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fullCard: Bool
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero
    @State private var errorText: String?

    private let canvasWidth: CGFloat = 284
    private var canvasHeight: CGFloat { fullCard ? 174 : 112 }

    init(image: UIImage, initialFullCard: Bool, onApply: @escaping (Data, Bool) -> Void) {
        self.image = image
        self.onApply = onApply
        _fullCard = State(initialValue: initialFullCard)
    }

    private var displaySize: CGSize {
        let imageWidth = max(1, image.size.width)
        let imageHeight = max(1, image.size.height)
        let fit = min(canvasWidth / imageWidth, canvasHeight / imageHeight)
        let factor = fit * zoom * gestureZoom
        return CGSize(width: imageWidth * factor, height: imageHeight * factor)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 17) {
                Text("Pellizca con dos dedos para acercar o alejar. Arrastra la imagen hasta dejarla como deseas.")
                    .font(.subheadline)
                    .foregroundStyle(CashTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 15)

                Toggle("Fotografía de fondo completo", isOn: $fullCard)
                    .tint(CashTheme.blue)
                    .padding(.horizontal, 14)

                ZStack {
                    Color.white
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .offset(x: offset.width + gestureOffset.width,
                                y: offset.height + gestureOffset.height)
                }
                .frame(width: canvasWidth, height: canvasHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(CashTheme.blue.opacity(0.65), lineWidth: 2))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .updating($gestureOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            offset.width += value.translation.width
                            offset.height += value.translation.height
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($gestureZoom) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            zoom = min(7, max(0.55, zoom * value))
                        }
                )
                .padding(.top, 8)

                VStack(spacing: 5) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: Binding(get: { Double(zoom) },
                                              set: { zoom = CGFloat($0) }), in: 0.55...7)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .font(.caption)
                    .tint(CashTheme.blue)
                    Button("Centrar fotografía") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            zoom = 1
                            offset = .zero
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 18)

                Text(fullCard ? "Se mostrará como fondo de la tarjeta, con un degradado para poder leer el saldo." :
                     "Se mostrará como logotipo en la parte superior de la tarjeta.")
                    .font(.caption)
                    .foregroundStyle(CashTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)
                Button {
                    guard let data = renderedImageData() else {
                        errorText = "No fue posible optimizar esta fotografía. Elige otra imagen e inténtalo nuevamente."
                        return
                    }
                    onApply(data, fullCard)
                    dismiss()
                } label: {
                    Label("Usar esta fotografía", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(CashTheme.blue)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .padding(.top, 20)
            .background(CashTheme.background.ignoresSafeArea())
            .navigationTitle("Ajustar fotografía")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } } }
            .alert("No se pudo guardar la imagen", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) { Button("Entendido") { errorText = nil } }
            message: { Text(errorText ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    // El resultado pesa como máximo 500 kB, por debajo del límite del almacén
    // y del respaldo JSON. Se conserva EXACTAMENTE el encuadre seleccionado.
    private func renderedImageData() -> Data? {
        let imageWidth = max(1, image.size.width)
        let imageHeight = max(1, image.size.height)
        let fit = min(canvasWidth / imageWidth, canvasHeight / imageHeight)
        let displayedWidth = imageWidth * fit * zoom
        let displayedHeight = imageHeight * fit * zoom
        let drawingRect = CGRect(
            x: (canvasWidth - displayedWidth) / 2 + offset.width,
            y: (canvasHeight - displayedHeight) / 2 + offset.height,
            width: displayedWidth,
            height: displayedHeight
        )
        // Imágenes extremadamente detalladas se reducen progresivamente sin
        // cambiar encuadre, hasta obtener un archivo compatible con CashLedger.
        for outputWidth in [CGFloat(850), 720, 590, 470] {
            let scale = outputWidth / canvasWidth
            let outputSize = CGSize(width: outputWidth, height: canvasHeight * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
            let cropped = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: outputSize))
                image.draw(in: CGRect(x: drawingRect.minX * scale, y: drawingRect.minY * scale,
                                      width: drawingRect.width * scale, height: drawingRect.height * scale))
            }
            for quality in [0.87, 0.76, 0.65, 0.55, 0.43, 0.34] {
                if let data = cropped.jpegData(compressionQuality: quality), data.count <= 500_000 {
                    return data
                }
            }
        }
        return nil
    }

}

// Vista previa con el mismo alto, jerarquía y colores de Inicio.
// Nunca se usa como sustituto de una operación real sobre el almacén.
struct CashEditableAccountPreview: View {
    let account: CashAccount
    let name: String
    let amount: String
    let imageData: Data?
    let style: String
    let imageFillsCard: Bool

    private var fullImage: UIImage? {
        guard imageFillsCard, let data = imageData else { return nil }
        return UIImage(data: data)
    }
    private var isWhite: Bool {
        fullImage == nil && (style == "blanco" ||
            (style == "original" && (account == .occidente || account == .sagrada)))
    }
    private var textColor: Color { isWhite ? CashTheme.background : .white }
    private var colors: [Color] {
        switch style {
        case "blanco": [.white, .white]
        case "azul": [CashTheme.blue, Color(red: 0.06, green: 0.23, blue: 0.63)]
        case "rojo": [CashTheme.red, Color(red: 0.52, green: 0.02, blue: 0.13)]
        case "verde": [CashTheme.green, Color(red: 0.04, green: 0.29, blue: 0.18)]
        case "grafito": [CashTheme.raised, CashTheme.background]
        default: account.bankColors
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if fullImage != nil {
                    Color.clear
                } else if let data = imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if !account.assetName.isEmpty && account != .cash {
                    CashBrandImage(filename: account.assetName, maxHeight: 74)
                } else {
                    Image(systemName: account == .cash ? "sparkles" : "building.columns.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(textColor.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 74)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Text(name.isEmpty ? "Nombre de la cuenta" : name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(textColor.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(account == .cash ? "EFECTIVO DISPONIBLE" : "SALDO DISPONIBLE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isWhite ? CashTheme.blue : .white.opacity(0.85))
                Text(CashMoney.formatted(CashMoney.parse(amount) ?? 0))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 218)
        .background {
            ZStack {
                if let image = fullImage {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .overlay(LinearGradient(colors: [.black.opacity(0.12),
                                                             .black.opacity(0.26), .black.opacity(0.82)],
                                                    startPoint: .top, endPoint: .bottom))
                    }
                } else {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CashTheme.radius))
        .overlay(RoundedRectangle(cornerRadius: CashTheme.radius)
            .strokeBorder(Color.white.opacity(0.15)))
        .accessibilityLabel("Vista previa de tarjeta. " + (name.isEmpty ? "Nueva cuenta" : name))
    }
}
