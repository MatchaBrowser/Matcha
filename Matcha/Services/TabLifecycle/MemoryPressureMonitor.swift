import Dispatch

/// Niveau d'une alerte mémoire du système.
nonisolated enum MemoryPressureLevel: String, Sendable {
    case warning
    case critical
}

/// Alertes mémoire du système (`DispatchSource.makeMemoryPressureSource`), reçues sur le fil principal ; le retour à la
/// normale est ignoré. La source est arrêtée avec l'objet.
final nonisolated class MemoryPressureMonitor {
    private let source: any DispatchSourceMemoryPressure

    init(handler: @escaping @MainActor @Sendable (MemoryPressureLevel) -> Void) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [unowned source] in
            let event = source.data
            let level: MemoryPressureLevel? = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : nil
            guard let level else {
                return
            }
            MainActor.assumeIsolated { handler(level) }
        }
        source.activate()
        self.source = source
    }

    deinit {
        source.cancel()
    }
}
