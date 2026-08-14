# DeepSeekBar 审核报告

> 审核日期：2026-08 · 审核对象：本仓库（macOS 菜单栏 App，监控 DeepSeek API 余额 + 多账户/密钥管理 + DeepSeek-TUI 同步）
> 对齐依据：DeepSeek 官方文档（api-docs.deepseek.com）与官方开源项目 deepseek-harness；
> 参考实践：opencode、OpenAI Codex、earendil-works/pi、Netcatty、VS Code。

---

## 0. 结论摘要

整体工程是**小而完整**的：余额接口解析正确、多账户 + TUI 导入/导出做了扎实的工作、CI/发布脚本齐全。但存在 **2 个会直接误导用户的高优先级问题**（与官方模型名不一致、复制出的环境变量与官方工具不兼容），以及一批安全（明文密钥）、工程质量（零测试、单文件 1351 行、手写 TOML）、体验（无本地化、无低余额提醒）层面的改进点。

优先级总览：

| 级别 | 问题 | 影响 |
|---|---|---|
| P0 | 预设模型名 `deepseek-v4-pro[1m]` 非官方模型 | 用户以为在用 Pro，实际被官方静默映射为 Flash |
| P0 | "复制环境变量"与官方集成文档不一致 | 复制到 Claude Code/opencode 等不生效 |
| P0 | API Key 明文落盘（`api_keys.json`）+ 经 `security` CLI 命令行传参 | 密钥以明文/进程参数暴露 |
| P1 | 货币符号硬编码 `¥`（官方返回 CNY/USD） | USD 用户显示错误 |
| P1 | `is_available` 已解析但未用于状态提示 | 余额不足时无告警 |
| P1 | legacy `/beta` base URL、手写 TOML、Timer 模式、串行刷新 | 兼容性/健壮性风险 |
| P2 | 零测试、单文件、无本地化、ad-hoc 签名、arm64 单架构 | 工程与分发质量 |

---

## 1. 与 DeepSeek 官方信息对齐（正确性，最高优先级）

### 1.1 P0：`deepseek-v4-pro[1m]` 不是官方模型名

官方文档（Models & Pricing，api-docs.deepseek.com）当前仅两个模型：

- `deepseek-v4-flash`（DeepSeek-V4-Flash-0731）
- `deepseek-v4-pro`（DeepSeek-V4-Pro-0813）

两者**上下文长度都是 1M**，不存在 `[1m]` 后缀变体。更关键的是官方文档明确说明：

> "When you pass an unsupported model name to DeepSeek's Anthropic API, the API backend will automatically map it to the **deepseek-v4-flash** model."

也就是说，用户选择 `Models.swift` 中的 `claudeCodePro1M` 预设（`deepseek-v4-pro[1m]`）后，该模型名被写入 TUI 配置 / 环境变量，真正调用时会被静默降级为 **Flash**——用户以为在用 Pro（贵、更强），实际跑的是 Flash。这是最需要立刻修复的问题。

**修复建议**：预设只保留 `deepseek-v4-pro` 与 `deepseek-v4-flash`；把"1M 上下文"仅作为展示文案（两模型均 1M）。真正的差异化维度是 **thinking effort**（官方支持 `reasoning.effort: none/low/high/max`，默认 high），建议把 effort 作为可配置项：

```swift
enum DeepSeekProfilePreset: String, CaseIterable {
    case pro, flash
    var model: String { rawValue == "pro" ? "deepseek-v4-pro" : "deepseek-v4-flash" }
    var baseURL: String { "https://api.deepseek.com/anthropic" }
    var defaultReasoningEffort: String { "high" } // none/low/high/max
}
```

### 1.2 P0："复制环境变量"与官方工具不兼容

`copyActiveProfileEnv()` 导出的是：

```bash
export DEEPSEEK_API_KEY="..."
export DEEPSEEK_BASE_URL="..."
export DEEPSEEK_MODEL="..."
```

而官方 Anthropic 兼容端点文档给出的是：

```bash
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_API_KEY=sk-...
```

Claude Code 官方集成读取的是 `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`（或 `ANTHROPIC_API_KEY`）。因此当前复制结果粘贴给 Claude Code / 支持 Anthropic 端点的工具（opencode 的 anthropic provider 等）**不会生效**。

**修复建议**：按目标工具生成配置（对齐 codex 的 profile / opencode 的 provider 概念），提供"复制配置到…"菜单，每个目标用官方变量名：

