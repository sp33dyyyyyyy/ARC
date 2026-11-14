#!/usr/bin/env bash
# Builds VIPER Mobile. Needs JDK 17+ and the Android SDK (platform 36, build-tools 36) with ANDROID_HOME set.
# Release signing: export VIPER_KEYSTORE, VIPER_KEYSTORE_PASSWORD, VIPER_KEY_ALIAS, VIPER_KEY_PASSWORD.
set -euo pipefail
cd "$(dirname "$0")/../mobile"
./gradlew --no-daemon testDebugUnitTest assembleDebug assembleRelease
ls -la app/build/outputs/apk/*/
