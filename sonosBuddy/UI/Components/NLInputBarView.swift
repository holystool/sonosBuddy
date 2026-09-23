import SwiftUI

// MARK: - 自然语言与语音智能控制栏
public struct NLInputBarView: View {
    @Bindable var controller: SonosController
    @StateObject private var speechManager = SpeechManager.shared
    @State private var inputText: String = ""
    @State private var isProcessing: Bool = false

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // 麦克风语音输入按钮
                Button {
                    speechManager.toggleRecording(
                        onUpdate: { transcribed in
                            inputText = transcribed
                        },
                        onFinished: { finalText in
                            inputText = finalText
                            executeCommand()
                        }
                    )
                } label: {
                    ZStack {
                        if speechManager.isRecording {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 22, height: 22)
                                .scaleEffect(1.2)
                        }

                        Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(speechManager.isRecording ? Color.red : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(speechManager.isRecording ? L(.tapToStopRecord) : L(.tapToStartVoice))

                // 文本输入框
                TextField(speechManager.isRecording ? L(.listeningPlaceholder) : (Localizer.shared.isEnglish ? L(.inputPlaceholderEn) : L(.inputPlaceholder)), text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        executeCommand()
                    }

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else if !inputText.isEmpty {
                    Button {
                        executeCommand()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(speechManager.isRecording ? Color.red.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            // 反馈提示或错误信息
            if let feedback = controller.lastActionFeedback {
                Text(feedback)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let err = controller.errorMessage {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let speechErr = speechManager.errorMessage {
                Text(speechErr)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.brand)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    private func executeCommand() {
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        inputText = ""
        isProcessing = true

        Task {
            await controller.executeNaturalLanguageCommand(cmd)
            isProcessing = false
        }
    }
}
