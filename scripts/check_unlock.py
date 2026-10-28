"""登入後檢查顯卡有沒有解鎖：量 FP16（FP32 累加）矩陣乘法速度，跳 Windows 通知。

判斷（4060 Ti 16GB、165 W）：解鎖約 67 TFLOPS、沒解鎖約 46。
  >= 58 → 已解鎖；<= 52 → 沒解鎖；中間 → 不確定（顯卡可能正在忙）
用 ComfyUI 內建 Python 跑：D:\\ComfyUI\\python_embeded\\pythonw.exe -I check_unlock.py [--wait 秒數]
結果另外記在同資料夾的 檢查紀錄.txt（不上傳）。
"""
import os, subprocess, sys, time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, "檢查紀錄.txt")
N = 8192
UNLOCKED_MIN = 58.0
LOCKED_MAX = 52.0
OK_TOAST_LIMIT = 2  # 開機自動檢查的 ✅ 通知只顯示前 2 次


def toast(title, body):
    # Windows PowerShell 5.1 內建 WinRT 通知，借用 PowerShell 的 AppId 才會顯示
    t = title.replace("'", "''")
    b = body.replace("'", "''")
    ps = f"""
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null
$x = New-Object Windows.Data.Xml.Dom.XmlDocument
$x.LoadXml('<toast duration="long"><visual><binding template="ToastGeneric"><text></text><text></text></binding></visual></toast>')
$n = $x.GetElementsByTagName('text')
$n.Item(0).AppendChild($x.CreateTextNode('{t}')) > $null
$n.Item(1).AppendChild($x.CreateTextNode('{b}')) > $null
$app = '{{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}}\\WindowsPowerShell\\v1.0\\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))
"""
    subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", ps],
                   creationflags=0x08000000)  # CREATE_NO_WINDOW


def measure():
    import torch
    torch.backends.cuda.matmul.allow_tf32 = False
    if hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation"):
        torch.backends.cuda.matmul.allow_fp16_accumulation = False
    a = torch.randn(N, N, device="cuda", dtype=torch.float16)
    b = torch.randn(N, N, device="cuda", dtype=torch.float16)
    c = torch.empty(N, N, device="cuda", dtype=torch.float16)
    # 先暖機約 1 秒，讓顯卡從省電狀態拉到全速
    t0 = time.perf_counter()
    while time.perf_counter() - t0 < 1.0:
        torch.matmul(a, b, out=c)
        torch.cuda.synchronize()
    best = 0.0
    for _ in range(3):
        s, e = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
        s.record()
        for _ in range(20):
            torch.matmul(a, b, out=c)
        e.record()
        torch.cuda.synchronize()
        best = max(best, 2 * N ** 3 * 20 / (s.elapsed_time(e) / 1000) / 1e12)
    name = torch.cuda.get_device_name(0)
    return best, name


def auto_ok_count():
    """檢查紀錄裡「開機自動」且「已解鎖」的次數。"""
    if not os.path.exists(LOG):
        return 0
    with open(LOG, encoding="utf-8-sig") as f:
        return sum(1 for l in f if "已解鎖" in l and "開機自動" in l)


def main():
    wait = 0
    if "--wait" in sys.argv:
        wait = int(sys.argv[sys.argv.index("--wait") + 1])
    time.sleep(wait)  # 開機登入後先等系統穩定
    try:
        tf, name = measure()
    except Exception as ex:  # noqa: BLE001
        msg = f"沒辦法量測：{ex}"
        toast("⚠️ 顯卡解鎖檢查失敗", msg)
        line = f"{datetime.now():%Y-%m-%d %H:%M:%S}  錯誤  {msg}"
    else:
        if tf >= UNLOCKED_MIN:
            title, body, tag = "✅ 顯卡已解鎖（全速）", f"FP16 {tf:.1f} TFLOPS（解鎖約 67、沒解鎖約 46）", "已解鎖"
        elif tf <= LOCKED_MAX:
            title, body, tag = "⚠️ 這次沒有解鎖（半速）", f"FP16 {tf:.1f} TFLOPS。開機順序可能被改掉（檢查 BIOS Boot Option #1），或解鎖失敗", "沒解鎖"
        else:
            title, body, tag = "❓ 顯卡解鎖不確定", f"FP16 {tf:.1f} TFLOPS，顯卡可能正在忙。關掉 AI 程式後點「檢查顯卡解鎖」再測一次", "不確定"
        # 開機自動檢查（有 --wait）時，✅ 只通知前 OK_TOAST_LIMIT 次；⚠️／❓ 和手動檢查每次都通知
        if not (wait and tag == "已解鎖" and auto_ok_count() >= OK_TOAST_LIMIT):
            toast(title, body)
        line = f"{datetime.now():%Y-%m-%d %H:%M:%S}  {tag}  {tf:.1f} TFLOPS  {name}"
        if wait:
            line += "  開機自動"
    # 新檔才寫 BOM（記事本才認得 UTF-8），之後用一般 utf-8 往下加
    enc = "utf-8" if os.path.exists(LOG) else "utf-8-sig"
    with open(LOG, "a", encoding=enc) as f:
        f.write(line + "\n")
    print(line)


if __name__ == "__main__":
    main()
