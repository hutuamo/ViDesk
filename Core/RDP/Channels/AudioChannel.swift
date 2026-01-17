import Foundation
import AVFoundation

/// 音频通道
/// 负责远程音频的接收和播放
final class AudioChannel: @unchecked Sendable {
    // MARK: - 属性

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    private var isEnabled: Bool = true
    private var volume: Float = 1.0

    /// 音频缓冲区
    private var audioBufferQueue: [AVAudioPCMBuffer] = []
    private let bufferLock = NSLock()
    private let maxBufferCount = 10

    // MARK: - 初始化

    init() {
        setupAudioSession()
        setupAudioEngine()
    }

    deinit {
        stop()
    }

    // MARK: - 配置

    private func setupAudioSession() {
        #if os(iOS) || os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)

        // 默认格式: 44.1kHz, 2 channels, 16-bit
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)

        guard let format = audioFormat else { return }

        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    // MARK: - 控制

    /// 启动音频播放
    func start() -> Bool {
        guard let engine = audioEngine, let player = playerNode else { return false }

        do {
            try engine.start()
            player.play()
            return true
        } catch {
            print("Failed to start audio engine: \(error)")
            return false
        }
    }

    /// 停止音频播放
    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
    }

    /// 暂停音频
    func pause() {
        playerNode?.pause()
    }

    /// 恢复音频
    func resume() {
        playerNode?.play()
    }

    /// 设置音量
    func setVolume(_ volume: Float) {
        self.volume = max(0, min(1, volume))
        playerNode?.volume = self.volume
    }

    /// 启用/禁用音频
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            _ = start()
        } else {
            stop()
        }
    }

    // MARK: - 音频数据处理

    /// 接收音频数据
    func receiveAudioData(_ data: Data, format: AudioStreamFormat) {
        guard isEnabled else { return }

        // 更新格式（如果需要）
        if let newFormat = createAudioFormat(from: format), newFormat != audioFormat {
            audioFormat = newFormat
            reconfigureAudioEngine(with: newFormat)
        }

        // 转换为 PCM 缓冲区
        guard let buffer = createPCMBuffer(from: data) else { return }

        // 添加到队列
        enqueueBuffer(buffer)

        // 调度播放
        scheduleNextBuffer()
    }

    private func createAudioFormat(from format: AudioStreamFormat) -> AVAudioFormat? {
        return AVAudioFormat(
            standardFormatWithSampleRate: Double(format.sampleRate),
            channels: AVAudioChannelCount(format.channels)
        )
    }

    private func reconfigureAudioEngine(with format: AVAudioFormat) {
        guard let engine = audioEngine, let player = playerNode else { return }

        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }

        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        if wasRunning {
            try? engine.start()
            player.play()
        }
    }

    private func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        guard let format = audioFormat else { return nil }

        let frameCount = AVAudioFrameCount(data.count) / format.streamDescription.pointee.mBytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.floatChannelData?[0], baseAddress, data.count)
            }
        }

        return buffer
    }

    private func enqueueBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        // 限制缓冲区队列大小
        if audioBufferQueue.count >= maxBufferCount {
            audioBufferQueue.removeFirst()
        }

        audioBufferQueue.append(buffer)
    }

    private func scheduleNextBuffer() {
        bufferLock.lock()
        guard !audioBufferQueue.isEmpty else {
            bufferLock.unlock()
            return
        }
        let buffer = audioBufferQueue.removeFirst()
        bufferLock.unlock()

        playerNode?.scheduleBuffer(buffer) { [weak self] in
            self?.scheduleNextBuffer()
        }
    }
}

/// 音频流格式
struct AudioStreamFormat {
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int

    static var `default`: AudioStreamFormat {
        AudioStreamFormat(sampleRate: 44100, channels: 2, bitsPerSample: 16)
    }
}