- **Claude Code**：`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`（`export` 或写入 `~/.claude/settings.json`）
- **OpenAI 格式**（DeepSeek 官方）：`DEEPSEEK_API_KEY` + `DEEPSEEK_BASE_URL=https://api.deepseek.com`
- **opencode**：`opencode.json` 的 `provider` + `model`
- **Codex**：`config.toml` 的 `model_provider`（或 `OPENAI_BASE_URL`/OpenAI 兼容模式）
- **DeepSeek Harness**：DSH 的 provider 配置
- **curl 示例**：`curl https://api.deepseek.com/user/balance -H "Authorization: Bearer <key>"`

### 1.3 P1：legacy `/beta` base URL

`TUIProviderKind.deepseek.defaultBaseURL = "https://api.deepseek.com/beta"`。官方当前 OpenAI 格式 BASE URL 是 `https://api.deepseek.com`（`/beta` 是早期 function calling 端点；V4 在主端点即支持工具调用与 JSON Output）。建议核实并改为官方主端点，避免与 TUI 历史配置冲突。

### 1.4 P1：货币符号硬编码

官方返回 `currency: "CNY" | "USD"`（`Models.swift` 已正确解析），但 `Double.moneyText` 硬编码 `¥`。USD 用户会看到 ¥ 符号。**修复**：

```swift
extension Double {
    func moneyText(currency: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = currency // "CNY" / "USD"
        return fmt.string(from: NSNumber(value: self)) ?? "\(currency) \(self)"
    }
}
```

同时菜单栏 `String(format: "¥%.0f", total)` 对小数余额会显示 `¥0`，建议 \(total >= 1 ? 取整 : 保留两位\) 的自适应格式。

### 1.5 P1：`is_available` 未用于状态提示

官方余额响应的 `is_available` 表示"余额是否足够调用 API"。App 已解析（`BalanceState.isAvailable`）但 UI 只判断 `hasBalance`（`totalBalance != nil`）。建议：`is_available == false` 时菜单栏变黄/红、popover 顶部显示"余额不足"横幅——这是本 App 最有价值的告警场景（对照 pi 的实时状态栏）。

### 1.6 已确认正确的部分（保持）

- 余额端点 `GET https://api.deepseek.com/user/balance` + `Authorization: Bearer <key>` ✓（与官方一致）
- 响应解析 `is_available` / `balance_infos[].{currency,total_balance,granted_balance,topped_up_balance}` ✓
- Anthropic 兼容端点 `https://api.deepseek.com/anthropic` ✓
- 支持 `DEEPSEEK_API_KEY` 环境变量（官方 OpenAI 格式变量名）✓

---

## 2. 安全问题

### 2.1 P0：API Key 明文落盘

`APIKeyStore.saveState` 把**全部账户的原始 key** 以 JSON 明文写入 `~/Library/Application Support/DeepSeekBar/api_keys.json`（仅 0600 权限）。0600 只防其他用户，不防本机恶意进程/备份泄漏。macOS 标准做法是 Keychain（本项目为 TUI 同步已经用了 `security` CLI，自己的密钥却没用）。**建议**：账户密钥迁移到 Keychain（`SecItemAdd`，service 用 `com.deepseekbar.app`），本地 JSON 只存非敏感元数据（id/name/baseURL/model/tuiProvider），key 用 Keychain 引用。

### 2.2 P0：`security` CLI 以命令行参数传递密钥

`KeychainBridge.set` 执行 `security add-generic-password -w <API_KEY>`——**密钥作为进程参数可见**（任何用户可 `ps` 看到），且每次调用同步 `waitUntilExit`。**修复**：改用 Security 框架：

```swift
import Security
func set(_ key: String, account: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: Data(key.utf8),
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
        SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(key.utf8)] as CFDictionary)
    }
}
```

（`kSecAttrAccessibleAfterFirstUnlock` 对登录后运行的菜单栏 App 是合理选择；如需与 TUI 兼容，保持 service `"deepseek"` + account `provider`。）

### 2.3 P1：密钥多副本扩散

一个 key 同时存在于：`api_keys.json`、TUI Keychain、`~/.deepseek/config.toml`、可能还有 `secrets.json`。应明确"单一事实来源"：App 密钥入 App 自己的 Keychain；TUI 同步走 TUI 的 Keychain（`SecItem` 读写），config.toml 仅作 TUI 的兼容回退，并在 UI 中说明。

