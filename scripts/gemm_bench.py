"""第一層對照組：純矩陣乘法速度（TFLOPS）。

會被解鎖影響的：fp16、bf16（FP32 累加）、tf32
不該變的（檢查用）：fp32、fp16 累加 fp16
用法：python gemm_bench.py <標籤，例如 破解前> [矩陣大小，預設 8192]
結果存到 ../對照組/第一層_<標籤>_<時間>.json
"""
import json, os, statistics, subprocess, sys, time
from datetime import datetime

import torch

label = sys.argv[1] if len(sys.argv) > 1 else "未標記"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 8192
REPS = 3          # 每種模式量 3 次取中間值
SECONDS = 4.0     # 每次量大約幾秒

def gpu_state():
    q = "clocks.sm,clocks.mem,temperature.gpu,power.draw,power.limit,pstate"
    out = subprocess.run(["nvidia-smi", f"--query-gpu={q}", "--format=csv,noheader,nounits"],
                         capture_output=True, text=True).stdout.strip()
    return dict(zip(q.split(","), [v.strip() for v in out.split(",")]))

def bench(dtype, tf32=False, fp16_acc=False):
    torch.backends.cuda.matmul.allow_tf32 = tf32
    if hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation"):
        torch.backends.cuda.matmul.allow_fp16_accumulation = fp16_acc
    a = torch.randn(N, N, device="cuda", dtype=dtype)
    b = torch.randn(N, N, device="cuda", dtype=dtype)
    c = torch.empty(N, N, device="cuda", dtype=dtype)
    for _ in range(5):
        torch.matmul(a, b, out=c)
    torch.cuda.synchronize()
    # 先估一次要跑幾輪才會大約 SECONDS 秒
    t = time.perf_counter(); torch.matmul(a, b, out=c); torch.cuda.synchronize()
    iters = max(5, int(SECONDS / max(time.perf_counter() - t, 1e-4)))
    results, states = [], []
    for _ in range(REPS):
        s, e = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
        s.record()
        for _ in range(iters):
            torch.matmul(a, b, out=c)
        e.record(); torch.cuda.synchronize()
        sec = s.elapsed_time(e) / 1000
        results.append(2 * N ** 3 * iters / sec / 1e12)
        states.append(gpu_state())
    del a, b, c
    torch.cuda.empty_cache()
    return {"tflops_runs": [round(x, 2) for x in results],
            "tflops_median": round(statistics.median(results), 2),
            "iters": iters, "gpu_state_after_each_run": states}

MODES = [
    ("fp16_fp32累加", dict(dtype=torch.float16)),
    ("bf16_fp32累加", dict(dtype=torch.bfloat16)),
    ("tf32", dict(dtype=torch.float32, tf32=True)),
    ("fp32（檢查用，不該變）", dict(dtype=torch.float32)),
    ("fp16_fp16累加（檢查用，不該變）", dict(dtype=torch.float16, fp16_acc=True)),
]

report = {
    "標籤": label, "時間": datetime.now().isoformat(timespec="seconds"), "矩陣大小": N,
    "顯卡": torch.cuda.get_device_name(0), "torch": torch.__version__, "cuda": torch.version.cuda,
    "驅動": subprocess.run(["nvidia-smi", "--query-gpu=driver_version,vbios_version", "--format=csv,noheader"],
                           capture_output=True, text=True).stdout.strip(),
    "開始時顯卡狀態": gpu_state(), "結果": {},
}
for name, kw in MODES:
    r = bench(**kw)
    report["結果"][name] = r
    print(f"{name:<28} {r['tflops_median']:>8.2f} TFLOPS   {r['tflops_runs']}", flush=True)

out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "對照組")
os.makedirs(out_dir, exist_ok=True)
path = os.path.join(out_dir, f"第一層_{label}_{datetime.now():%Y%m%d_%H%M}.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print("saved", os.path.abspath(path))
