# 移除開機自動解鎖：刪開機項目、刪 GPUUNLOCK 分割區、把空間還給 D 槽、刪捷徑。
# 由「移除開機自動解鎖.cmd」以系統管理員身分啟動。檔案要存 UTF-8 with BOM。

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$State = Join-Path $Here '安裝資訊.json'
$Label = 'GPUUNLOCK'
$EntryName = 'GPU Unlock'

Start-Transcript -Path (Join-Path $Here '安裝紀錄.txt') -Append | Out-Null
function Step($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }

try {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { throw '要用系統管理員身分執行（請點「移除開機自動解鎖.cmd」）' }
    $s = if (Test-Path $State) { Get-Content $State -Raw | ConvertFrom-Json } else { $null }
    Write-Host '會刪掉開機項目「GPU Unlock」和 GPUUNLOCK 分割區（裡面只有解鎖程式），空間還給 D 槽。'
    $ans = Read-Host '確定要移除嗎？輸入 Y 再按 Enter（其他鍵取消）'
    if ($ans -ne 'Y' -and $ans -ne 'y') { Write-Host '你取消了，什麼都沒改'; Stop-Transcript | Out-Null; exit 0 }

    Step '1/3 刪開機項目'
    $ids = @()
    if ($s -and $s.bcd_id) { $ids += $s.bcd_id }
    # 用名稱再找一次，避免 安裝資訊.json 遺失
    $cur = $null
    foreach ($line in (bcdedit /enum firmware)) {
        if ($line -match '\{[0-9a-fA-F-]{36}\}') { $cur = $Matches[0] }
        if ($line -match [regex]::Escape($EntryName) -and $cur) { $ids += $cur }
    }
    foreach ($id in ($ids | Select-Object -Unique)) { bcdedit /delete $id /f | Out-Null; Write-Host "已刪 $id" }
    if (Get-ScheduledTask -TaskName 'GPU Unlock 排第一' -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName 'GPU Unlock 排第一' -Confirm:$false
        Write-Host '已刪工作排程「GPU Unlock 排第一」'
    }

    Step '2/3 刪 GPUUNLOCK 分割區並還給 D 槽'
    $v = Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue
    if ($v) {
        $p = $v | Get-Partition
        if ($p.Size -gt 1GB) { throw "GPUUNLOCK 分割區超過 1 GB，不像是安裝程式建的，停止" }
        Remove-Partition -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -Confirm:$false
        $from = if ($s) { $s.from } else { 'D' }
        $max = (Get-PartitionSupportedSize -DriveLetter $from).SizeMax
        Resize-Partition -DriveLetter $from -Size $max
        Write-Host "已刪分割區，$from 槽恢復原本大小"
    } else { Write-Host '找不到 GPUUNLOCK 分割區（可能已經刪過）' }

    Step '3/3 刪捷徑'
    foreach ($d in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'))) {
        $f = Join-Path $d '檢查顯卡解鎖.lnk'
        if (Test-Path $f) { Remove-Item $f; Write-Host "已刪 $f" }
    }
    if (Test-Path $State) { Remove-Item $State }
    Write-Host ''
    Write-Host '移除完成。之後開機會直接進 Windows，顯卡回到原廠速度。' -ForegroundColor Green
}
catch {
    Write-Host ''; Write-Host "停止：$($_.Exception.Message)" -ForegroundColor Red
}
Stop-Transcript | Out-Null
