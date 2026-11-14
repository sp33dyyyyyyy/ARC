# VIPER test results and limitations

Build environment: Linux x64 cloud container (4 vCPU, 16 GB RAM, no GPU, no microphone, no
display except Xvfb, no KVM). Date: 2026-11-14.

## Automated tests — all executed

| Suite | Result | What it exercises |
|---|---|---|
| Desktop `npm test` (13 files) | **90 / 90 pass** | everything below |
| core | pass | migrations, settings persistence, encrypted vault, memory CRUD/search/import/export/temporary mode, API token + DNS-rebinding guard, path traversal, CSP, log redaction, time parsing |
| llm | pass | OpenAI-compatible streaming + tool calls (Foundry Local protocol), Foundry endpoint discovery parsing, role resolution, per-conversation model switching, perf metrics, crash-recovery hook, honest "no model" reply |
| orchestrator | pass (16) | intents ("are you online", reminder follow-up slot, memory, stop speaking, mode switch), native and text-protocol tool loops, denied/declined permissions, destructive-always-asks, **prompt-injection guard**, folder sandbox, cancellation, private chats not stored, search/pin/export, memory injection, context trimming |
| automation-notify | pass (11) | validation, schedules, **download-finished trigger with a real file**, conditions, failure alerts, pause/resume, reminders firing, quiet hours, emergency mute, categories, rate limit, retries, phone queueing, briefing |
| files-research | pass | real PDF/DOCX/XLSX/CSV extraction, folder indexing with embeddings, hybrid search, cited Q&A, citation validation, allowed-folder enforcement, offline research labelling |
| remote (phone protocol) | pass (10) | QR payload, certificate pinning, single-use token, hashed secrets, scopes, WebSocket streaming, push, file transfer, SMS relay, prompt routing to the requesting phone, instant revocation (close 4001) |
| plugins | pass | install/grant, tools/widgets/pages/actions, sandbox has no require/process/fetch, ungranted HTTP refused, infinite loop interrupted |
| comms-code | pass | SMTP delivery to a local fake SMTP server with auth, declined send blocked, self-notifications, scheduled outbox, templates; Code Studio scaffold, workspace path escape blocked, diff, terminal run (`node --test`), git init/commit |
| voice | pass | **real Piper TTS (British "Alan") → whisper.cpp base.en STT round trip**: "Viper, open my Downloads folder." transcribed in 1.3 s, wake word stripped |
| ollama.integration | pass (7) | **real local models**: qwen2.5:0.5b streaming (~82 tok/s on CPU), all-minilm embeddings, moondream reading "Error 404" from a screenshot, model download progress, unload/reload without restart |
| Electron smoke (`npm run test:electron`, Xvfb) | **10 / 10** | real app window from in-process core, preload isolation (no Node in renderer), first-run wizard, dashboard + core, chat event stream, floating HUD opens and is always-on-top |
| UI pass (Playwright, all 16 modes) | no console errors | every page renders; screenshots reviewed |
| Lint (`no-undef`, whole codebase) | clean | caught a missing account dialog, now implemented |
| Android JVM unit tests | **5 / 5 pass** | pairing-code parsing, rejection of foreign codes, fingerprint handling, wake-word extraction, WAV encoding |
| Android build | pass | debug APK (13 MB, installable) and minified release APK (1.8 MB, unsigned) |
| Windows installer build | pass | `VIPER-Setup-1.0.0.exe` (168 MB) + `latest.yml` built with electron-builder (Wine for the NSIS step) |

Bugs found and fixed by these tests: tool-call protocol mismatch causing a loop with unknown
OpenAI-compatible models; auto-selection picking a vision model for chat; stream events arriving
before the HTTP reply; late socket events after shutdown; leaked test-runner env in workspace
commands; HUD layout; unsupported `window.prompt` in Electron.

## Not verified here (needs real hardware or accounts)

| Area | Status |
|---|---|
| **Installer on real Windows** | Built but not run on Windows. Under Wine the app's core started (SQLite created, "core listening" logged) but the silent NSIS install aborted (exit 2), which is a Wine limitation we could not rule out. The CI workflow installs it silently on a real `windows-latest` runner and checks the shortcuts. |
| Windows-only tools | PowerShell Core Audio volume, window management, Start-menu/Store app discovery, `taskkill`, event log, DPAPI vault, global shortcuts, tray, login item, `desktopCapturer` screenshots: implemented, not executed on Windows. |
| Microsoft Foundry Local | Windows/macOS only, unavailable here. Implemented against the Microsoft Learn REST reference (Oct 2026) and tested with an OpenAI-compatible server; catalogue/download/load endpoints untested against the real service. |
| Live microphone, wake word, barge-in | No microphone. VAD/wake logic and the STT/TTS engines are tested; real-room accuracy is not. |
| Image generation | No Stable Diffusion engine/GPU here; only the "engine not running" path was exercised. |
| IMAP reading, OAuth sign-in, Twilio | No accounts. SMTP sending is tested against a fake server. |
| Android app on a device | No emulator (no KVM). The app compiles and its logic is unit-tested; the server side of its protocol is tested with a client that mirrors it exactly. Screens, camera, background service and SMS sending are untested on a phone. |
| Live web research | DuckDuckGo search parsing was verified live; a full multi-page research run was interrupted when the container ran out of resources, so it is not counted as passed. Offline labelling and citation validation are tested. |

## Known limitations

- Release APK and Windows installer are not code-signed (SmartScreen warning; release APK must be
  signed with your own key — see INSTALL.md). The shipped APK is the debug-signed build.
- `EncryptedSharedPreferences` is deprecated by Google but still functional; a Keystore-only store
  is a future change.
- Wake word uses VAD-gated local Whisper transcription rather than a dedicated keyword model, so it
  uses some CPU while you speak.
- CPU temperature on Windows is often not exposed to apps; VIPER reports "not available" rather
  than estimating.
- Small models (≤1.5B) answer simple questions well but choose tools unreliably; common commands
  are handled by the deterministic intent router for that reason.
