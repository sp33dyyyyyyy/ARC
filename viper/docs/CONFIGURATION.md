# Configuration

Everything is configurable in the app (Settings, Models, Voice, Communications). Settings are
stored in SQLite (`%APPDATA%\VIPER\viper.db`, table `settings`) as JSON sections and take effect
immediately.

## Data locations (`%APPDATA%\VIPER`)

| Path | Contents |
|---|---|
| `viper.db` | Conversations, memory, reminders, automations, notifications, devices, document index, activity log, encrypted secrets |
| `logs/` | Daily logs with secrets redacted, pruned after 14 days |
| `components/` | whisper.cpp, Piper, speech models, voices |
| `images/`, `screenshots/`, `research/`, `transfers/`, `exports/` | Generated and saved files |
| `plugins/` | Installed plugins (each with its own sandboxed storage) |
| `certs/` | The phone-link TLS key and self-signed certificate |

Delete everything from *Settings → Privacy & permissions → Delete data*.

## Credentials

Passwords, OAuth refresh tokens, the Twilio token and the ntfy token are encrypted with Windows
DPAPI through Electron `safeStorage` (bound to your Windows account) and stored in the `secrets`
table. In the headless server mode, a local AES-256-GCM key file is used instead and the About
page says so. No API keys are hardcoded anywhere.

## Permissions

Each tool belongs to a category with mode **Allow**, **Ask** or **Deny** (*Settings → Privacy &
permissions*). Defaults: reading system state, opening apps/folders/websites and volume are
allowed; closing apps, writing files, clipboard, screenshots, web access, scripts, workspace
commands, email and SMS ask. Regardless of the mode:

- destructive actions (closing apps, deleting files, sending email/SMS, running workspace
  commands) always ask;
- any action requested after VIPER has read external content (web page, email, file, clipboard,
  plugin output) asks, and that content is wrapped as untrusted data in the prompt;
- file tools only touch **Allowed folders** (default Documents, Downloads, Desktop);
- scripts can only be run if listed in **Approved scripts**;
- phones can only reach API scopes granted to that device and only answer their own prompts.

Every action is recorded in the activity log (*Settings → Activity log*).

## Performance

*Settings → Performance* has three profiles. **Automatic** picks one from the hardware VIPER
detects, and you can switch at any time:

| | Eco | Balanced (default on a Core i7 / 16 GB / integrated-graphics laptop) | Performance |
|---|---|---|---|
| Interface | reduced animation, 30 fps | full animation, 60 fps (30 fps while the AI is generating) | 60 fps |
| Context window | 2,048 tokens | 4,096 tokens | 8,192 tokens |
| Models kept in RAM at once | 1 | 1 | 2 |
| Idle model unloaded after | 2 min | 10 min | 30 min |
| Background warm-up | off | on | on |
| CPU cores kept free for the UI | 2 | 1 | 0 |

How the speed-ups work:

- **Prompt cache.** The system prompt and the base tool list never change between messages.
  The current time and remembered facts are added to your latest message instead. Local
  engines can then reuse their cache and only process the new turn.
- **Warm-up.** Shortly after start-up, VIPER loads the chat model and pre-processes its
  instructions in the background, so the first reply starts sooner.
- **One model in memory.** Before a different model runs (for example vision after chat),
  other idle models are unloaded, so chat, code and vision models never all occupy RAM together.
- **Threads.** CPU inference uses one thread per performance core. On Intel CPUs with
  efficiency cores, the E-cores are left for Windows and the interface.
- **Animation.** The core animation reduces its own detail if drawing becomes slow (adaptive
  quality). It stops completely while VIPER is minimised, hidden or scrolled out of view.

Every value (context window, threads, GPU layers, keep-alive, frame-rate limit, models in
memory) can still be changed individually. The *Measured speed* table shows real tokens per
second and time to first token for each model on your PC.

## Environment variables

| Variable | Purpose |
|---|---|
| `VIPER_DATA_DIR` | Use another data folder |
| `VIPER_COMPONENTS_DIR` | Use another folder for voice engines/models |
| `VIPER_PORT`, `VIPER_TOKEN`, `VIPER_ECHO` | Headless server port, fixed access token, echo logs |

## Network ports

| Port | Bound to | Purpose |
|---|---|---|
| 47800 | 127.0.0.1 only | Local API + UI (per-launch random token, Host-header check) |
| 47801 | all interfaces, only while the phone link is on | HTTPS/WSS for paired phones |
