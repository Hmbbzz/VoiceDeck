import AVFoundation
import Foundation

@MainActor
final class PCMPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    private var scheduledBufferCount = 0

    var onPlaybackStateChange: ((Bool) -> Void)?
    /// `AVAudioPlayerNode.isPlaying` stays true while its node is active, even
    /// after its final buffer has drained. The queued buffer count reflects
    /// audible playback and lets the UI dismiss its stop control promptly.
    var isPlaying: Bool { scheduledBufferCount > 0 }

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
            scheduledBufferCount += 1
            onPlaybackStateChange?(true)
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
                    self.onPlaybackStateChange?(self.isPlaying)
                }
            }
            if !player.isPlaying { player.play() }
        } catch {
            return
        }
    }

    func stop() {
        player.stop()
        scheduledBufferCount = 0
        onPlaybackStateChange?(false)
    }
}
