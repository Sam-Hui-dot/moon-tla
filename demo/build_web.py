import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SPECS_DIR = ROOT / "demo" / "specs"

PRESET_META = [
    {
        "id": "RaftSplitBrainBuggy",
        "title": "Raft Leader Election (Split-Brain Bug)",
        "tag": "Buggy",
        "pair": "RaftElection",
        "check_deadlock": True,
        "description": "1-line defect injected in Vote: a node forgets to check votedFor[n] = \"none\", allowing two candidates to win majorities in the same term and violating ElectionSafety.",
    },
    {
        "id": "RaftElection",
        "title": "Raft Leader Election (Safe)",
        "tag": "Safe",
        "pair": "RaftSplitBrainBuggy",
        "check_deadlock": True,
        "description": "3-node Raft election protocol with term advancement, single-vote-per-term rule, and majority quorum check. Exhaustively verifies ElectionSafety across all reachable states.",
    },
    {
        "id": "TwoPhaseBuggy",
        "title": "Two-Phase Commit (Consistency Bug)",
        "tag": "Buggy",
        "pair": "TwoPhase",
        "check_deadlock": True,
        "description": "1-line defect injected in TMCommit: transaction manager commits as soon as any RM prepares instead of requiring all RMs, allowing one RM to commit while another aborts.",
    },
    {
        "id": "TwoPhase",
        "title": "Two-Phase Commit (Safe)",
        "tag": "Safe",
        "pair": "TwoPhaseBuggy",
        "check_deadlock": True,
        "description": "Classic Gray/Lamport Two-Phase Commit over 3 Resource Managers (r1, r2, r3). Verifies TCConsistent (no RM commits while another aborts) across the complete state graph.",
    },
    {
        "id": "MutexBuggy",
        "title": "Concurrent Mutual Exclusion (Race Bug)",
        "tag": "Buggy",
        "pair": "MutexPeterson",
        "check_deadlock": True,
        "description": "Two-process lock missing Peterson's tie-breaker turn variable: both processes observe the other's flag as FALSE and enter the critical section simultaneously.",
    },
    {
        "id": "MutexPeterson",
        "title": "Peterson's Mutual Exclusion (Safe)",
        "tag": "Safe",
        "pair": "MutexBuggy",
        "check_deadlock": True,
        "description": "Peterson's 2-process mutual exclusion algorithm with flag array and turn tie-breaker. Verifies MutualExclusion across all interleavings.",
    },
    {
        "id": "BankTransferBuggy",
        "title": "Concurrent Bank Transfer (TOCTOU Race)",
        "tag": "Buggy",
        "pair": "BankTransfer",
        "check_deadlock": False,
        "description": "Two concurrent transfers read balance before deducting (check-then-act race), overdrafting the account and violating NoOverdraft.",
    },
    {
        "id": "BankTransfer",
        "title": "Atomic Bank Transfer (Safe)",
        "tag": "Safe",
        "pair": "BankTransferBuggy",
        "check_deadlock": False,
        "description": "Atomic debit-and-credit transfers preserving total balance conservation (TotalConserved) and non-negative balances (NoOverdraft).",
    },
    {
        "id": "DiningPhilosophers",
        "title": "Dining Philosophers (Circular Deadlock)",
        "tag": "Deadlock",
        "pair": None,
        "check_deadlock": True,
        "description": "3 philosophers each pick up their left fork before requesting their right fork, producing the canonical 3-step circular wait deadlock.",
    },
    {
        "id": "DieHard",
        "title": "Die Hard 3/5-Gallon Jugs (Shortest Solution)",
        "tag": "Puzzle",
        "pair": None,
        "check_deadlock": True,
        "description": "Lamport's classic TLA+ puzzle: violating NotSolved (big # 4) synthesizes the shortest 6-step water pouring sequence via BFS.",
    },
    {
        "id": "TokenRing",
        "title": "Distributed Token Ring (Safe)",
        "tag": "Safe",
        "pair": None,
        "check_deadlock": True,
        "description": "4-node distributed token ring verifying single-token exclusivity (SingleToken) and ring circulation across all reachable states.",
    },
    {
        "id": "PaxosConsensus",
        "title": "Synod Paxos Consensus (Safe, 3,921 states)",
        "tag": "Safe",
        "pair": None,
        "check_deadlock": False,
        "description": "Lamport Single-Decree Synod Paxos over 3 Acceptors, 2 Values, and 2 Ballots. Verifies Agreement (at most one chosen value) across 3,921 distinct states.",
    },
    {
        "id": "TwoPhaseSym",
        "title": "Two-Phase Commit (SYMMETRY Permutations)",
        "tag": "Symmetry",
        "pair": "TwoPhase",
        "check_deadlock": True,
        "description": "3-RM Two-Phase Commit with SYMMETRY Permutations(RM), compressing 288 states down to 80 canonical quotient states (3.6x reduction, exact TLC match).",
    },
    {
        "id": "PetersonLiveness",
        "title": "Peterson's Lock (Per-Action WF Liveness)",
        "tag": "Liveness",
        "pair": "StarvationBuggy",
        "check_deadlock": True,
        "description": "Peterson's mutual exclusion with quantified per-process weak fairness (\\A i \\in Procs : WF_vars(ProcStep(i))). Proves StarvationFree ((pc[i] = \"wait\") ~> (pc[i] = \"cs\")).",
    },
    {
        "id": "StarvationBuggy",
        "title": "Biased Lock (Fair Starvation Lasso Bug)",
        "tag": "Liveness Bug",
        "pair": "PetersonLiveness",
        "check_deadlock": True,
        "description": "Biased 2-process lock missing Peterson's turn tie-breaker. Even under per-process weak fairness, Emerson-Lei SCC pruning catches the exact fair starvation Lasso cycle.",
    },
    {
        "id": "TokenRingLiveness",
        "title": "Token Ring (Infinitely-Often []<> Liveness)",
        "tag": "Liveness",
        "pair": "TokenRing",
        "check_deadlock": True,
        "description": "4-node fair token ring verifying \\A n \\in Nodes : []<>(holder = n) under WF_holder(Next).",
    },
]


