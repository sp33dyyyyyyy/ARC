# Architecture

```
┌──────────────────────── Electron (desktop/src/main) ─────────────────────────┐
│ main window · floating HUD · tray · global shortcuts · DPAPI vault · screen   │
│ capture · notifications · auto-update · login item                            │
│        │ preload bridge (contextIsolation, sandbox)                           │
│ ┌──────▼──────── renderer (desktop/src/renderer, vanilla ES modules) ───────┐ │
│ │ shell · animated core (canvas) · voice engine (AudioWorklet, VAD, wake) │ │
│ │ 16 mode pages · setup wizard · HUD                                       │ │
│ └──────┬───────────────────────────────────────────────────────────────────┘ │
│        │ HTTP + WebSocket, 127.0.0.1, token                                   │
│ ┌──────▼──────────── VIPER core (desktop/src/server, Node 24) ─────────────┐ │
│ │ orchestrator ─ intents fast-path ─ tool registry ─ permission engine      │ │
│ │ model manager ─ Foundry Local / Ollama / OpenAI-compatible backends       │ │
│ │ memory · reminders · automation · notifications · briefing · monitor      │ │
│ │ files · research · image · code · voice · comms · plugins (QuickJS)       │ │
│ │ SQLite (node:sqlite, WAL, FTS5) · encrypted vault · sanitised logs        │ │
│ │ remote link: HTTPS/WSS, self-signed cert, QR pairing, device scopes ──────┼─┼──► VIPER Mobile
│ └───────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
        │ local HTTP                        │ local processes
  Foundry Local / Ollama / llama.cpp   whisper.cpp · Piper · SD WebUI (optional)
```

## Request flow

1. A message (typed, spoken, from the HUD or phone) reaches `POST /api/v1/chat`.
2. The **intent router** handles unambiguous commands deterministically (status, reminders,
   memory, open/close, volume, mode switches, briefings…), calling the same tools the model would.
   Small local models are unreliable at tool selection; this keeps everyday commands instant.
3. Otherwise the **orchestrator** builds the prompt (personality, relevant memories, trimmed
   history + summary), selects ≤14 relevant tools and streams the model. Tool calls run through
   the registry (schema validation → permission engine → handler) and their results go back to the
   model, up to five rounds. Models without native tool calling use a text protocol.
4. Every step is published on the event bus and streamed over WebSocket to the UI, HUD and phones.

## Security model

- Local API bound to 127.0.0.1 with a random per-launch token; Host-header check against DNS
  rebinding; strict CSP; no Node in renderers; navigation and window-opening locked.
- Permission engine (see CONFIGURATION.md) with taint tracking for untrusted content.
- Phone link: TLS with a pinned self-signed certificate, single-use pairing token (5 min), hashed
  per-device secrets, scopes, rate-limited auth, immediate revocation (WebSocket close 4001).
- Plugins run in QuickJS/WebAssembly with memory/CPU limits and capability grants only.
- Web research refuses private-network URLs; citations are validated against fetched sources.

## Database

Tables: `settings`, `secrets`, `conversations`, `messages` (+`messages_fts`), `memories`
(+`memories_fts`), `reminders`, `automations`, `automation_runs`, `notifications`, `deliveries`,
`recipients`, `devices`, `activity`, `model_perf`, `documents`, `chunks` (+`chunks_fts`,
embeddings as float32 blobs), `research`, `images`, `email_accounts`, `email_templates`, `outbox`,
`plugins`, `workspaces`, `transcripts`. Versioned migrations in `src/server/db.js`.

## API

Versioned under `/api/v1`. Main groups: `status`, `settings`, `models`/`backend`, `chat`,
`conversations`, `confirm`, `tools`, `memory`, `reminders`, `automations`, `notifications`,
`system`, `vision`, `voice`, `files`, `research`, `image`, `code`, `comms`, `remote`, `plugins`.
WebSocket: `/api/v1/ws` (events: `chat.*`, `tool.*`, `confirm.*`, `notification`,
`system.sample`, `models.*`, `tasks.changed`, `ui.navigate`, `voice.*`, …). Phone-only:
`/api/v1/pair`, `/api/v1/transfer/*`, `/api/v1/sms/result`. Route handlers live in
`src/server/api.js` and each feature module's `routes()`.

## Android app

`mobile/app/src/main/java/com/viper/mobile`: `net/` (pinned OkHttp REST + WebSocket, pairing),
`data/Store.kt` (Keystore-encrypted preferences, offline queue), `voice/` (AudioRecord + VAD,
MediaPlayer/TextToSpeech), `ConnectionService` (optional foreground service for alerts and
hands-free listening), `ViperApp` (state, chat streaming, approvals, SMS bridge), `ui/` (Compose).
