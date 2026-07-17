import AVFoundation
import Foundation

@MainActor
final class PCMPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ data: Data) {
        guard !data.isEmpty else { return }
        let frameCount = UInt32(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { source in
            guard let address = source.baseAddress, let destination = buffer.int16ChannelData?[0] else { return }
            destination.update(from: address.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
        }
        do {
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer)
            if !player.isPlaying { player.play() }
        } catch {
            return
        }
    }

    func stop() {
        player.stop()
    }
}
