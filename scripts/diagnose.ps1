# 診斷（只讀不改設定）：把韌體開機順序、GPU Unlock 項目、GPUUNLOCK 分割區裡的 loader.log 存到 診斷結果\。
# 會暫時給 GPUUNLOCK 一個磁碟代號來讀檔，讀完就拿掉。由「診斷開機自動解鎖.cmd」以系統管理員身分啟動。

$ErrorActionPreference = 'Continue'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out = Join-Path $Here '診斷結果'
New-Item -ItemType Directory -Force -Path $Out | Out-Null

bcdedit /enum firmware > (Join-Path $Out 'bcd-firmware.txt') 2>&1
bcdedit /enum '{fwbootmgr}' /v > (Join-Path $Out 'bcd-fwbootmgr.txt') 2>&1

$v = Get-Volume -FileSystemLabel 'GPUUNLOCK' -ErrorAction SilentlyContinue
if ($v) {
    $p = $v | Get-Partition
    "disk=$($p.DiskNumber) partition=$($p.PartitionNumber) guid=$($p.Guid) type=$($p.GptType)" | Set-Content (Join-Path $Out 'partition.txt')
    $p | Add-PartitionAccessPath -AssignDriveLetter
    Start-Sleep -Seconds 2
    $L = (Get-Partition -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber).DriveLetter
    if ($L) {
        Get-ChildItem "${L}:\" -Recurse | Select-Object FullName, Length, LastWriteTime | Out-File (Join-Path $Out 'files.txt')
        if (Test-Path "${L}:\loader.log") { Copy-Item "${L}:\loader.log" (Join-Path $Out 'loader.log') }
        Remove-PartitionAccessPath -DiskNumber $p.DiskNumber -PartitionNumber $p.PartitionNumber -AccessPath "${L}:\"
    }
} else {
    'GPUUNLOCK not found' | Set-Content (Join-Path $Out 'partition.txt')
}
Write-Host '診斷完成，可以關掉這個視窗。' -ForegroundColor Green
