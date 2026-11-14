# VIPER — Virtual Intelligence Personal Executive Response

A local-first personal AI assistant for Windows with an Android companion. VIPER talks with you by
voice or text, operates your PC through permissioned tools, remembers what you ask it to, watches
your system, runs automations and reaches you on your phone — using free AI models that run on
your own computer. No subscription, no cloud inference by default.

| Component | Where | What it is |
|---|---|---|
| VIPER desktop | `desktop/` | Electron app (Windows 10/11) hosting the VIPER core: Node.js services, SQLite, local API, UI |
| VIPER Mobile | `mobile/` | Native Android app (Kotlin + Jetpack Compose), a secure remote for the desktop |
| Docs | `docs/` | Install, configuration, architecture, communications, plugins, test report |

## Quick start (Windows)

1. Run `VIPER-Windows-Setup.exe` (per-user install, desktop + Start-menu shortcuts, uninstaller), or
   run `VIPER-Portable.exe` without installing.
2. The first-run wizard scans your hardware, helps you install **Microsoft Foundry Local**
   (`winget install Microsoft.FoundryLocal`) or **Ollama**, downloads a model sized for your PC,
   tests it, and optionally installs voice (whisper.cpp + a British Piper voice).
3. Say or type **“VIPER, are you online?”**. Hold **Ctrl+Space** to talk; **Ctrl+Shift+Space**
   opens the floating HUD from anywhere.
4. On your phone, install `VIPER-Mobile.apk`, open *Communications → Phone link* on the PC and scan
   the pairing code.

Full instructions: [docs/INSTALL.md](docs/INSTALL.md).

## What works

- **Local AI engines**: Foundry Local (REST API, model catalogue, download/load/unload, endpoint
  discovery via `foundry service status`), Ollama (native API incl. vision and embeddings) and any
  OpenAI-compatible local server. Per-task model roles, live model switching, tokens/s and
  first-token metrics, benchmark, automatic restart of a crashed engine, hardware-based
  recommendations with realistic speed estimates.
- **Assistant**: streaming chat with tool calling (native, or a text protocol for models without
  it), configurable personality, long-term memory (SQLite FTS5), context trimming + summaries,
  private chats, search, pin, rename, export, attachments (PDF/Word/Excel/images).
- **Real PC tools**: open/close apps (verified by process check), volume (Core Audio), windows,
  folders, file search, create/move/recycle files in allowed folders, screenshots, clipboard,
  approved scripts, websites, diagnostics incl. Windows event log. Every tool has a permission
  category; destructive actions always ask; actions that follow web/email/document content always
  ask (prompt-injection guard).
- **Voice**: wake word (“VIPER”, configurable), push-to-talk, continuous conversation, barge-in,
  VAD, device selection, sensitivity, noise suppression; whisper.cpp or Foundry Whisper for STT;
  Piper British voices for TTS with the core visualiser driven by the actual speech audio.
- **Modes**: Image Studio (Stable Diffusion via the AUTOMATIC1111-compatible API of Forge/A1111/
  SD.Next: txt2img, img2img, inpaint, variations, upscale, background removal, styles, history,
  before/after), Code Studio (workspaces, editor, terminal, tests, git, AI diffs you approve),
  Vision (upload, screen/region capture, camera, live assist), Research (opt-in web research with
  verified citations, offline answers clearly labelled), Automation, Computer Control, File
  Intelligence (local hybrid semantic search, cited Q&A, summaries, comparison, spreadsheet and
  codebase analysis), Memory, System Intelligence, Communications, Plugins.
- **Phone link**: QR pairing with single-use 5-minute token, TLS with certificate pinning,
  per-device secrets and scopes, instant revocation, streamed replies, push alerts, offline queue,
  voice, camera analysis, PC dashboard and remote commands, reminders, automations, file transfer,
  code help, SMS relay with on-phone approval.
- **Notifications**: desktop, phone, email (SMTP/IMAP with app password or OAuth2 PKCE with your
  own client ID), SMS (Twilio or your phone), ntfy; quiet hours, priorities, categories, rate limits,
  retries, emergency mute, delivery history.
- **Plugins**: QuickJS WebAssembly sandbox; tools, automation actions, notification channels,
  document readers, local model endpoints, dashboard widgets and pages; per-permission grants.

What was verified, how, and what was not: [docs/TEST-REPORT.md](docs/TEST-REPORT.md).
