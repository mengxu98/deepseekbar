# DeepSeekBar

A lightweight macOS menu bar app for monitoring DeepSeek API balance — with multi-key management, usage estimates, and low-balance alerts.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="figures/main_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="figures/main.png">
    <img alt="DeepSeekBar menu bar popover" src="figures/main.png" width="420">
  </picture>
</p>

## Features

- **Menu bar balance** — live total balance (with currency symbol) next to the menu bar; turns orange with a `!` marker when the balance can no longer cover API calls (`is_available = false`).
- **Multi-key management** — add any number of DeepSeek API keys, rename them, switch the active key with one click, and see each key's balance at a glance. Duplicate keys are rejected.
- **Usage statistics** — today / total spend, daily average, estimated days remaining, and a balance sparkline, estimated from local balance snapshots (top-ups reset the baseline; DeepSeek's API exposes no usage endpoint).
- **Low-balance alerts** — configurable threshold with a local notification (fires once per alerting period, re-arms on recovery), plus an automatic alert when the official `is_available` flag goes false.
- **Launch at login** — standard macOS login item (SMAppService).
- **Auto updates** — daily check against GitHub releases; the popover shows a banner when a new version is available.
- **Localization** — English and 简体中文 (follows the system language).
- **Adaptive app icon** — Liquid Glass layers support light, dark, clear, and tinted appearances on macOS 26, with an ICNS fallback for earlier systems.

## Security

- API keys are stored in the **macOS Keychain** (service `com.deepseekbar.app`); `api_keys.json` in Application Support holds non-sensitive metadata only (id/name/creation date) with `0600` permissions.
- Older builds that stored plaintext keys are migrated to the Keychain automatically on first launch.
- The app talks only to `api.deepseek.com` (balance endpoint) and `api.github.com` (update check). Keys are never sent anywhere else.
- As a fallback for CLI users, the `DEEPSEEK_API_KEY` environment variable (and legacy `~/.deepseek/api_key` files) are picked up when no key is saved in the app.

## Install

Download the latest DMG from [Releases](https://github.com/mengxu98/deepseekbar/releases), drag **DeepSeekBar.app** to Applications, and launch it. Release builds are universal (Apple Silicon + Intel).

> Release binaries are ad-hoc signed. On first launch, macOS Gatekeeper may ask you to approve the app (right-click → Open, or approve in System Settings → Privacy & Security).

### Build from source

```bash
git clone https://github.com/mengxu98/deepseekbar.git
cd deepseekbar
swift build                # debug build
swift test                 # unit tests
./build.sh                 # release .app + DMG in .build/release/
UNIVERSAL=1 ./build.sh     # universal (arm64 + x86_64) build
```

Signing/notarization hooks (optional):

```bash
CODESIGN_IDENTITY="Developer ID Application: …" NOTARYTOOL_PROFILE="my-profile" ./build.sh
```

## Data locations

| Data | Location |
|---|---|
| Account metadata | `~/Library/Application Support/DeepSeekBar/api_keys.json` |
| API keys | macOS Keychain, service `com.deepseekbar.app` |
| Balance snapshots | `~/Library/Application Support/DeepSeekBar/balance_snapshots_*.json` |
| Settings (interval, alert threshold) | `UserDefaults` (`DeepSeekBar.*`) |

## FAQ

**Why are usage numbers estimates?** DeepSeek's API only exposes the current balance. DeepSeekBar snapshots the balance on every refresh and counts drops between snapshots; a top-up (or any significant balance rise) resets the baseline. Recent snapshots are kept raw, older ones are coalesced to hourly buckets.

**How do I delete my data?** Remove keys from the popover (🗑 per key — this also deletes the Keychain item), use "Reset usage" for snapshots, and delete `~/Library/Application Support/DeepSeekBar/` to remove everything else.

**The menu bar shows an error.** Hover the item for the message. `API key is invalid` means the key was rejected (401) — click Replace in the popover to update it.

## License

MIT
