import AVFoundation

/// Efectos breves de Cash: sonido distinto para ingresos y gastos.
/// La categoría .ambient de iOS respeta el interruptor de silencio y
/// permite coexistir con el audio de otras aplicaciones.
@MainActor
final class CashSoundPlayer {
    static let shared = CashSoundPlayer()
    private var player: AVAudioPlayer?

    private init() {}

    func play(for kind: CashKind) {
        let soundName: String
        switch kind {
        case .income: soundName = "CashIngreso"
        case .expense: soundName = "CashGasto"
        case .transfer: return
        }
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "wav") else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.volume = 0.55
            audio.prepareToPlay()
            player = audio
            audio.play()
        } catch {
            // Un problema de sonido jamás debe revertir un registro guardado.
        }
    }
}
