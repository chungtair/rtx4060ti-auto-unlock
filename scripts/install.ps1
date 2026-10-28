# 安裝開機自動解鎖：從 D 槽切 300 MB 做 FAT32 分割區（GPUUNLOCK），放 nv-uefi-unlocker，
# 加一個開機項目排第一，每次開機自動解鎖後接著進 Windows。另加登入自動檢查。
# 由「安裝開機自動解鎖.cmd」以系統管理員身分啟動。檔案要存 UTF-8 with BOM（PowerShell 5.1 才讀得懂中文）。

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src = Join-Path (Split-Path -Parent $Here) '參考程式碼\nv-usbroot'
$State = Join-Path $Here '安裝資訊.json'
$Label = 'GPUUNLOCK'
$EntryName = 'GPU Unlock'
$SizeMB = 300
$FromLetter = 'D'
$Python = 'D:\ComfyUI\python_embeded\pythonw.exe'
$Files = @('booter_load_ad102.bin', 'gsp_boot_desc_ad102.bin', 'gsp_boot_ad102.bin', 'fwimage_ad102.bin',
           'fwsignature_ad102.bin', 'scrubber_ad10x.bin', 'v67-ad102-four-plm.bin')

Start-Transcript -Path (Join-Path $Here '安裝紀錄.txt') -Append | Out-Null
function Step($t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
function Fail($t) { Write-Host ''; Write-Host "停止：$t" -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }

try {
    Step '檢查'
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { Fail '要用系統管理員身分執行（請點「安裝開機自動解鎖.cmd」，跳出視窗時按「是」）' }
    if (Test-Path $State) { Fail '已經安裝過了（有 安裝資訊.json）。要重裝請先執行「移除開機自動解鎖.cmd」' }
    if (Get-Volume -FileSystemLabel $Label -ErrorAction SilentlyContinue) { Fail "電腦裡已經有標籤 $Label 的分割區" }
    if ((bcdedit /enum firmware) -match [regex]::Escape($EntryName)) { Fail "開機選單裡已經有「$EntryName」" }
    foreach ($f in $Files + 'BOOTX64.EFI') {
        if (-not (Test-Path (Join-Path $Src $f))) { Fail "找不到解鎖檔案 $Src\$f" }
    }
    if (-not (Test-Path $Python)) { Fail "找不到 $Python（登入檢查要用）" }

    $dPart = Get-Partition -DriveLetter $FromLetter
    $disk = $dPart.DiskNumber
    $range = Get-PartitionSupportedSize -DriveLetter $FromLetter
    $newSize = $dPart.Size - ($SizeMB + 2) * 1MB
    if ($newSize -lt $range.SizeMin) { Fail "$FromLetter 槽沒辦法再縮 $SizeMB MB" }
    Write-Host ("{0} 槽：磁碟 {1}，現在 {2:N1} GB，會縮成 {3:N1} GB，空出 {4} MB 給解鎖程式。原本的檔案不會動。" -f $FromLetter, $disk, ($dPart.Size / 1GB), ($newSize / 1GB), $SizeMB)
    Write-Host '接著會：切分割區 → 放解鎖程式 → 加開機項目並排第一 → 加登入自動檢查。'
    $ans = Read-Host '確定要開始嗎？輸入 Y 再按 Enter（其他鍵取消）'
    if ($ans -ne 'Y' -and $ans -ne 'y') { Fail '你取消了，什麼都沒改' }

    Step "1/6 縮小 $FromLetter 槽"
    Resize-Partition -DriveLetter $FromLetter -Size $newSize

    Step '2/6 建立 FAT32 分割區'
    $p = New-Partition -DiskNumber $disk -Size ($SizeMB * 1MB) -AssignDriveLetter
    Start-Sleep -Seconds 2
    $p = Get-Partition -DiskNumber $disk -PartitionNumber $p.PartitionNumber
    Format-Volume -Partition $p -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false -Force | Out-Null
    $L = $p.DriveLetter
    if (-not $L) { Fail '新分割區沒有拿到磁碟代號' }
    Write-Host "新分割區：磁碟 $disk 第 $($p.PartitionNumber) 個，暫時代號 ${L}:"
    @{ disk = $disk; partition = $p.PartitionNumber; from = $FromLetter; installed = (Get-Date -Format s) } |
        ConvertTo-Json | Set-Content -Path $State -Encoding UTF8

    Step '3/6 放解鎖程式並核對指紋'
    New-Item -ItemType Directory -Force -Path "${L}:\EFI\BOOT" | Out-Null
    Copy-Item (Join-Path $Src 'BOOTX64.EFI') "${L}:\EFI\BOOT\BOOTX64.EFI"
    foreach ($f in $Files) { Copy-Item (Join-Path $Src $f) "${L}:\$f" }
    # 有這個檔 = 開機時 5 秒倒數後自動解鎖（倒數中按任意鍵可跳過）
    Set-Content -Path "${L}:\i_know_what_i_am_doing.txt" -Value 'auto-run at every boot (installed by install.ps1)' -Encoding ASCII
    $checks = @{ 'EFI\BOOT\BOOTX64.EFI' = 'BOOTX64.EFI' }
    foreach ($f in $Files) { $checks[$f] = $f }
    foreach ($dst in $checks.Keys) {
        $a = (Get-FileHash (Join-Path $Src $checks[$dst])).Hash
        $b = (Get-FileHash "${L}:\$dst").Hash
        if ($a -ne $b) { Fail "指紋不符：$dst" }
    }
    Write-Host '檔案都放好了，指紋全部相符'

    Step '4/6 加開機項目並排第一'
    $out = bcdedit /copy '{bootmgr}' /d $EntryName
    $id = [regex]::Match(($out -join ' '), '\{[0-9a-fA-F-]{36}\}').Value
    if (-not $id) { Fail "bcdedit 沒有回傳項目編號：$out" }
    bcdedit /set $id device "partition=${L}:" | Out-Null
    bcdedit /set $id path '\EFI\BOOT\BOOTX64.EFI' | Out-Null
    bcdedit /set '{fwbootmgr}' displayorder $id /addfirst | Out-Null
    $s = Get-Content $State -Raw | ConvertFrom-Json
    $s | Add-Member -NotePropertyName bcd_id -NotePropertyValue $id
    $s | ConvertTo-Json | Set-Content -Path $State -Encoding UTF8
    Write-Host "開機項目 $id 已排第一"
    # Windows／主機板會把 Windows Boot Manager 排回第一（2026-10-28 實測），加工作排程每次啟動再排一次
    & (Join-Path $Here 'fix_order.ps1')

    Step '5/6 拿掉暫時代號（避免被誤刪）'
    Remove-PartitionAccessPath -DiskNumber $disk -PartitionNumber $p.PartitionNumber -AccessPath "${L}:\"

    Step '6/6 加登入自動檢查與桌面捷徑'
    $ws = New-Object -ComObject WScript.Shell
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = $ws.CreateShortcut((Join-Path $startup '檢查顯卡解鎖.lnk'))
    $lnk.TargetPath = $Python
    $lnk.Arguments = "-I `"$Here\check_unlock.py`" --wait 20"
    $lnk.WorkingDirectory = $Here
    $lnk.Save()
    $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) '檢查顯卡解鎖.lnk'))
    $lnk.TargetPath = $Python
    $lnk.Arguments = "-I `"$Here\check_unlock.py`""
    $lnk.WorkingDirectory = $Here
    $lnk.Save()

    Step '完成'
    Write-Host '目前的開機順序（第一個應該是 GPU Unlock，第二個是 Windows Boot Manager）：'
    bcdedit /enum '{fwbootmgr}'
    Write-Host ''
    Write-Host '下次開機（重新啟動或關機再開）會先自動解鎖，再進 Windows。登入約 20 秒後會跳通知。' -ForegroundColor Green
}
catch {
    Fail $_.Exception.Message
}
Stop-Transcript | Out-Null