def main() -> None:
    cmd = ["moon", "build", "--target", "js", "--release", "--deny-warn", "web"]
    print("Running:", " ".join(cmd))
    subprocess.run(cmd, cwd=ROOT, check=True)

    built_js = ROOT / "_build" / "js" / "release" / "build" / "web" / "web.js"
    if not built_js.exists():
        raise FileNotFoundError(f"Expected JS build artifact not found: {built_js}")

    DOCS.mkdir(parents=True, exist_ok=True)
    target_js = DOCS / "moon-tla.js"
    shutil.copy2(built_js, target_js)
    print(f"Copied {built_js} -> {target_js} ({target_js.stat().st_size} bytes)")

    samples = []
    for meta in PRESET_META:
        tla_path = SPECS_DIR / f"{meta['id']}.tla"
        cfg_path = SPECS_DIR / f"{meta['id']}.cfg"
        entry = dict(meta)
        entry["tla"] = tla_path.read_text(encoding="utf-8")
        entry["cfg"] = cfg_path.read_text(encoding="utf-8")
        samples.append(entry)

    samples_js = DOCS / "samples.js"
    samples_js.write_text(
        "globalThis.MOON_TLA_SAMPLES = " + json.dumps(samples, ensure_ascii=False) + ";\n",
        encoding="utf-8",
    )
    print(f"Wrote {samples_js} ({samples_js.stat().st_size} bytes, {len(samples)} presets)")

    smoke = (
        "require('./docs/moon-tla.js');\n"
        "require('./docs/samples.js');\n"
        "const M = globalThis.MoonTla;\n"
        "for (const s of globalThis.MOON_TLA_SAMPLES) {\n"
        "  const res = M.checkSpec(s.tla, s.cfg, { maxStates: 100000, maxGraphNodes: 80 });\n"
        "  if (!res.ok) throw new Error('web checkSpec failed for ' + s.id + ': ' + res.error);\n"
        "  if (!res.trace_svg.includes('moon-tla-trace')) throw new Error('missing trace svg for ' + s.id);\n"
        "  if (!res.graph_svg.includes('moon-tla-graph')) throw new Error('missing graph svg for ' + s.id);\n"
        "  console.log('WEB_SMOKE_OK', s.id, 'status=' + res.result.status_text, 'distinct=' + res.result.distinct_states, 'diam=' + res.result.diameter, 'trace=' + res.result.trace.length);\n"
        "}\n"
    )
    subprocess.run(["node", "-e", smoke], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
