# 開機順序守護：把「GPU Unlock」排回韌體開機順序第一，並加一個工作排程（Windows 每次啟動時以 SYSTEM 執行同一件事），
# 因為 Windows／主機板會把 Windows Boot Manager 排回第一。結果存到 診斷結果\fix-order.txt。
# 由「修復開機順序.cmd」以系統管理員身分啟動；install.ps1 也會呼叫。檔案要存 UTF-8 with BOM。

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$State = Join-Path $Here '安裝資訊.json'
$EntryName = 'GPU Unlock'
$TaskName = 'GPU Unlock 排第一'
$Out = Join-Path $Here '診斷結果'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$id = $null
if (Test-Path $State) { $id = (Get-Content $State -Raw | ConvertFrom-Json).bcd_id }
if (-not $id) {
    $cur = $null
    foreach ($line in (bcdedit /enum firmware)) {
        if ($line -match '\{[0-9a-fA-F-]{36}\}') { $cur = $Matches[0] }
        if ($line -match [regex]::Escape($EntryName) -and $cur) { $id = $cur; break }
    }
}
if (-not $id) { Write-Host '找不到 GPU Unlock 開機項目，請先執行安裝' -ForegroundColor Red; exit 1 }

bcdedit /set '{fwbootmgr}' displayorder $id /addfirst | Out-Null

$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\bcdedit.exe" -Argument "/set {fwbootmgr} displayorder $id /addfirst"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

"task=$TaskName id=$id time=$(Get-Date -Format s)" | Set-Content (Join-Path $Out 'fix-order.txt')
bcdedit /enum '{fwbootmgr}' | Add-Content (Join-Path $Out 'fix-order.txt')
Write-Host "GPU Unlock 已排回第一，並加了工作排程「$TaskName」（每次 Windows 啟動都會再排一次）。" -ForegroundColor Green
