import SwiftUI

// MARK: - 设置与鉴权面板
public struct SettingsView: View {
    @Bindable var controller: SonosController
    var onDismiss: () -> Void
    @State private var showToken: Bool = false
    @State private var isTestingLLM: Bool = false
    @State private var llmTestResult: String? = nil
    @State private var llmTestSuccess: Bool = false
    @State private var showLanguagePicker = false

    private func resolveModelName(endpoint: String, customModel: String) -> String {
        let trimmedCustom = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            return trimmedCustom
        }
        let lower = endpoint.lowercased()
        if lower.contains("deepseek") {
            return "deepseek-chat"
        } else if lower.contains("dashscope") || lower.contains("aliyun") {
            return "qwen-plus"
        } else if lower.contains("siliconflow") {
            return "deepseek-ai/DeepSeek-V3"
        } else if lower.contains("moonshot") {
            return "moonshot-v1-8k"
        } else if lower.contains("glm") || lower.contains("bigmodel") || lower.contains("zhipu") {
            return "glm-4-flash"
        } else if lower.contains("groq") {
            return "llama-3.1-8b-instant"
        } else {
            return "gpt-4o-mini"
        }
    }

    private func testLLMConnection() async {
        guard !controller.config.openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            llmTestSuccess = false
            llmTestResult = L(.apikeyFirst)
            return
        }

        isTestingLLM = true
        llmTestResult = nil

        var endpoint = controller.config.openAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty { endpoint = "https://api.openai.com/v1" }
        if endpoint.hasSuffix("/") { endpoint.removeLast() }
        let fullURLStr = endpoint.hasSuffix("/chat/completions") ? endpoint : "\(endpoint)/chat/completions"

        guard let url = URL(string: fullURLStr) else {
            isTestingLLM = false
            llmTestSuccess = false
            llmTestResult = L(.endpointInvalid)
            return
        }

        let modelName = resolveModelName(endpoint: endpoint, customModel: controller.config.openAIModel)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(controller.config.openAIKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "user", "content": "ping"]
            ],
            "max_tokens": 5
        ]

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            if let httpRes = response as? HTTPURLResponse {
                if httpRes.statusCode == 200 {
                    llmTestSuccess = true
                    llmTestResult = String(format: L(.llmSuccess), modelName, "\(elapsedMs)")
                } else {
                    llmTestSuccess = false
                    // 解析厂商的错误信息（如 Invalid model 或余额不足等）
                    var detail = ""
                    if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = errJson["error"] as? [String: Any],
                       let msg = errorObj["message"] as? String {
                        detail = msg
                    } else if let str = String(data: data, encoding: .utf8) {
                        detail = str
                    }
                    llmTestResult = String(format: L(.llmFailStatus), "\(httpRes.statusCode)", modelName, String(detail.prefix(90)))
                }
            }
        } catch {
            llmTestSuccess = false
            llmTestResult = String(format: L(.llmNetworkFail), error.localizedDescription)
        }

        isTestingLLM = false
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部标题
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Label(L(.settingsTitle), systemImage: "gearshape.fill")
                    .font(.system(size: 14, weight: .bold))
                Spacer()

                // 语言切换按钮
                Menu {
                    ForEach(Localizer.Language.allCases, id: \.self) { lang in
                        Button {
                            Localizer.shared.setLanguage(lang)
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                if Localizer.shared.language == lang {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(Color.primary.opacity(0.06))
                        )
                }
                .menuStyle(.borderlessButton)
                .help("Language / 语言")

                Button(L(.done)) {
                    onDismiss()
                }
                .controlSize(.small)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. 官方 OAuth 2.1 授权
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L(.oauthTitle))
                            .font(.system(size: 12, weight: .semibold))

                        Text(L(.oauthDesc))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await controller.startOAuthLogin()
                            }
                        } label: {
                            HStack {
                                if controller.isOAuthAuthenticating {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(L(.browserAuthenticating))
                                } else {
                                    Image(systemName: "globe")
                                    Text(controller.config.bearerToken.isEmpty ? L(.loginWithSonos) : L(.reAuthorize))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                        .tint(.brand)
                        .disabled(controller.isOAuthAuthenticating)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.brand.opacity(0.06)))

                    // 2. 演示模式开关（已隐藏，暂不开放）
                    // Toggle("开启演示模式 (Demo Mode)", isOn: $controller.config.isDemoMode)

                    // 2.2 语音控制模块（开关 + 倾听时长）
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Toggle(L(.enableVoice), isOn: $controller.config.isVoiceEnabled)
                                .font(.system(size: 12, weight: .semibold))
                                .disabled(!controller.hasAppleMusic)

                            Text(Localizer.shared.isEnglish ? L(.experimentalBadgeEn) : L(.experimentalBadge))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(Color.brand)
                                )
                        }

                        Text(Localizer.shared.isEnglish ? L(.voiceExperimentalNoteEn) : L(.voiceExperimentalNote))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.85, green: 0.35, blue: 0.0))

                        if controller.hasAppleMusic {
                            Text(L(.voiceAppleMusicOnly))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L(.noAppleMusic))
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }

                        if controller.config.isVoiceEnabled {
                            Divider()
                                .padding(.vertical, 2)

                            HStack {
                                Text(L(.speechTimeoutLabel))
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Picker("", selection: $controller.config.speechTimeoutSeconds) {
                                    Text("3s").tag(3)
                                    Text("5s").tag(5)
                                    Text("10s").tag(10)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                            }

                            Text(L(.speechTimeoutDesc))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                    Divider()

                    // 2.5 MCP 连接状态诊断
                    if controller.isConnected && !controller.config.isDemoMode {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L(.mcpDiagnosis))
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button {
                                    Task { await controller.refreshStatus() }
                                } label: {
                                    Label(L(.manualRefresh), systemImage: "arrow.clockwise")
                                        .font(.system(size: 10))
                                }
                                .controlSize(.mini)
                                .buttonStyle(.bordered)
                            }

                            // 工具数量
                            Text(String(format: L(.toolsFound), "\(controller.availableTools.count)"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            // 工具名列表（可滚动）
                            if !controller.availableTools.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(controller.availableTools.map { $0.name }.joined(separator: "  •  "))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(height: 22)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            }

                            // 最后一次操作反馈（高可读性胶囊设计）
                            if let feedback = controller.lastActionFeedback, !feedback.isEmpty {
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: feedback.contains("failed") || feedback.contains("error") || feedback.contains("quota") ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(feedback.contains("failed") || feedback.contains("error") || feedback.contains("quota") ? Color.brand : Color.accentColor)

                                    Text(feedback)
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.06))
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                            }
                            if let err = controller.errorMessage, !err.isEmpty {
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: "xmark.octagon.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: .systemRed))

                                    Text(err)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.08))
                                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

                        Divider()
                    }

                    // 3. 高级配置 / 手动 Token（已隐藏，暂不开放）
                    // DisclosureGroup("高级配置与手动 Token") { ... }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: 260)

            // 底部版本信息与今日统计
            HStack {
                Text(Localizer.shared.isEnglish ? L(.versionInfoEn) : L(.versionInfo))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "network")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.accentColor.opacity(0.8))

                    Text(String(format: L(.todayMCP), "\(controller.todayRequestCount)"))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .help(L(.todayMCPHint))
            }
        }
        .padding(14)
        .frame(width: 310, height: 380)
        .task {
            controller.checkAndResetQuotaCycleIfNeeded()
            if controller.availableMusicServices.isEmpty {
                await controller.fetchRegisteredMusicServices()
            }
        }
    }
}