### 2.4 P1：手写 TOML 写入无转义

`DeepSeekTUIConfig` 重建 TOML 时 `api_key = "\(key)"` 不做转义（读侧 `unquote` 也只处理 `\"`/\`\n`/\`\\`）。DeepSeek key 目前是 `sk-`+字母数字，风险低，但这是脆弱的边界。且重建逻辑会**丢失 provider 段内注释、内联注释、其他 TOML 特性**。**建议**：改用成熟 TOML 库（如 `swift-toml`），或至少为写入侧加转义 + 单测覆盖 round-trip。

### 2.5 P2：无沙盒 / ad-hoc 签名

无 entitlements、无 App Sandbox；`codesign -s -` 临时签名。见 §5 发布部分。

---

## 3. 架构与工程质量

1. **单文件膨胀**：`DeepSeekBarApp.swift` 1351 行 = AppDelegate + ViewModel + 全部 View + 组件。建议按职责拆分：`App/AppDelegate.swift`、`App/AppViewModel.swift`、`Views/*.swift`、`Components/*.swift`、`Support/*.swift`（对齐 pi/opencode 的模块化组织）。
2. **零测试**：Package.swift 无 test target，CI 无 `swift test`。以下纯逻辑非常适合 XCTest：余额解码、TOML 解析/重建 round-trip、版本比较、UsageTracker 估算、currency 格式化、预设模型名校验（可加"模型名必须在官方清单内"的编译期/运行期校验，防 1.1 类问题回归）。参考 pi 的 conformance tests / dsh 的测试目录。
3. **手写 TOML 解析/重建**（见 2.4）。
4. **Timer 模式问题**：`Timer.scheduledTimer` 默认加入 default runloop mode，菜单跟踪/面板打开时可能不触发。改用 `RunLoop.main.add(timer, forMode: .common)` 或基于 `Task` 的 `sleep` 循环。
5. **串行刷新**：`refreshSavedAccounts` 逐个 await，多账户时串行。用 `withTaskGroup` 并发拉取（注意并发上限与 429 退避）。
6. **无代码规范/静态检查**：无 SwiftLint/SwiftFormat；CI 仅 macos-14 构建。建议加 `swiftformat --lint` / `swiftlint` job。
7. **单架构**：`--arch arm64` 只出 Apple Silicon 包，x86_64 Mac 无法使用。至少支持 `--arch arm64 --arch x86_64`（universal）。
8. **README 过简**：仅 2 段 + License。建议补充：功能清单、安装方式（DMG / brew cask / 源码）、密钥存储与安全说明、TUI 同步原理与数据位置（`~/.deepseek/config.toml`、Keychain service `deepseek`）、常见问题、隐私说明（仅请求官方 balance 端点、不上传密钥）。
9. **无本地化**：全部硬编码英文；DeepSeek 是中文公司产品，加 String Catalog（`Localizable.xcstrings`）提供 `zh-Hans`（Netcatty 三语、opencode 20+ 语种是良好示范）。
10. **无障碍**：图标按钮（`toolbarButton`）的 `.help(name)` 直接把 SF Symbol 名当 tooltip（如 "arrow.clockwise"）；应加 `.accessibilityLabel("刷新")` 与人类可读 `.help`。
11. **小项**：`DeepSeekAPI` 用 `.shared` session 无 User-Agent；建议自定义 session（UA、超时、重试）；更新检查无 `If-None-Match`/ETag（小优化）；`@unchecked Sendable` 建议注释原因。

---

## 4. 功能与体验建议（对照参考项目）

### 4.1 参照 codex / opencode：一键生成目标工具配置（替代当前"复制环境变量"）

codex 有 `model_provider` profile、opencode 有 `opencode.json` provider/model。DeepSeekBar 的差异化价值就是"密钥管理器 + 配置生成器"：为每个账户提供"Copy config for…"（Claude Code / opencode / codex / DSH / curl），使用 §1.2 的官方变量名。这比泛化的 `DEEPSEEK_*` 三连更贴近用户真实工作流。

### 4.2 参照 pi：把已解析的数据做成有用的状态面板

- 官方返回 **granted / topped-up 拆分**（且官方计费说明"优先扣 granted"），UI 目前只显示 total——建议详情区展示两项拆分。
- UsageTracker 已有余额快照数据，可画一个轻量 sparkline（今日/近 7 日余额走势），对应 pi 的状态栏统计。
- 菜单栏显示 `is_available` 状态（§1.5）。

