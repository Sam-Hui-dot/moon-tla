import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPECS_DIR = ROOT / "demo" / "specs"
CACHE_DIR = ROOT / "demo" / ".tlc-cache"
OUT_DIR = ROOT / "demo" / "out"

TLC_URL = "https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar"

SPEC_ORDER = [
    "DieHard",
    "TwoPhase",
    "TwoPhaseBuggy",
    "MutexPeterson",
    "MutexBuggy",
    "RaftElection",
    "RaftSplitBrainBuggy",
    "BankTransfer",
    "BankTransferBuggy",
    "DiningPhilosophers",
    "TokenRing",
]


def ensure_tlc_jar(custom_path: str | None) -> Path:
    if custom_path:
        p = Path(custom_path)
        if not p.exists():
            raise FileNotFoundError(f"TLC jar not found: {p}")
        return p
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    jar = CACHE_DIR / "tla2tools.jar"
    if jar.exists() and jar.stat().st_size > 1_000_000:
        return jar
    print(f"Downloading official TLC v1.7.4 from {TLC_URL} ...")
    for attempt in range(1, 4):
        try:
            urllib.request.urlretrieve(TLC_URL, jar)
            if jar.stat().st_size > 1_000_000:
                print(f"Downloaded {jar} ({jar.stat().st_size:,} bytes)")
                return jar
        except Exception as exc:
            print(f"Attempt {attempt} failed: {exc}", file=sys.stderr)
            if attempt == 3:
                raise
            time.sleep(2)
    return jar


def find_moon_tla_bin() -> Path:
    build_dir = ROOT / "_build" / "native" / "release" / "build" / "cmd" / "main"
    for cand in (build_dir / "main.exe", build_dir / "main"):
        if cand.exists():
            return cand
    print("Building native release binary for moon-tla ...")
    subprocess.run(
        ["moon", "build", "--target", "native", "--release", "--deny-warn", "cmd/main"],
        cwd=ROOT,
        check=True,
    )
    for cand in (build_dir / "main.exe", build_dir / "main"):
        if cand.exists():
            return cand
    raise FileNotFoundError(f"moon-tla native binary not found in {build_dir}")


