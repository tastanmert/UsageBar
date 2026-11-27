import AppKit
import Carbon.HIToolbox

/// One system-wide shortcut that opens and closes the panel, from a short list of combinations
/// (Settings > General). Carbon's hot key API: it needs no Accessibility permission, and the key is
/// delivered to UsageBar only, never typed into the frontmost app.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    enum Choice: String, CaseIterable, Identifiable {
        case off
        case optionCommandU
        case controlOptionU
        case controlOptionCommandU

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: L("Off")
            case .optionCommandU: "⌥⌘U"
            case .controlOptionU: "⌃⌥U"
            case .controlOptionCommandU: "⌃⌥⌘U"
            }
        }

        fileprivate var modifiers: UInt32 {
            switch self {
            case .off: 0
            case .optionCommandU: UInt32(optionKey | cmdKey)
            case .controlOptionU: UInt32(controlKey | optionKey)
            case .controlOptionCommandU: UInt32(controlKey | optionKey | cmdKey)
            }
        }
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Whether the combination could be registered (another app may own it).
    private(set) var registered = false

    private init() {}

    func apply(_ choice: Choice) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registered = false
        guard choice != .off else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5542_4152), id: 1)   // "UBAR"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_U), choice.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        hotKey = ref
        registered = true
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in StatusItemController.shared?.toggleFromHotKey() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
