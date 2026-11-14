# Installing VIPER

## Requirements

| | Minimum | Recommended |
|---|---|---|
| OS | Windows 10 22H2 (Ollama backend) | Windows 11 (Foundry Local) |
| RAM | 8 GB (tiny/light models) | 16 GB+ |
| GPU | none (CPU inference works) | NVIDIA/AMD/Intel GPU or NPU |
| Disk | 3 GB + models (0.4–5 GB each) | SSD |

Realistic speeds: 0.5–1.5B models run at 20–80 tokens/s on a modern CPU; 3–4B models at 8–25
tokens/s; 7–8B models need a GPU (30–80 tokens/s) and crawl on CPU (3–10 tokens/s). The Model
Manager measures the real numbers on your PC.

## 1. Install the desktop app

Run `VIPER-Windows-Setup.exe`. It installs per user (no admin rights) into
`%LOCALAPPDATA%\Programs\VIPER`, adds desktop and Start-menu shortcuts and registers an
uninstaller (Settings → Apps). Data lives in `%APPDATA%\VIPER` and is kept on uninstall unless you
delete it.

`VIPER-Portable.exe` runs VIPER without installing (it unpacks itself to a temporary folder on each
start, so it starts a little slower). It uses the same data folder, `%APPDATA%\VIPER`.

The installer is not code-signed, so Windows SmartScreen shows “Windows protected your PC” — choose
*More info → Run anyway*, or sign it with your own certificate (see *Building* below).

## 2. Choose an AI engine (wizard step 3–5)

**Microsoft Foundry Local** (Windows 11 recommended): the wizard's *Install Foundry Local* button
runs `winget install Microsoft.FoundryLocal` after you approve it. VIPER finds the service port
automatically with `foundry service status` and can start the service for you. Recommended models:
`phi-4-mini`, `qwen2.5-1.5b` (light), `qwen2.5-7b` (GPU/NPU).

**Ollama** (Windows 10/11): install from <https://ollama.com/download/windows>. VIPER downloads
models through Ollama with progress (e.g. `qwen3:4b`, `qwen2.5:7b`; `qwen2.5vl:3b` or `moondream`
for Vision; `nomic-embed-text` for semantic file search).

You can run both: e.g. Foundry Local for chat and Ollama for vision/embeddings — set each task's
model in *Models → Model per task*.

## 3. Voice (optional, ~230 MB)

*Voice* page → install the speech recognition engine (whisper.cpp v1.9.0, from its GitHub release),
a speech model (`base.en` recommended) and Piper with a voice (default: *Alan — British male*). Then
enable *Wake word*. Without Piper, Windows' own voices are used.

## 4. Image generation (optional)

VIPER does not bundle Stable Diffusion. Install **Stable Diffusion WebUI Forge** (free), start it
with `--api`, and VIPER connects at `http://127.0.0.1:7860`. Needs ~4 GB VRAM for SD 1.5 and
6–8 GB for SDXL; CPU generation works but takes minutes per image. Background removal needs the
rembg extension.

## 5. VIPER Mobile (Android 8.0+)

1. Copy `VIPER-Mobile.apk` to the phone and install it (allow “Install unknown apps” for your
   file manager). If you installed the 1.0.0 test build (“VIPER” with a debug label), uninstall it first.
2. On the PC: *Communications → Phone link → Show pairing code*.
3. In the app: *Scan pairing code*. No camera? Click *Copy pairing code* on the PC, send the text to
   the phone (e.g. e-mail to yourself) and share it to VIPER Mobile or paste it into the app. Both devices must be on the same Wi-Fi, or connected through a
   private VPN such as WireGuard or Tailscale for away-from-home use. Windows Firewall will ask to
   allow VIPER on private networks the first time — allow it.

## Building from source

Desktop (on Windows): install Node.js 22+, then `viper\scripts\build-windows.ps1`. From Linux use
`viper/scripts/build-windows.sh` (needs Wine for the NSIS step). Code signing: set `CSC_LINK` and
`CSC_KEY_PASSWORD` before building (electron-builder).

Android: JDK 17+, Android SDK platform 36; run `viper/scripts/build-android.sh`. For a signed
release APK set `VIPER_KEYSTORE`, `VIPER_KEYSTORE_PASSWORD`, `VIPER_KEY_ALIAS`, `VIPER_KEY_PASSWORD`.

Headless core (any OS): `cd viper/desktop && npm ci && npm run server`, then open the printed URL.

The GitHub Actions workflow `.github/workflows/viper.yml` builds and tests both on real Windows
and Linux runners.
