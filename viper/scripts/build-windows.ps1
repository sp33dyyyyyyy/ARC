# Builds the VIPER Windows installer on a Windows 10/11 PC.
# Requirements: Node.js 22+ (https://nodejs.org). Output: viper\desktop\dist\VIPER-Setup-<version>.exe
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\desktop')
npm ci
npm test
npx electron-builder --win nsis --x64 --publish never
Write-Host "Installer: $(Resolve-Path dist\VIPER-Setup-*.exe)"