### 4.3 参照 vscode / netcatty：系统集成与配置体验

- **低余额提醒**：余额低于阈值或 `is_available=false` 时发本地通知（`UNUserNotificationCenter`）。
- **开机自启**：`SMAppService.mainApp` 提供 "Launch at login"（菜单栏工具标配）。
- **URL scheme**：`deepseekbar://add-key?key=...&name=...`，便于从网页/脚本一键添加。
- **配置导入导出**：加密（Keychain 派生密钥）导入/导出账户，便于换机。
- **主题**：跟随系统深/浅色已有，可补 accent 色选择（DeepSeek 蓝）。
- **"Open DeepSeek Console"**：跳转 platform.deepseek.com 余额/账单页的入口。

### 4.4 参照 deepseek-harness：工程与生态对齐

- 阅读并遵循官方 harness 的文档规范（AGENTS.md / docs / CONTRIBUTING），为 DeepSeekBar 补 AGENTS.md 与架构文档。
- 若目标用户使用 DSH，可提供 DSH provider 配置生成（DSH 生态是"一切皆插件"，未来可做成一个 dsh-plugin，如 `dsh-plugin-deepseekbar` 读取余额告警）。
- 对齐官方命名与端点（§1），避免自身成为"非官方信息源"。

---

## 5. 发布与分发

1. **Developer ID + 公证**：`codesign -s - `（ad-hoc）在他人机器上会触发 Gatekeeper 拦截。用 Developer ID Application 证书 + `notarytool` 公证 + `stapler` staple（参考 codex/netcatty 的正式分发）。
2. **Universal binary**（§3.7）。
3. **Homebrew Cask**：`brew install --cask deepseekbar`（opencode 官方 brew formula 是良好范例）；`brew update` 自动更新与 App 内更新检查互补。
4. **更新检查优化**：GitHub API 未认证限额 60 次/时，当前 1 次/天无碍；建议缓存 ETag，并在 CI 发布时同步 `latest` release。
5. **版本单一来源**：`APP_VERSION` 在 build.sh 内，tag/plist 已做一致性校验（脚本做得不错），可考虑改用 xcconfig 或 git describe 减少手工维护。

---

## 6. 建议路线图

**P0（本周）**
1. 修正预设模型名（移除 `[1m]`），加"模型名必须在官方清单"的校验
2. 密钥迁移到 Keychain（SecItem），`api_keys.json` 不再存明文
3. KeychainBridge 改 Security 框架（去掉 CLI 传参）
4. 复制配置改为按目标工具生成官方变量名

**P1（两周内）**
5. currency 按官方响应格式化；菜单栏金额自适应精度
6. `is_available` 告警（横幅 + 菜单栏变色）+ 低余额通知
7. 移除 `/beta`；TOML 用库或加转义与 round-trip 测试
8. Timer 改 common mode；多账户并发刷新 + 429 退避
9. 拆文件 + 补 XCTest（解码/TOML/版本/估算）+ CI 跑 `swift test` + SwiftLint

**P2（后续）**
10. Developer ID + 公证 + Universal + brew cask
11. 本地化（zh-Hans）、无障碍标签
12. "Launch at login"、URL scheme、配置导入导出、usage sparkline、granted/topped-up 展示
13. README 重写 + AGENTS.md + DSH 集成/插件

---

## 附 2：实施记录（2026-08-14）

以下 P0/P1 项已实施并通过 `swift build` / `swift test`（19 个测试全绿）验证：

**P0（已完成）**
- ✅ §1.1 预设模型名：移除 `deepseek-v4-pro[1m]`，仅保留官方 `deepseek-v4-pro` / `deepseek-v4-flash`；新增 `DeepSeekOfficialModel` 目录 + `isOfficial` 校验（含回归测试，防止虚构模型名重现）
- ✅ §1.2 复制配置：按目标工具生成官方变量名——Claude Code（`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`）、DeepSeek OpenAI 格式（`DEEPSEEK_API_KEY` + `https://api.deepseek.com`）、余额 curl；接入右键菜单 "Copy Config"
- ✅ §2.1/2.2 密钥安全：新增 `AppKeychainStore`（SecItem），账户密钥迁入 Keychain（service `com.deepseekbar.app`），`api_keys.json` 仅存元数据；含旧明文格式自动迁移；删除账户/清空密钥时同步清理 Keychain
- ✅ §2.2 `KeychainBridge` 重写为 Security 框架（不再 `security` CLI 传参，密钥不再出现在进程参数中）
- ✅ §1.4 货币：按官方 `currency`（CNY/USD）格式化；菜单栏新增 `compactMoneyText` 自适应精度

