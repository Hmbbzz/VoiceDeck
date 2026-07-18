import Carbon.HIToolbox
import Foundation

final class GlobalHotkeyManager {
    private enum HotkeyID: UInt32 {
        case pushToTalk = 1
        case captureWindowContext = 2
    }

    private var eventHandler: EventHandlerRef?
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?
    private var onCaptureWindowContext: (() -> Void)?
    private var isPushToTalkPressed = false

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
        var modifiers: UInt32 = 0
        let modifierStatus = GetEventParameter(
            event,
            EventParamName(kEventParamKeyModifiers),
            EventParamType(typeUInt32),
            nil,
            MemoryLayout<UInt32>.size,
            nil,
            &modifiers
        )
        let hasShiftModifier = modifierStatus == noErr && modifiers & UInt32(shiftKey) != 0
        let eventKind = GetEventKind(event)
        if identifier.id == HotkeyID.pushToTalk.rawValue, eventKind == UInt32(kEventHotKeyPressed) {
            // Carbon can match Option-Shift-Z against the less specific Option-Z registration.
            guard !hasShiftModifier else { return noErr }
            guard !manager.isPushToTalkPressed else { return noErr }
            manager.isPushToTalkPressed = true
            manager.onPress?()
        } else if identifier.id == HotkeyID.pushToTalk.rawValue, eventKind == UInt32(kEventHotKeyReleased) {
            guard !hasShiftModifier else { return noErr }
            guard manager.isPushToTalkPressed else { return noErr }
            manager.isPushToTalkPressed = false
            manager.onRelease?()
        } else if identifier.id == HotkeyID.captureWindowContext.rawValue, eventKind == UInt32(kEventHotKeyPressed) {
            manager.onCaptureWindowContext?()
        }
        return noErr
    }

    func start(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onCaptureWindowContext: @escaping () -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCaptureWindowContext = onCaptureWindowContext
        guard hotkeyRefs.isEmpty else { return }

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
        register(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(optionKey), id: .pushToTalk)
        register(keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(optionKey), id: .captureWindowContext)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: HotkeyID) {
        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: OSType(0x5644434B), id: id.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        if status == noErr, let hotkeyRef {
            hotkeyRefs.append(hotkeyRef)
        }
    }

    func stop() {
        isPushToTalkPressed = false
        for hotkeyRef in hotkeyRefs {
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        stop()
    }
}
