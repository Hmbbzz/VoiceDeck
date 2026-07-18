import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    static let preferenceKey = "voiceDeck.audioInputDeviceUID"

    let id: AudioDeviceID
    let uid: String
    let name: String

    static func availableDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        var ids = Array(repeating: AudioDeviceID(), count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        let didReadDevices = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            ) == noErr
        }
        guard didReadDevices else { return [] }

        return ids.compactMap { id in
            guard hasInputStreams(id),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, for: id),
                  let name = stringProperty(kAudioObjectPropertyName, for: id) else {
                return nil
            }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func selectedDevice() -> AudioInputDevice? {
        let uid = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        guard !uid.isEmpty else { return nil }
        return availableDevices().first { $0.uid == uid }
    }

    static func defaultDeviceName() -> String? {
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID) == noErr else {
            return nil
        }
        return stringProperty(kAudioObjectPropertyName, for: deviceID)
    }

    private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var dataSize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr && dataSize > 0
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, for id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }
}

enum AudioInputDeviceError: LocalizedError {
    case unavailable
    case selectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "所选麦克风当前不可用。请在设置中重新选择输入设备。"
        case let .selectionFailed(name):
            "无法启用麦克风“\(name)”。请检查它是否已连接且没有被系统禁用。"
        }
    }
}

func configureInputDevice(for inputNode: AVAudioInputNode) throws -> String? {
    let selectedUID = UserDefaults.standard.string(forKey: AudioInputDevice.preferenceKey) ?? ""
    guard !selectedUID.isEmpty else { return nil }
    guard let device = AudioInputDevice.selectedDevice() else {
        throw AudioInputDeviceError.unavailable
    }
    guard let inputUnit = inputNode.audioUnit else {
        throw AudioInputDeviceError.selectionFailed(device.name)
    }

    var deviceID = device.id
    let status = AudioUnitSetProperty(
        inputUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard status == noErr else {
        throw AudioInputDeviceError.selectionFailed(device.name)
    }
    return device.name
}