**P1（已完成）**
- ✅ §1.5 `is_available` 告警：菜单栏变橙 + "!"、popover 橙色横幅、header 徽章变色；低余额本地通知（`BalanceNotifier`，一次不足期只通知一次）
- ✅ §3.4 Timer 改 `RunLoop.main.add(..., forMode: .common)`（菜单跟踪期间也能触发）
- ✅ §3.5 多账户刷新并发化（`withTaskGroup`）
- ✅ §1.3 移除 legacy `/beta` 默认端点
- ✅ §2.4 TOML 写入转义（`escape`/round-trip 测试）
- ✅ §3.9 测试：新增 `DeepSeekBarTests`（19 用例：官方余额 JSON 解码、API 错误码（mock URLSession）、版本比较、TOML 解析/重建/转义 round-trip、UsageTracker 估算、货币格式化、官方模型清单）；CI 新增 `.github/workflows/test.yml` 跑 `swift test`
- ✅ 修复实施中发现的真实 bug：`DeepSeekTUIConfig` 中 `dropFirst(12)` 应为 `dropFirst(11)`（`"[providers."` 仅 11 字符），此前 provider 段名会被截断为 `eepseek`

**备注**
- target 拆分曾尝试（Core library），因 Swift 内跨模块可见性需大量 `public` 修饰而回退；SwiftPM 5.5+ 支持 testTarget 依赖 executable target，保持单 target 即可测试，代价更低
- 未实施（P2）：Developer ID 公证、Universal 架构、本地化、开机自启、URL scheme、README 重写

---

## 附 3：二次迭代（2026-08-14，按用户反馈）

- ✅ **简化**：移除整套 DeepSeek-TUI 同步（Import 按钮、TUI Provider 选择、账户行徽章/同步按钮、`importFromTUI`/`exportToTUI`/`removeFromTUI`/`isSyncedWithTUI`、`tuiSyncStatus`）；删除 `KeychainBridge.swift`/`SecretsFileStore.swift`/`DeepSeekTUIConfig.swift`（及 TOML 测试）；`TUIProviderKind`/`tuiProvider` 字段移除（旧数据 `tui_provider` 键在解码时被安全忽略）。应用聚焦"DeepSeek 余额 + 消耗监控"。修复"删除账户后 Import 又读回"的问题（Import 功能已移除）
- ✅ **统计增强**：`UsageTracker` 新增 `UsageStats`（今日/昨日/近 7 天/近 30 天/日均/预计可用天数/余额走势快照）；UI 统计卡片显示上述指标 + 余额走势 sparkline + granted/topped-up 拆分展示（官方响应字段）
- ✅ 测试更新至 16 个全绿（`swift test`），release 打包 + 替换安装完成
- ✅ 背景改为白底（浅色模式纯白，深色模式系统深色），降低磨砂透明度

---

## 附 4：Token 用量 / 缓存统计（本地代理，2026-08-14）

**事实**：官方 API 无 token 用量查询端点（`GET /user/balance` 仅余额）；token/cache 数据只存在于调用方收到的每次响应 `usage` 字段（Claude Code 本机 JSONL 实测含 `input_tokens`/`output_tokens`/`cache_read_input_tokens`/`cache_creation_input_tokens`）。

