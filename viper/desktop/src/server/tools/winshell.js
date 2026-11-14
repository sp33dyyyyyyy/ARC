'use strict';
// Safe PowerShell runner. Scripts are fixed strings bundled with VIPER; all
// dynamic values are passed through environment variables (VIPER_ARG_*),
// never interpolated into code, so model output cannot inject commands.
const { execFile } = require('node:child_process');

function runPowerShell(script, args = {}, timeout = 20000) {
  return new Promise((resolve) => {
    if (process.platform !== 'win32') return resolve({ ok: false, error: 'Windows only', stdout: '' });
    const env = { ...process.env };
    for (const [k, v] of Object.entries(args)) env[`VIPER_ARG_${k.toUpperCase()}`] = String(v ?? '');
    execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      { env, timeout, windowsHide: true, maxBuffer: 8 * 1024 * 1024 },
      (err, stdout, stderr) => resolve({ ok: !err, stdout: String(stdout || '').trim(), stderr: String(stderr || '').trim(), error: err?.message }));
  });
}

function run(cmd, args, timeout = 15000) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout, windowsHide: true, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) =>
      resolve({ ok: !err, stdout: String(stdout || '').trim(), stderr: String(stderr || '').trim(), error: err?.message }));
  });
}

// CoreAudio master volume via COM interop (no external utilities required).
const VOLUME_PS = `
$ErrorActionPreference = 'Stop'
Add-Type -Language CSharp -TypeDefinition @"
using System; using System.Runtime.InteropServices;
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  int f(); int g(); int h(); int i();
  int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
  int j();
  int GetMasterVolumeLevelScalar(out float pfLevel);
  int k(); int l(); int m(); int n();
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
  int GetMute(out bool pbMute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume aev); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int f(); int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
public class ViperAudio {
  static IAudioEndpointVolume Vol() {
    var enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
    IMMDevice dev = null; Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out dev));
    IAudioEndpointVolume epv = null; var epvid = typeof(IAudioEndpointVolume).GUID;
    Marshal.ThrowExceptionForHR(dev.Activate(ref epvid, 23, 0, out epv)); return epv;
  }
  public static float Get() { float v = -1; Marshal.ThrowExceptionForHR(Vol().GetMasterVolumeLevelScalar(out v)); return v; }
  public static void Set(float v) { Marshal.ThrowExceptionForHR(Vol().SetMasterVolumeLevelScalar(v, Guid.Empty)); }
  public static bool GetMute() { bool m; Marshal.ThrowExceptionForHR(Vol().GetMute(out m)); return m; }
  public static void SetMute(bool m) { Marshal.ThrowExceptionForHR(Vol().SetMute(m, Guid.Empty)); }
}
"@
$op = $env:VIPER_ARG_OP
if ($op -eq 'set') { [ViperAudio]::Set([float]$env:VIPER_ARG_LEVEL / 100) }
elseif ($op -eq 'mute') { [ViperAudio]::SetMute($true) }
elseif ($op -eq 'unmute') { [ViperAudio]::SetMute($false) }
$lvl = [Math]::Round([ViperAudio]::Get() * 100)
$m = [ViperAudio]::GetMute()
Write-Output ("{""level"":" + $lvl + ",""muted"":" + $m.ToString().ToLower() + "}")
`;

const WINDOW_PS = `
$ErrorActionPreference = 'Stop'
Add-Type @"
using System; using System.Runtime.InteropServices;
public class ViperWin {
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
$name = $env:VIPER_ARG_NAME
$action = $env:VIPER_ARG_ACTION
$procs = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.ProcessName -like "*$name*" -or $_.MainWindowTitle -like "*$name*") }
if (-not $procs) { Write-Output '{"ok":false,"error":"No matching window"}'; exit 0 }
$p = $procs | Select-Object -First 1
$h = $p.MainWindowHandle
switch ($action) {
  'minimize' { [ViperWin]::ShowWindowAsync($h, 6) | Out-Null }
  'maximize' { [ViperWin]::ShowWindowAsync($h, 3) | Out-Null }
  'restore'  { [ViperWin]::ShowWindowAsync($h, 9) | Out-Null }
  'focus'    { [ViperWin]::ShowWindowAsync($h, 9) | Out-Null; [ViperWin]::SetForegroundWindow($h) | Out-Null }
}
Write-Output ('{"ok":true,"title":' + ($p.MainWindowTitle | ConvertTo-Json) + ',"process":' + ($p.ProcessName | ConvertTo-Json) + '}')
`;

const LIST_WINDOWS_PS = `Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | Select-Object ProcessName, Id, MainWindowTitle | ConvertTo-Json -Compress`;

const START_APPS_PS = `Get-StartApps | Select-Object Name, AppID | ConvertTo-Json -Compress`;

const EVENTLOG_PS = `try { $e = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 50 -ErrorAction Stop | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, @{n='Message';e={($_.Message -split [Environment]::NewLine)[0]}}; $e | ConvertTo-Json -Compress } catch { '[]' }`;

module.exports = { runPowerShell, run, VOLUME_PS, WINDOW_PS, LIST_WINDOWS_PS, START_APPS_PS, EVENTLOG_PS };
