import Foundation
import Combine
import Speech
import AVFoundation

// MARK: - 独立权限助手（完全脱离 MainActor，确保系统后台线程回调时不会触发 Swift 并发隔离断言）
private enum SpeechPermissionHelper {
    static func requestSpeechRecognition() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authStatus in
                continuation.resume(returning: authStatus == .authorized)
            }
        }
    }

    static func requestMicrophone() async -> Bool {
        if #available(macOS 14.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            if status == .granted { return true }
            if status == .denied { return false }
            return await AVAudioApplication.requestRecordPermission()
        } else {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .authorized { return true }
            if status == .denied || status == .restricted { return false }
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

// MARK: - 音频采集与语音识别后台桥接（完全脱离 MainActor 隔离，防止 CoreAudio/Speech 线程回调时触发 Swift 并发隔离断言）
private func attachAudioTap(to inputNode: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest) {
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
    }
}

private func startSpeechRecognitionTask(
    recognizer: SFSpeechRecognizer,
    request: SFSpeechAudioBufferRecognitionRequest,
    onResult: @escaping @Sendable (String?, Bool, Bool) -> Void
) -> SFSpeechRecognitionTask {
    return recognizer.recognitionTask(with: request) { result, error in
        let transcription = result?.bestTranscription.formattedString
        let isFinal = result?.isFinal ?? false
        let hasError = (error != nil)
        onResult(transcription, isFinal, hasError)
    }
}

// MARK: - 原生语音听写管理器
@MainActor
public final class SpeechManager: NSObject, ObservableObject {
    public static let shared = SpeechManager()

    @Published public var isRecording: Bool = false
    @Published public var recognizedText: String = ""
    @Published public var errorMessage: String? = nil

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var autoStopTask: Task<Void, Never>?
    private var hasDeliveredFinished: Bool = false

    public override init() {
        super.init()
        // zh-CN 识别器原生支持中英混合识别（中文+英文均可）
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
    }

    public func requestPermissions() async -> Bool {
        let speechGranted = await SpeechPermissionHelper.requestSpeechRecognition()
        guard speechGranted else {
            self.errorMessage = "请在系统设置中授予“语音识别”权限"
            return false
        }

        let micGranted = await SpeechPermissionHelper.requestMicrophone()
        guard micGranted else {
            self.errorMessage = "请在系统设置中授予“麦克风”权限"
            return false
        }

        return true
    }

    public func toggleRecording(
        timeoutSeconds: Int = 3,
        onUpdate: @escaping @MainActor @Sendable (String) -> Void,
        onFinished: @escaping @MainActor @Sendable (String) -> Void
    ) {
        if isRecording {
            stopRecording(onFinished: onFinished)
        } else {
            startRecording(timeoutSeconds: timeoutSeconds, onUpdate: onUpdate, onFinished: onFinished)
        }
    }

    public func startRecording(
        timeoutSeconds: Int = 3,
        onUpdate: @escaping @MainActor @Sendable (String) -> Void,
        onFinished: @escaping @MainActor @Sendable (String) -> Void
    ) {
        // 先重置上一次会话
        cancelRecording()
        hasDeliveredFinished = false

        Task {
            let authorized = await requestPermissions()
            guard authorized else { return }

            guard let speechRecognizer = self.speechRecognizer, speechRecognizer.isAvailable else {
                self.errorMessage = "语音识别服务当前不可用，请稍后重试"
                return
            }

            do {
                let engine = AVAudioEngine()
                self.audioEngine = engine

                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                self.recognitionRequest = request

                let inputNode = engine.inputNode
                inputNode.removeTap(onBus: 0)

                var recordingFormat = inputNode.outputFormat(forBus: 0)
                if recordingFormat.sampleRate == 0 || recordingFormat.channelCount == 0 {
                    recordingFormat = inputNode.inputFormat(forBus: 0)
                }

                // 防御 macOS 虚拟音频或无有效采样率时的致命崩溃
                guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                    self.errorMessage = "未检测到可用的麦克风输入设备"
                    self.cancelRecording()
                    return
                }

                attachAudioTap(to: inputNode, format: recordingFormat, request: request)

                engine.prepare()
                try engine.start()

                self.isRecording = true
                self.errorMessage = nil
                self.recognizedText = ""

                // 启动窗口期自动停止计时器（到期自动退出并执行指令）
                self.autoStopTask?.cancel()
                self.autoStopTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutSeconds)) * 1_000_000_000)
                    guard !Task.isCancelled, let self = self, self.isRecording else { return }
                    self.stopRecording(onFinished: onFinished)
                }

                self.recognitionTask = startSpeechRecognitionTask(
                    recognizer: speechRecognizer,
                    request: request
                ) { [weak self] transcription, isFinal, hasError in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        if let text = transcription, !text.isEmpty {
                            self.recognizedText = text
                            onUpdate(text)
                        }

                        if isFinal || hasError {
                            self.stopRecording(onFinished: onFinished)
                        }
                    }
                }
            } catch {
                self.errorMessage = "启动录音失败: \(error.localizedDescription)"
                self.cancelRecording()
            }
        }
    }

    public func stopRecording(onFinished: @escaping @MainActor @Sendable (String) -> Void) {
        guard !hasDeliveredFinished else { return }
        hasDeliveredFinished = true
        let finalText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRecording()
        if !finalText.isEmpty {
            onFinished(finalText)
        }
    }

    public func cancelRecording() {
        autoStopTask?.cancel()
        autoStopTask = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()
            self.audioEngine = nil
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}