**实现**（方案 A，用户选定）：
- ✅ `TokenUsage.swift`：`TokenUsage` 模型 + `DeepSeekPricing`（官方 flash/pro 每百万定价，成本估算）+ `TokenUsageStore`（JSONL 落盘 + 今日/本月聚合）+ `UsageExtractor`（OpenAI/Anthropic 非流式 JSON 与 SSE 流式 usage 提取，Anthropic 跨事件合并：message_start 的 input/cache + message_delta 的 output）
- ✅ `UsageProxy.swift`：NWListener 本地 HTTP 代理，**仅绑定 127.0.0.1 随机端口**；**纯透明转发（按官方路径原样）**——客户端必须按官方端点配置：OpenAI 系 base URL 为 `http://127.0.0.1:<端口>`，Anthropic SDK（Claude Code）为 `http://127.0.0.1:<端口>/anthropic`（与官方 `https://api.deepseek.com/anthropic` 同构，代理不做路径猜测）；chunked 流式转发同时逐行解析 SSE usage；非流式 JSON 响应整包提取
- ✅ UI：Token Usage 卡片（今日/本月 tokens、缓存命中率、估算费用、两种代理地址）+ 菜单栏右键 Copy Proxy Base URL (OpenAI) / (Anthropic)；代理随 app 启动/退出
- ✅ 冒烟测试：真实调用经代理转发（响应与直连一致）、Anthropic/OpenAI/balance 三个官方路径均正确命中端点、监听仅 127.0.0.1
- ✅ 测试 24 个全绿（新增 extractor/store 单测，含 OpenAI/Anthropic 流式合并用例）
- 使用方式：Claude Code 设 `ANTHROPIC_BASE_URL=http://127.0.0.1:<端口>/anthropic`，OpenAI 系工具设 `base_url=http://127.0.0.1:<端口>`，即可实时统计 token 与缓存命中率

---

## 附 5：界面简化（2026-08-14，按用户反馈）

- ✅ **删除右键菜单**：移除整个菜单栏右键菜单（Refresh / Check for Updates / Copy Config / Copy Proxy Base URL / Quit）；菜单栏点击统一切换 popover；退出走 popover 底部 power 按钮
- ✅ **添加 API 简化**：新增账户面板只保留 **Name + API Key** 两个输入；删除 Model 预设选择（DeepSeekProfilePreset 整体删除）与 Base URL 输入
- ✅ **账户模型简化**：`APIKeyAccount` 删除 `baseURL`/`model` 字段（旧 JSON 中这两个键解码时忽略）；`APIKeyStore.updateAccount` 仅剩改名；删除 `applyPreset`/`updateActiveAccount`/`copyAnthropicEnv`/`copyOpenAIEnv`/`copyBalanceCurl` 等全部配置导出方法
- ✅ 测试更新（testPresetsUseOfficialModels → testOfficialModelCatalog），24 个全绿；面板高度 400→240；release 打包替换安装完成

---

## 附 6：移除 Token Usage 代理统计（2026-08-14，按用户反馈）

- ✅ **完整删除 Token Usage**：移除 Token Usage 卡片（含 tokenRow/formatTokens/rateText/costText）；删除本地统计代理 UsageProxy.swift 与 TokenUsage.swift（模型/存储/提取器）；ViewModel 删除 tokenStats/proxyBaseURL/代理启动停止/复制地址方法；AppDelegate 退出钩子清理；删除 8 个 token 相关测试（24 → 16 全绿）；清理遗留 token_usage.jsonl
- ✅ **Daily avg 恢复金额显示**：移除 tokens/¥ 手动切换（数据源已删），回到金额日均 + 预计可用天数
- ✅ **sparkline 直线修复**：余额快照几乎无波动（max-min < 0.01）时不再画直线，改显示 "Balance stable" 占位文案

---

## 附 7：菜单栏品牌图标（2026-08-14，按用户反馈）

- ✅ **状态栏显示官方 logo + 余额**：从 www.deepseek.com favicon 手动解码 ICO 内嵌 BMP（跳过 AND mask）提取鲸鱼；后按用户反馈改用官方 deepseek-harness-desktop 仓库的菜单栏图标（apps/desktop/resources/trayTemplate@2x.png，32x32 专为 template 渲染设计）
- ✅ **template 渲染**：NSImage.isTemplate = true + button.image（非文本 attachment），系统按菜单栏明暗自适应着色，深浅色模式均清晰；保持源图宽高比不被压扁
- ✅ **build.sh 修复**：SwiftPM 资源 bundle（DeepSeekBar_DeepSeekBar.bundle）随 app 一起打包进 Contents/Resources
- ✅ 版本 v0.0.2 → v0.0.3（本轮全部改动随 v0.0.3 发布）

---

## 附：官方信息源

- Get User Balance：https://api-docs.deepseek.com/api/get-user-balance/
- Models & Pricing（含 V4 模型清单、1M 上下文、peak/off-peak 计费）：https://api-docs.deepseek.com/quick_start/pricing/
- Using the Anthropic API（含不支持模型名静默映射为 flash 的说明）：https://api-docs.deepseek.com/guides/anthropic_api/
- Thinking Mode（reasoning.effort 控制）：https://api-docs.deepseek.com/guides/thinking_mode/
- DeepSeek Harness：https://github.com/deepseek-ai/deepseek-harness