def run_moon_tla(bin_path: Path, tla: Path, cfg: Path) -> tuple[dict, float]:
    t0 = time.perf_counter()
    proc = subprocess.run(
        [
            str(bin_path),
            "check",
            str(tla),
            "--cfg",
            str(cfg),
            "--format",
            "json",
            "--exit-zero",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    return json.loads(proc.stdout), elapsed_ms


def normalize_moon_verdict(res: dict) -> str:
    txt = res["status_text"]
    if txt.startswith("No errors"):
        return "OK"
    m = re.match(r"Invariant (\S+) is violated", txt)
    if m:
        return f"INVARIANT:{m.group(1)}"
    if txt.startswith("Deadlock"):
        return "DEADLOCK"
    m2 = re.match(r"Temporal property (\S+) is violated", txt)
    if m2:
        return f"LIVENESS:{m2.group(1)}"
    return txt


def run_java_tlc(jar: Path, tla: Path, cfg: Path) -> tuple[dict, float]:
    with tempfile.TemporaryDirectory(prefix="tlc_meta_") as meta_dir:
        cmd = [
            "java",
            "-XX:+UseParallelGC",
            "-cp",
            str(jar),
            "tlc2.TLC",
            "-workers",
            "1",
            "-cleanup",
            "-nowarning",
            "-metadir",
            meta_dir,
            "-config",
            str(cfg),
            str(tla),
        ]
        t0 = time.perf_counter()
        proc = subprocess.run(
            cmd,
            cwd=SPECS_DIR,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        out = proc.stdout + "\n" + proc.stderr

    verdict = "UNKNOWN"
    if "Model checking completed. No error has been found." in out:
        verdict = "OK"
    else:
        m_inv = re.search(r"Error:\s+Invariant\s+(\S+)\s+is violated\.", out)
        if m_inv:
            verdict = f"INVARIANT:{m_inv.group(1)}"
        elif "Error: Deadlock reached." in out:
            verdict = "DEADLOCK"
        elif "Temporal properties were violated" in out:
            verdict = "LIVENESS"
        else:
            raise RuntimeError(f"Unexpected Java TLC output for {tla.name}:\n{out}")

    m_distinct = re.search(r"(\d+)\s+distinct states found", out)
    m_gen = re.search(r"(\d+)\s+states generated", out)
    m_depth = re.search(r"The depth of the complete state graph search is (\d+)\.", out)
    state_headers = re.findall(r"^State\s+(\d+):", out, flags=re.MULTILINE)

    return {
        "verdict": verdict,
        "distinct_states": int(m_distinct.group(1)) if m_distinct else -1,
        "states_generated": int(m_gen.group(1)) if m_gen else -1,
        "diameter": int(m_depth.group(1)) if m_depth else -1,
        "trace_len": len(state_headers),
        "raw": out,
    }, elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(description="Differential oracle against official Java TLC v1.7.4")
    parser.add_argument("--tlc-jar", default=None, help="Path to pre-downloaded tla2tools.jar")
    args = parser.parse_args()

    if shutil.which("java") is None:
        raise RuntimeError("Java runtime (`java`) not found in PATH")

    jar = ensure_tlc_jar(args.tlc_jar)
    bin_path = find_moon_tla_bin()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    total_moon_ms = 0.0
    total_tlc_ms = 0.0

    for name in SPEC_ORDER:
        tla = SPECS_DIR / f"{name}.tla"
        cfg = SPECS_DIR / f"{name}.cfg"

        m_res, m_ms = run_moon_tla(bin_path, tla, cfg)
        t_res, t_ms = run_java_tlc(jar, tla, cfg)

        m_verdict = normalize_moon_verdict(m_res)
        t_verdict = t_res["verdict"]

        if m_verdict != t_verdict:
            raise AssertionError(
                f"[{name}] verdict mismatch: moon-tla={m_verdict} vs TLC={t_verdict}"
            )

        m_distinct = m_res["distinct_states"]
        m_diam = m_res["diameter"]
        m_trace = len(m_res["trace"])
        t_distinct = t_res["distinct_states"]
        t_diam = t_res["diameter"]
        t_trace = t_res["trace_len"]

        if m_verdict == "OK":
            if m_distinct != t_distinct:
                raise AssertionError(
                    f"[{name}] distinct_states mismatch: moon-tla={m_distinct} vs TLC={t_distinct}"
                )
            if t_diam >= 0 and m_diam != t_diam:
                raise AssertionError(
                    f"[{name}] diameter mismatch: moon-tla={m_diam} vs TLC={t_diam}"
                )
            parity_note = f"exact states={m_distinct}, diam={m_diam}"
        else:
            if m_trace != t_trace:
                raise AssertionError(
                    f"[{name}] shortest trace length mismatch: moon-tla={m_trace} vs TLC={t_trace}"
                )
            parity_note = f"exact shortest trace={m_trace} states"

        total_moon_ms += m_ms
        total_tlc_ms += t_ms
        speedup = t_ms / m_ms if m_ms > 0 else 0.0
        rows.append(
            {
                "name": name,
                "verdict": m_verdict,
                "moon_distinct": m_distinct,
                "tlc_distinct": t_distinct,
                "moon_diam": m_diam,
                "tlc_diam": t_diam,
                "trace_len": m_trace,
                "moon_ms": m_ms,
                "tlc_ms": t_ms,
                "speedup": speedup,
                "parity_note": parity_note,
            }
        )
        print(
            f"ORACLE_OK {name:20s} verdict={m_verdict:26s} {parity_note:32s} "
            f"moon={m_ms:6.1f}ms vs TLC={t_ms:7.1f}ms ({speedup:5.1f}x)"
        )

    # Export showcase SVGs for RaftSplitBrainBuggy
    for fmt, fname in [("trace-svg", "raft-splitbrain-trace.svg"), ("graph-svg", "raft-splitbrain-graph.svg")]:
        subprocess.run(
            [
                str(bin_path),
                "check",
                str(SPECS_DIR / "RaftSplitBrainBuggy.tla"),
                "--cfg",
                str(SPECS_DIR / "RaftSplitBrainBuggy.cfg"),
                "--format",
                fmt,
                "--out",
                str(OUT_DIR / fname),
                "--exit-zero",
            ],
            cwd=ROOT,
            check=True,
        )

    agg_speedup = total_tlc_ms / total_moon_ms if total_moon_ms > 0 else 0.0
    md_lines = [
        "## Official Java TLC v1.7.4 Differential Oracle Summary",
        "",
        f"Verified **{len(rows)}/{len(rows)}** unmodified `.tla` + `.cfg` distributed protocol specifications against official `tlaplus/tlaplus v1.7.4` (`tla2tools.jar`, single-worker deterministic BFS).",
        "",
        "| Protocol | Verdict (Both) | Distinct States (moon / TLC) | Diameter (moon / TLC) | Shortest Trace | Native `moon-tla` | JVM `TLC v1.7.4` | Speedup |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for r in rows:
        diam_str = f"{r['moon_diam']} / {r['tlc_diam']}" if r["verdict"] == "OK" else "—"
        trace_str = "—" if r["verdict"] == "OK" else f"{r['trace_len']} states"
        md_lines.append(
            f"| `{r['name']}` | `{r['verdict']}` | {r['moon_distinct']} / {r['tlc_distinct']} | {diam_str} | {trace_str} | {r['moon_ms']:.1f} ms | {r['tlc_ms']:.1f} ms | **{r['speedup']:.1f}x** |"
        )
    md_lines.append(
        f"| **Total ({len(rows)} specs)** | **11/11 EXACT** | — | — | — | **{total_moon_ms:.1f} ms** | **{total_tlc_ms:.1f} ms** | **{agg_speedup:.1f}x** |"
    )
    md_lines.append("")

    summary_path = OUT_DIR / "tlc-oracle-summary.md"
    summary_path.write_text("\n".join(md_lines), encoding="utf-8")
    (OUT_DIR / "tlc-oracle-results.json").write_text(
        json.dumps(rows, indent=2), encoding="utf-8"
    )
    print(f"\nALL {len(rows)}/{len(rows)} SPECS MATCHED OFFICIAL JAVA TLC v1.7.4 EXACTLY!")
    print(f"Aggregate: Native moon-tla {total_moon_ms:.1f} ms vs JVM TLC {total_tlc_ms:.1f} ms ({agg_speedup:.1f}x faster)")
    print(f"Summary written to {summary_path}")


if __name__ == "__main__":
    main()
