import SwiftUI
import AppKit

// MARK: - 更新与打赏面板（紧凑一屏版）
struct AboutUpdateView: View {
    let versionChecker: VersionChecker
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            headerBar

            Divider()
                .background(Color.white.opacity(0.08))

            // 内容区域（无滚动，确保一屏显示）
            VStack(spacing: 12) {
                // 版本信息卡片
                versionCard

                // 赞助区域（根据语言决定顺序）
                donationSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .frame(width: 340, height: 400)
        .accentColor(.brand)
    }

    // MARK: - 顶部标题栏

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("sonosBuddy")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            Text(L(.aboutTitle))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help(L(.close))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 版本信息卡片

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L(.currentVersion))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("v\(versionChecker.currentVersionDisplay)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // 更新状态
            updateStatusView
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var updateStatusView: some View {
        if versionChecker.isChecking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L(.checkingUpdate))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else if versionChecker.hasUpdate {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text(String(format: L(.newVersionFound), versionChecker.latestVersion))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Spacer()
                }

                if !versionChecker.releaseNotes.isEmpty {
                    Text(versionChecker.releaseNotes)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)
                }
            }
        } else if let err = versionChecker.checkError, !err.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 9))
                Text(String(format: L(.checkFailed), err))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if versionChecker.latestVersion.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 9))
                Text(L(.noRelease))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .font(.system(size: 9))
                Text(L(.alreadyLatest))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }

        // 操作按钮
        HStack(spacing: 6) {
            if versionChecker.hasUpdate && !versionChecker.releaseURL.isEmpty {
                Button {
                    if let url = URL(string: versionChecker.releaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(L(.goToDownload), systemImage: "arrow.up.forward.square")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.brand)
            }

            Button {
                Task { await versionChecker.checkForUpdate() }
            } label: {
                Label(L(.recheck), systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .disabled(versionChecker.isChecking)
        }
    }

    // MARK: - 赞助区域（根据语言切换顺序）

    private var donationSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(nsColor: .systemPink))
                Text(L(.supportAuthor))
                    .font(.system(size: 11, weight: .semibold))
            }

            // 根据语言决定顺序：英文时 Ko-fi 在上，中文时微信在上
            if Localizer.shared.isEnglish {
                kofiButton
                Divider().padding(.horizontal, 30)
                wechatQRBlock
            } else {
                wechatQRBlock
                Divider().padding(.horizontal, 30)
                kofiButton
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    // MARK: - 微信赞赏码

    private var wechatQRBlock: some View {
        VStack(spacing: 4) {
            wechatQRImage
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                .background(Color.white)

            Text(L(.wechatScan))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ko-fi 按钮（显眼版）

    private var kofiButton: some View {
        Button {
            if let url = URL(string: "https://ko-fi.com/loveuncleg") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(Localizer.shared.isEnglish ? L(.kofiSponsorEn) : L(.kofiSponsorZh))
                    .font(.system(size: 13, weight: .bold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .controlSize(.regular)
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.0, green: 0.67, blue: 0.87)) // Ko-fi 蓝色
        .shadow(color: Color(red: 0.0, green: 0.67, blue: 0.87).opacity(0.25), radius: 6, x: 0, y: 2)
    }

    // MARK: - 赞赏码图片

    private var wechatQRImage: some View {
        Group {
            if let nsImage = loadResourceImage(name: "wechat_qr", ext: "png") {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let nsImage = loadResourceImage(name: "wechat_qr", ext: "JPG") {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 从 Bundle.module 加载资源图片
    private func loadResourceImage(name: String, ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        return NSImage(contentsOf: url)
    }
}
