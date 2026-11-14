#!/usr/bin/env bash
# Cross-builds the Windows installer from Linux. Needs Node 22+ and Wine (wine64 + wine32) for the NSIS step.
set -euo pipefail
cd "$(dirname "$0")/../desktop"
npm ci
npm test
npx electron-builder --win nsis --x64 --publish never
ls -la dist/*.exe
