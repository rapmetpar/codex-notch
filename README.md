<div align="center">

# CodexNotch

<img src="Resources/AppIcon.svg" width="240" alt="CodexNotch app icon">

### Your Codex quota—always in sight.

**Weekly quota, five-hour details, exact reset times, and task status stay beside your MacBook notch.**<br>
Your browser, IDE, or any other app can be frontmost—your quota remains visible.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://github.com/fengdwx/codex-notch/releases/latest)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](Package.swift)
[![Latest release](https://img.shields.io/github/v/release/fengdwx/codex-notch?label=download&color=2ea44f)](https://github.com/fengdwx/codex-notch/releases/latest)
[![MIT License](https://img.shields.io/badge/License-MIT-4c8bf5)](LICENSE)
[![LINUX DO](https://img.shields.io/badge/LINUX-DO-FFB003.svg)](https://linux.do)

[**Download the latest release**](https://github.com/fengdwx/codex-notch/releases/latest) · [**Watch the 26-second demo**](docs/assets/codex-notch-demo-en.mp4) · [简体中文](README.zh-CN.md)

</div>

[![CodexNotch English product demo](docs/assets/codex-notch-demo-en.gif)](docs/assets/codex-notch-demo-en.mp4)

<p align="center"><sub>Real app capture with English product callouts: weekly quota, exact reset time, every reset-credit expiry, cross-app visibility, and live task status.</sub></p>

## New in 0.2.2

- Optional launch at login and an Off choice for the left display area to reduce menu-bar overlap.
- Settings grouped into General, Appearance, and Floating Bar, with clearer descriptions.
- Preview floating-bar styles and task states without an external display.
- The animation switch controls quota and status effects independently of system Reduce Motion; disabling animations reduces resource use while quota and task updates continue.
- Fixed redundant Settings activation that could interrupt dropdown menus.

## New in 0.2.1

- Bring an already-open Settings window back to the front.
- Download, verify, install, and relaunch updates inside the app. Install 0.2.1 manually once when upgrading from an earlier version.

## New in 0.2.0

- Gentle hover feedback, a spring opening with a small landing rebound, and a smoother collapse.
- Cleaner typography and spacing, with text staying at its natural size during transitions.
- Four floating-bar center styles: a custom signature, orbit, elapsed time, and light flow. Signature lighting moves continuously while the compact bar is visible and motion is enabled.
- Better-balanced floating status icons and current Codex task names, filtering attachment headers and decoding escaped characters in conversation labels.

## Why CodexNotch exists

Codex quota is easy to lose behind other windows. CodexNotch keeps the answers that matter beside your MacBook notch, wherever you work:

- **How much weekly quota is left, and what is the five-hour detail?**
- **Exactly when does it reset?**
- **Is the task still running?**

They remain beside the physical notch while you code, browse, write, or work in another app.

> **One glance at the notch: quota, reset time, and task status—without changing apps.**

## At a glance

| What you want to know | What CodexNotch shows |
| --- | --- |
| **How much quota remains?** | On a physical notch, a returned five-hour ring or wave ball sits on the left and weekly stays on the right; the expanded card lists five-hour first, then weekly. |
| **When will quota reset?** | The exact reset timestamp plus a second-by-second countdown in the expanded card. |
| **When does each reset credit expire?** | Click **N reset credits available** to reveal every precise expiry time and countdown. |
| **What happens when I switch apps?** | Nothing disappears. Quota and status stay visible while another app is frontmost. |
| **Is the task running?** | A blue activity echo while Codex works, then a clear green check when it finishes. |

## The experience

### Quota at a glance, in every app

The left side shows five-hour quota when available, or the selected status icon otherwise. Weekly quota stays on the right even when no task is active. Choose Off in Settings to hide the left side; the expanded card still shows all available quota windows, with five-hour detail above weekly. Switch to your browser, IDE, or another app and the quota remains visible.

### Exact reset timing, not just a percentage

Hover over the notch to reveal:

- The returned five-hour quota first, followed by weekly quota, with horizontal progress bars
- The exact reset timestamp and live countdown
- The precise expiry time of every available reset credit
- Active tasks and recent conversations

Quota windows are identified from the returned `limit_window_seconds`. On both notch and floating-bar layouts, weekly quota stays on the right; the left side shows five-hour quota when available unless Off is selected. The expanded card lists five-hour detail first.

### Your quota follows you across apps

CodexNotch is a standalone native macOS app. It does not depend on Atoll, CodexIsland, CC Switch, or another host. Your browser, IDE, or any other app can stay in front while quota, reset time, and task status remain visible.

### Task status in the same place

While Codex works, a blue activity echo and restrained halos behind the real visible quota indicators show that the task is still running; completion switches to a clear green check. Click a task in the expanded card to open `codex://threads/<thread-id>` instead of searching for the conversation again.

## Install

From [**GitHub Releases**](https://github.com/fengdwx/codex-notch/releases/latest), prefer `CodexNotch-...dmg` when the release provides one. Otherwise, use the ZIP archive:

1. For a DMG, open the disk image; for a ZIP, unzip the archive.
2. In the DMG window, drag `CodexNotch.app` onto the `Applications` shortcut. (The ZIP requires dragging the app into Applications manually.)
3. Sign in to ChatGPT, use Codex once, then launch CodexNotch.

Swift, Swift Package Manager, and Xcode are not required.

> A ZIP is also provided as an alternative archive. The current public build uses an ad-hoc signature, so a DMG does not remove the first-launch macOS warning. Choose **Open Anyway** in **System Settings → Privacy & Security**, or Control-click the app and choose **Open**.

CodexNotch reads the default `~/.codex` directory. If Codex uses another directory, set `CODEX_HOME` before launching the app.

## Usage

Hover over the notch or floating bar to open the expanded card. Recent conversations are grouped by project. Drag a project heading to change its priority, or use its up/down buttons. The order applies immediately and is saved locally; the configured Running/New/Viewed category order applies within each project. The 0–20 conversation limit counts chats, not project headings.

## Make it yours

Open **Settings** at the lower-right of the expanded card, from the notch context menu, or from the app menu.

In **Appearance**, enable **Custom color** to choose the quota and glow color, or restore the standard warning palette. Select **Custom image** under **Left side** to import a static PNG/JPEG icon (up to 8 MB). A small local copy survives moving the source file. Five-hour quota still takes priority over this icon.

- Switch between the clockwise quota ring and wave ball
- Choose a floating-bar center style and set a signature of up to 12 characters
- Choose Chinese, English, or Russian for the app interface (English by default)
- Show 0–20 recent conversations in the expanded card
- Check for stable updates and download, install, and relaunch inside the app (from 0.2.1)
- Apply changes immediately and save them locally
- Start automatically at login when enabled in General
- Hide the left display area while keeping quota details in the expanded card
- Control animations with the app's **Animations** switch

Displays without a notch, including mirrored displays, use a floating bar centered at the top of the screen.

### Animated companions

In **Companions**, choose **Import companion library…**, select a local library folder, then choose any imported companion. Companions are **Off** by default; choosing Off restores the original left-side icon setting and removes the companion stage. The library and selection are saved locally, so the original import folder can be moved or deleted.

On a physical notch, the selected companion is animated in the compact left wing without hovering. Separate slots keep the five-hour quota and running/completed cue visible; weekly quota stays in place. The left wing grows to make room. Hovering moves the companion to its larger stage below the camera. If the measured safe area is too small, it remains available in the expanded stage. For compact floating bars, select **Companion** as the center style in **Floating Bar**. The other center styles remain available; physical compact notches keep their camera area clear.

The companion works while tasks run, jumps once for a newly observed completion, occasionally strolls at rest, and greets on hover with a cooldown. Opening old history does not replay completion celebrations. Companion motion requires **Animations** to be on and system **Reduce Motion** to be off; either setting stops its motion while keeping a static pose. Existing quota and status animations retain their independent app-switch behavior.

Compatible libraries contain a `manifest.json` and local PNG/WebP sprite atlases with standard clip metadata: legacy **v1 (8×9)** or **v2 (8×11)**, both using **192×208-pixel cells**. Imports are validated before replacing the current library. Personal companion artwork and account-specific collections are not included in this repository.

<details>
<summary><strong>Visual and interaction details</strong></summary>

- Both compact indicators use matching 24pt alignment containers, keeping icons clear of the camera cutout.
- The quota ring starts at 12 o'clock and progresses clockwise. It is green at 20% or above, red below 20%, and gray when data is unavailable.
- The quota gradient or wave moves only while a task is running. Signature lighting also continues while idle or completed; disabling animations in the app keeps both still.
- The card expands downward from the compact island. Its transparent canvas is reclaimed after collapse so it does not intercept clicks outside the notch.
- The quota number stays inside the indicator and is never repeated beside it.

</details>

## Data and privacy

- The authentication token is read only from `CODEX_HOME/auth.json` and remains in process memory. CodexNotch never writes it to a cache or log.
- Quota and reset-credit details come from ChatGPT's read-only usage and reset-credit endpoints.
- Task state is parsed only from rollout JSONL files in `CODEX_HOME/sessions`.
- Conversation labels use the latest short `thread_name` in `CODEX_HOME/session_index.jsonl`, falling back to `threads.title` in read-only `CODEX_HOME/state_5.sqlite`. Rollout message bodies, `first_user_message`, and `preview` are ignored when resolving titles.
- CodexNotch never records Authorization headers, complete usage responses, user-message bodies, or conversation-title caches.
- Manual update checks read a public GitHub appcast and download signed release archives; they send no Codex credentials, quota data, task data, or user content.

The usage endpoint is an internal ChatGPT endpoint and its fields may change. If it fails, CodexNotch keeps the last successful quota while task monitoring continues.

<details>
<summary><strong>Build from source</strong></summary>

Contributors need Xcode 16 or newer and a macOS version supported by that Xcode release. The built app supports macOS 14 or later. CI uses Xcode 16.2 on macOS 14:

```sh
swift test
./scripts/build_app.sh
open dist/CodexNotch.app
```

Create distributable ZIP and DMG archives:

```sh
./scripts/release.sh
```

The release script runs tests, builds the release app, validates its code signature, produces ZIP and DMG archives plus SHA-256 files, mounts the DMG to verify its bundled app, and signs the ZIP to generate an update feed using the publisher’s Keychain. See [the publisher update workflow](docs/updating.md). The DMG improves installation flow; it does not replace Developer ID signing or notarization. To skip signing entirely:

```sh
SIGN_IDENTITY=none ./scripts/build_app.sh
```

</details>

## Current boundaries

CodexNotch is currently in its 0.x release series. It does not terminate Codex tasks, estimate cost, sync to the cloud, send remote notifications, download or install updates without user action, or support Mac App Store distribution. ChatGPT Classic is not a monitored target.

## License

CodexNotch is released under the [MIT License](LICENSE). If it helps you stay focused—and a little less anxious about quota—consider giving the project a Star.
