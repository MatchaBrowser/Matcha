import Dispatch

/// Level of a system memory warning.
nonisolated enum MemoryPressureLevel: String, Sendable {
    case warning
    case critical
}

/// System memory warnings (`DispatchSource.makeMemoryPressureSource`), received on the main thread; the return to
/// normal is ignored. The source is stopped with the object.
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
