import Carbon.HIToolbox
import Foundation

final class GlobalHotkeyManager {
    private static let hotkeyID = EventHotKeyID(signature: OSType(0x5644434B), id: 1)

    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    private static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        var identifier = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard identifier.id == 1 else { return noErr }
        if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
            manager.onPress?()
        } else {
            manager.onRelease?()
        }
        return noErr
    }

    func start(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        guard hotkeyRef == nil else { return }

        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventCallback,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard installStatus == noErr else { return }
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Z),
            UInt32(optionKey),
            Self.hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    func stop() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        stop()
    }
}
