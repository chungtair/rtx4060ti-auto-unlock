# RTX 4060 Ti 16GB (MSI, 10de:2803) Tensor Unlock on Windows — Auto-Unlock at Every Boot, No USB Stick

**MSI RTX 4060 Ti 16GB · MSI MAG B550M MORTAR WIFI · Ryzen 5 5600X (no iGPU) · Windows 11**

Shared by **忠台AI智能客服 ChungTair AI** ([chungtair.com](https://chungtair.com)) — we run local AI image/video generation on this machine every day, and this is our field report.

[繁體中文版在下面 ↓](#繁體中文)

---

## TL;DR

- Unlocked with [physicsdolphin/nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker) v2.1.4 (built locally), on a desktop where the **only display is on the 4060 Ti** (AMD B550, no iGPU).
- **Sustained** FP16→FP32 GEMM at the stock 165 W limit: **45.72 → 67.30 TFLOPS (+47%)**. BF16 46.06 → 69.00, TF32 22.20 → 32.47.
- Real work: image generation **1.51× faster**, 14B video sampling **1.47× faster**. Images with the same seed are **pixel-identical** to the stock run.
- Made it **unlock automatically on every boot without a USB stick**: a small FAT32 partition on a data disk plus a firmware boot entry. On this MSI board the BIOS ignores the boot order Windows writes, so **Boot Option #1 must be set in the BIOS**.

## What this does and does not do

- **Does not** modify the NVIDIA driver (stock 610.88 is used as-is).
- **Does not** flash the VBIOS. Nothing on the card is permanently changed.
- **Does**, before the driver loads, use a known vulnerability in NVIDIA's signed Booter firmware to open the register lock, then switch the card's own speed selectors to full rate (`SS0=0x88888888`, `SS1=0x8`).
- The effect lasts until power-off. After a power cycle the card is back to stock, so it has to run at every boot.

## Hardware and software

| Item | Value |
|---|---|
| GPU | MSI RTX 4060 Ti 16GB, AD106, `10de:2803`, subsystem `1462:5174`, VBIOS 95.06.34.00.f3 |
| Power limit | 165 W (stock, not raised, no undervolt) |
| GPU location | PCI `2b:00.0`, upstream bridge `00:03.1` (`1022:1483`) |
| Motherboard | MSI MAG B550M MORTAR WIFI (MS-7C94) |
| CPU | AMD Ryzen 5 5600X (**no iGPU**, the 4060 Ti drives the only monitor) |
| OS | Windows 11 Pro 26200, Secure Boot off |
| Driver | NVIDIA 610.88 (unmodified) |
| Benchmark env | PyTorch 2.14.1+cu130, ComfyUI v0.43.0 |
| Unlocker | nv-uefi-unlocker v2.1.4 (`8d925da`), `make-usbroot.ps1 -Family ad102` |

## Results (matched pair: same driver, same power limit, same models, same seeds)

### Layer 1: GEMM, 8192³, sustained

Each mode runs **continuously for ~4 seconds, 3 times**, median reported. Script: [`scripts/gemm_bench.py`](scripts/gemm_bench.py).

| Mode | Stock | Unlocked | Gain |
|---|---:|---:|---:|
| FP16 → FP32 accumulate | 45.72 | **67.30** | +47% |
| BF16 → FP32 accumulate | 46.06 | **69.00** | +50% |
| TF32 | 22.20 | **32.47** | +46% |
| FP32 (control) | 12.15 | 12.02 | unchanged |
| FP16 → FP16 accumulate (control) | 71.03 | 70.28 | unchanged |

- Stock FP16 ran at 2655 MHz / 165 W. Unlocked FP16 runs at **2190 MHz / 165 W**: the card is **power-limited**, so it lands at ~+50%, not 2×.
- FP16/BF16 correctness check against an FP64 reference passed.

### Layer 2: Image generation (ComfyUI, Z-Image-Turbo bf16, 1024×1024, 8 steps)

| | Stock | Unlocked | |
|---|---:|---:|---:|
| Per image (model loaded) | 12.1 s | **8.0 s** | **1.51×** |
| First image (incl. model load) | 19.3 s | 15.2 s | 21% faster |

The seed-43 image is **100% pixel-identical** before and after the unlock: same quality, just faster.

### Layer 3: Video (Wan 2.2 I2V 14B fp8 + lightx2v 4-step, 640×640, 81 frames)

| | Stock | Unlocked | |
|---|---:|---:|---:|
| Sampling (4 steps) | ~122 s | **~83 s** | **1.47×** |
| Total (incl. loading two 14B models, VAE decode, save) | 166.9 s | 122.1 s | 27% faster |

Model loading, VAE decode and saving do not use the tensor path, so the end-to-end saving is 20–30%.

### Why 67 and not the 75–80 in other 4060 Ti reports?

Other public 4060 Ti numbers (75–78 TFLOPS) time **10 GEMMs, about 0.15 s in total**. That is a short burst, and the 165 W limit (an average over time) does not catch up within it, so the card boosts higher (~2355 MHz in one report). Our benchmark runs **continuously for several seconds**, which pins the card at 165 W and 2190 MHz. Diffusion and video workloads run for many seconds, so we think the sustained number is closer to what you actually get. Our end-to-end image speedup (1.51×) is close to the 1.57× ComfyUI result reported on another 4060 Ti 16GB.

(We have not yet re-run the short-burst protocol on this card.)

## Unlock transaction (summary of `\loader.log`)

- Upstream bridge `00:03.1` command `0x0003` → `0x0007` (restored afterwards)
- Booter `MAILBOX0=0x67b00001`
- Selectors `SS0=0x88888888`, `SS1=0x8`, still set after FLR, `readout1=0`
- Chain-loads Windows Boot Manager

On this board the upstream bridge does **not** have Bus Master enabled by the firmware (`0x0003`). nv-uefi-unlocker's `BridgeMaster` fix is required here; without it the Booter cannot read WprMeta (`MAILBOX0=0x89`).

## Auto-unlock at every boot (no USB stick)

Plugging a USB stick in and pressing F11 every boot gets old fast. What we did instead ([`scripts/install.ps1`](scripts/install.ps1)):

1. Shrink a **data disk** (not the system disk) by 300 MB and create a FAT32 partition labelled `GPUUNLOCK`.
2. Copy `EFI\BOOT\BOOTX64.EFI` and the locally generated `*.bin` files onto it, then verify every file's SHA-256.
3. Add `i_know_what_i_am_doing.txt` → the loader auto-runs after a 5-second countdown (press any key to skip once).
4. `bcdedit /copy {bootmgr} /d "GPU Unlock"`, then `device partition=X:` and `path \EFI\BOOT\BOOTX64.EFI`, and put it first in `{fwbootmgr} displayorder`.
5. Remove the drive letter so nobody deletes the files by accident.
6. At logon, [`scripts/check_unlock.py`](scripts/check_unlock.py) runs a quick FP16 GEMM and shows a Windows notification (≥58 unlocked / ≤52 not unlocked).

[`scripts/uninstall.ps1`](scripts/uninstall.ps1) reverts everything.

### ⚠️ The MSI BIOS pitfall

After installing, the first reboots were **not** unlocked (46 TFLOPS), even though `bcdedit` showed "GPU Unlock" first. Choosing it manually with F11 worked (68.6). The loader log on the partition had **no new entry** for the failed boots, so the loader had never been started.

**This MSI B550 board boots from its own BIOS boot order and ignores the `{fwbootmgr}` order written from Windows.** Fix: BIOS → Del → F7 (Advanced) → Settings → Boot → **Boot Option #1 = GPU Unlock** (may be shown as the disk's name) → F10. After that the logon check read 69.6 TFLOPS: unlocked automatically.

Remember to set it again after a BIOS update or a CMOS reset.

## Other pitfalls

- **Build in a pure-ASCII path.** Our project folder has a Chinese name, and the build broke there. Copying the source to an English-only path fixed it.
- **The USB stick's FAT got corrupted once** (folder names turned to garbage) before the first rehearsal. After reformatting it was fine. Run `chkdsk` after copying files.
- **Rehearse first.** Leaving out `v67-ad102-four-plm.bin` makes the loader run all checks without writing the selectors. Our rehearsal passed cleanly before we did the real unlock.
- With no iGPU, the screen goes black for a few seconds during the unlock. That is expected.

## What is NOT in this repo

NVIDIA firmware, the generated `*.bin` assets, the built `BOOTX64.EFI` and VBIOS/ROM dumps are NVIDIA's copyrighted material. **They are not included.** Generate them yourself with nv-uefi-unlocker's `make-usbroot.ps1`, which downloads the official sources and verifies their SHA-256.

## Disclaimer

This is a record of **one machine**. It writes GPU registers and changes boot settings. It may void your warranty and could leave your PC needing a power cycle or a BIOS fix. The scripts are written for this machine (paths such as `D:` and `D:\ComfyUI` are hard-coded, `install.ps1` expects the generated files in `..\參考程式碼\nv-usbroot`, and messages are in Traditional Chinese). Read them before you adapt anything. Everything here is provided as-is, with no warranty. **Use at your own risk.**

We are not affiliated with NVIDIA or MSI. NVIDIA, GeForce, RTX and MSI are trademarks of their respective owners.

Recovery: if boot hangs, press F11 at power-on and choose **Windows Boot Manager**.

## Credits

- [physicsdolphin/nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker): the Windows UEFI unlocker we used
- [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock): the original research
- [JustAResearcher/gpu-unlock-ada](https://github.com/JustAResearcher/gpu-unlock-ada): Ada support and reports
- [impacifist/Windows-GPU-UNLOCK](https://github.com/impacifist/Windows-GPU-UNLOCK): Windows UEFI groundwork

---

<a id="繁體中文"></a>

# 繁體中文

# RTX 4060 Ti 16GB（MSI，10de:2803）Windows 解鎖：不用隨身碟，每次開機自動解鎖

**MSI RTX 4060 Ti 16GB · MSI MAG B550M MORTAR WIFI · Ryzen 5 5600X（沒有內顯）· Windows 11**

由 **忠台AI智能客服**（[chungtair.com](https://chungtair.com)）分享。我們每天用這台電腦跑本地 AI 作圖、做影片，這是我們的實測紀錄。

## 重點

- 用 [nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker) v2.1.4（自己編譯）解鎖。這台螢幕只接 4060 Ti（AMD B550，沒有內顯）。
- 原廠 165 W 功耗、**連續滿載**的 FP16 矩陣乘法：**45.72 → 67.30 TFLOPS（+47%）**；BF16 46.06 → 69.00、TF32 22.20 → 32.47。
- 實際使用：作圖 **1.51 倍速**、14B 影片算圖 **1.47 倍速**。同一個種子畫出來的圖，跟解鎖前**逐像素完全相同**。
- 做到**每次開機自動解鎖、不用隨身碟**：在資料碟切一塊 FAT32 小分割區，再加一個開機項目。這片 MSI 主機板不理 Windows 寫的開機順序，**要在 BIOS 把 Boot Option #1 設成它**。

## 這個做法有改什麼、沒改什麼

- **沒有**修改 NVIDIA 驅動（原版 610.88 直接用）。
- **沒有**刷顯卡 BIOS，顯卡不會有任何永久改變。
- 做法是在驅動載入前，利用 NVIDIA 原廠簽名韌體（Booter）一個已知的漏洞打開暫存器的鎖，把顯卡自己的速度開關切到全速（`SS0=0x88888888`、`SS1=0x8`）。
- 效果維持到斷電，斷電後回原廠狀態，所以每次開機都要重做。

## 測速結果（破解前後同一個驅動、同功耗、同模型、同種子）

**第一層：矩陣乘法 8192³（每種連續跑約 4 秒、量 3 次取中位數）**

| 模式 | 破解前 | 破解後 | 提升 |
|---|---:|---:|---:|
| FP16（FP32 累加） | 45.72 | **67.30** | +47% |
| BF16（FP32 累加） | 46.06 | **69.00** | +50% |
| TF32 | 22.20 | **32.47** | +46% |
| FP32（對照，不該變） | 12.15 | 12.02 | 不變 |
| FP16（FP16 累加，對照） | 71.03 | 70.28 | 不變 |

破解後吃滿 165 W、時脈 2190 MHz，卡在功耗上限，所以是 +50% 左右，不是 2 倍。FP16、BF16 的計算結果都跟雙精度參考值比對過，正確。

**第二層：作圖（ComfyUI，Z-Image-Turbo bf16，1024×1024，8 步）**：每張 12.1 秒 → **8.0 秒（1.51 倍速）**；第一張含載入模型 19.3 → 15.2 秒。

**第三層：影片（Wan 2.2 I2V 14B fp8＋lightx2v 4 步，640×640，81 格）**：算圖約 122 → **83 秒（1.47 倍速）**；總時間 166.9 → 122.1 秒（載入模型、解碼、存檔不會變快）。

### 為什麼我們是 67，別人的 4060 Ti 報告是 75～80？

別人公開的 75～78 只跑 10 次矩陣乘法，**總共約 0.15 秒**，是瞬間短跑。165 W 功耗上限是看一段時間的平均，還來不及壓下時脈測試就結束了（有一份紀錄是 2355 MHz）。我們是**連續滿載好幾秒**，會被壓在 165 W、2190 MHz。作圖、做影片都是連續跑好幾秒以上，所以我們認為連續滿載的數字比較接近實際使用。我們作圖 1.51 倍，另一張 4060 Ti 16GB 公開的 ComfyUI 結果是 1.57 倍，很接近。（我們還沒在這張卡上用短跑方式測過。）

## 解鎖紀錄重點

這片主機板開機時，顯卡上游的 PCI 橋沒有開 Bus Master（`0x0003`），要靠 nv-uefi-unlocker 的 `BridgeMaster` 自動改成 `0x0007`（做完會還原），不然 Booter 會失敗（`MAILBOX0=0x89`）。成功時 `MAILBOX0=0x67b00001`、`SS0=0x88888888 SS1=0x8`，重置顯卡（FLR）後仍保留，接著自動進 Windows。

## 每次開機自動解鎖（不用隨身碟）

[`scripts/install.ps1`](scripts/install.ps1) 會做這些事：

1. 從**資料碟**（不是系統碟）縮出 300 MB，建一個 FAT32 分割區 `GPUUNLOCK`。
2. 放入 `EFI\BOOT\BOOTX64.EFI` 和本機產生的 `*.bin`，逐一核對 SHA-256。
3. 放 `i_know_what_i_am_doing.txt`：開機時 5 秒倒數後自動解鎖（按任意鍵可跳過這次）。
4. 用 `bcdedit` 建「GPU Unlock」開機項目，排在 `{fwbootmgr}` 第一。
5. 拿掉這個分割區的磁碟代號，避免被誤刪。
6. 登入 Windows 後 [`scripts/check_unlock.py`](scripts/check_unlock.py) 自動量一次速度並跳通知（≥58 已解鎖、≤52 沒解鎖）。

[`scripts/uninstall.ps1`](scripts/uninstall.ps1) 可以全部還原。

### ⚠️ MSI 主機板的坑

裝好後前幾次重開都**沒解鎖**（46），但 `bcdedit` 明明顯示 GPU Unlock 排第一；用 F11 手動選它又能解鎖（68.6）。分割區裡的解鎖紀錄在失敗那幾次**完全沒有新紀錄**，代表程式根本沒被啟動。

原因：**這片 MSI B550 照 BIOS 自己的開機順序走，不理 Windows 寫的 `{fwbootmgr}` 順序。** 解法：開機按 Delete → F7 進階模式 → Settings → Boot → **Boot Option #1 設成 GPU Unlock**（可能顯示成那顆硬碟的名稱）→ F10 存檔。之後登入檢查量到 69.6，開機自動解鎖成功。更新 BIOS 或清 CMOS 後要重設一次。

## 其他踩過的坑

- **編譯要在純英文路徑**，中文資料夾會編譯失敗。
- **隨身碟的 FAT 曾經壞掉**（資料夾名稱變亂碼），格式化重放後正常。每次放完檔案跑一次 `chkdsk`。
- **先演練再解鎖**：不放 `v67-ad102-four-plm.bin` 就只做檢查、不寫顯卡。
- 沒有內顯的電腦，解鎖時會黑畫面幾秒，屬正常。

## 這個 repo 沒有放的東西

NVIDIA 韌體、產生出來的 `*.bin`、編譯好的 `BOOTX64.EFI`、顯卡 ROM 都是 NVIDIA 的版權資料，**不放**。請用 nv-uefi-unlocker 的 `make-usbroot.ps1` 自己產生，它會下載官方原始檔並核對 SHA-256。

## 免責聲明

這是**單一台電腦**的實測紀錄。過程會寫入顯卡暫存器、更改開機設定，可能影響保固，也可能需要斷電重開或進 BIOS 修復。程式是照這台電腦寫的（`D:`、`D:\ComfyUI` 等路徑寫死，`install.ps1` 要從 `..\參考程式碼\nv-usbroot` 讀取自己產生的檔案），要套用前請先讀懂。本文與程式照現狀提供，不提供任何保證。**風險自負。**

我們與 NVIDIA、MSI 沒有任何關係。NVIDIA、GeForce、RTX、MSI 是各自公司的商標。

開不了機時：開機連按 F11，選 **Windows Boot Manager** 即可照常進 Windows。

## 致謝

[nv-uefi-unlocker](https://github.com/physicsdolphin/nv-uefi-unlocker)、[gpu-unlock](https://github.com/Zagitta/gpu-unlock)、[gpu-unlock-ada](https://github.com/JustAResearcher/gpu-unlock-ada)、[Windows-GPU-UNLOCK](https://github.com/impacifist/Windows-GPU-UNLOCK)。
