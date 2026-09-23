<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="sonosBuddy — 极简 macOS 菜单栏 Sonos 控制器">
</p>

<p align="center">
  基于 Sonos 官方 27mcp（Model Context Protocol）构建的极简 macOS 菜单栏音乐控制器。
  <br>
  <a href="./README.md">English Documentation</a>
</p>

<p align="center">
  <a href="#安装"><img src="https://img.shields.io/badge/下载-v1.0.0-FF6B00?style=flat-square&logo=github" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-26.2%2B-3A3A3C?style=flat-square&logo=apple" alt="macOS 26.2+">
  <img src="https://img.shields.io/badge/Sonos-27mcp-FF6B00?style=flat-square" alt="Sonos 27mcp">
  <img src="https://img.shields.io/badge/许可证-MIT-3A3A3C?style=flat-square" alt="MIT License">
</p>

---

## ✨ 核心功能

<table>
<tr>
<td width="50%">

**🎛️ 极简菜单栏面板**
260px 毛玻璃设计，与 macOS 原生风格融为一体。

**🔊 多房间分组管理**
下拉多选音箱，独立与综合音量智能联动。

**⭐ 收藏夹即点即播**
一键浏览 Sonos 收藏的电台、歌单与专辑。

</td>
<td width="50%">

**🎤 语音控制（实验性）**
原生语音识别，支持点播歌手、歌曲、专辑和歌单。

**🔐 官方授权**
浏览器一键 OAuth 2.1 授权，开箱即用。

**📊 MCP 请求计数**
底部状态栏实时显示今日 MCP 请求数。

</td>
</tr>
</table>

---

## 🚀 安装

### 方式一：直接下载（推荐）

1. 前往 **[Releases](https://github.com/holystool/sonosBuddy/releases)** 下载最新的 `sonosBuddy.zip`
2. 解压后将 `sonosBuddy.app` 拖入「应用程序」文件夹
3. 双击打开，顶部菜单栏即会出现 Sonos 图标

> **开发者签名**：本应用使用有效的 Apple 开发者 ID 签名，并启用了 Hardened Runtime。若 macOS 仍弹出安全提示，请前往「系统设置 → 隐私与安全性」，点击「仍要打开」即可。

### 方式二：源码编译

```bash
git clone https://github.com/holystool/sonosBuddy.git
cd sonosBuddy
xcodebuild -project sonosBuddy.xcodeproj -scheme sonosBuddy -configuration Release build
```

打包产物位于 `build/Release/sonosBuddy.app`，双击或 `open build/Release/sonosBuddy.app` 即可运行。

---

## 📸 界面截图

<p align="center">
  <img src="./assets/readme/screenshot-player.jpg" width="45%" alt="播放面板">&nbsp;&nbsp;&nbsp;&nbsp;
  <img src="./assets/readme/screenshot-settings.png" width="45%" alt="设置面板">
</p>

<p align="center">
  <em>左：极简播放面板，支持多房间音量独立控制 &nbsp;|&nbsp; 右：设置页面，OAuth 一键授权</em>
</p>

---

##  快速上手

| 步骤 | 操作 |
|:----:|:-----|
| **1** | 点击菜单栏图标 → 设置齿轮 →「通过 Sonos 账号登录授权」→ 浏览器完成 OAuth |
| **2** | 点击顶部音箱名称胶囊，勾选/取消音箱，实时生效 |
| **3** | 点击 ★ 星标图标，浏览 Sonos 收藏的歌单与电台 |
| **4** | 点击麦克风按钮，说出指令（如"播放周杰伦"、"音量 40"） |

---

## 🎤 语音点播

> ⚠️ 语音点播为**实验性功能**，识别准确率可能不稳定。

### 为什么提供语音点播？

Sonos 收藏夹仅包含手动保存的电台和歌单，无法搜索全曲库。而 **Apple Music 不受 Sonos 收藏夹限制**，可通过 Sonos MCP 实现全曲库搜索访问。因此提供语音点播功能，直接用语音搜索并播放 Apple Music 中的任意内容。

### 推荐语句格式

语音指令支持**中文**和**英文**，无需特殊唤醒词，直接说出指令即可：

| 场景 | 中文示例 | 英文示例 |
|:----:|:---------|:---------|
| 播放歌手 | "播放周杰伦的歌" | "play Taylor Swift" |
| 播放单曲 | "播放晴天" | "play Shape of You" |
| 播放专辑 | "播放专辑范特西" | "play album Rumours" |
| 播放歌单 | "播放歌单轻松流行" | "play playlist Chill Hits" |

> 💡 **提示**：MCP 操作有额度限制，基础功能（播放/暂停、音量、切歌）建议**直接用按键操作**，避免语音识别不准确导致空耗额度。

---

## ⚙️ 关于 MCP

sonosBuddy 通过 Sonos 官方 **27mcp**（Model Context Protocol）与音箱通信。

### 配额与重置

MCP 接口有**每日调用配额限制**：

- **重置时间**：每天北京时间 **08:00**（UTC 00:00）自动重置
- **配额估算**：播放面板底部和设置页均显示「今日 MCP 请求数」，可据此粗略估算日常消耗
- **正常使用**：正常使用（每天几十次播控操作）一般够用，无需担心超限

### 为节约配额做的优化

为减少不必要的 MCP 请求，sonosBuddy 做了以下优化：

- **静态数据本地持久化**：音乐服务列表等信息仅请求一次并缓存，杜绝重复调用
- **防抖与防级联刷新**：消除播控时的多倍级联刷新，单次播控调用降至最低
- **播放状态简化**：部分播控操作跳过了状态回读，以节约请求次数

> ⚠️ **注意**：上述优化可能导致播放按钮状态与实际播放状态出现短暂不同步（例如暂停后按钮仍显示播放中），但 **不影响实际使用**，再次操作即可同步。

### 响应延迟

MCP 基于网络请求，与本地直接控制相比会有 **些许延时**（通常 1-3 秒）。这是正常现象，尤其在首次连接或网络波动时可能更明显。

---

## 🛠 技术栈

- **Swift 5.0** + **SwiftUI** + **AppKit**
- **Xcode** 原生工程
- **Sonos 27mcp** 官方 MCP 协议（34 个工具）
- **OAuth 2.1 + PKCE** 安全授权
- **AVFoundation** 原生语音识别

---

## ☕ 支持作者

如果 sonosBuddy 对你有帮助，欢迎赞助支持：

<table>
<tr>
<td width="50%" align="center">

**Ko-fi 赞助**

[![Ko-fi](https://img.shields.io/badge/Ko--fi-Sponsor-00B9FE?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/loveuncleg)

</td>
<td width="50%" align="center">

**微信赞赏**

<img src="./Resources/wechat_qr.png" width="160" alt="微信扫码赞赏">

</td>
</tr>
</table>

每一杯咖啡都是对项目的支持！☕

---

## 📄 许可证

MIT
