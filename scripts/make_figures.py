#!/usr/bin/env python3
"""
Draws the plots for the report.
  waveform_systolic_N4.png - waveform of one 4x4 multiply, drawn straight from
                             the simulation's .vcd file (so it's real data)
  dataflow_skew.png        - which a/b values sit in which PE, cycle by cycle
  latency_vs_n.png         - cycles needed: systolic vs sequential
  resources_vs_n.png       - how LUTs / FFs / DSPs grow with N
Everything is saved to report/figures/.
"""
import json
import os
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIG = os.path.join(ROOT, "report", "figures")
os.makedirs(FIG, exist_ok=True)

BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
INK, INK2, GRID = "#1f1f1e", "#5f5e5a", "#e4e3de"
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 9, "axes.edgecolor": INK2,
    "axes.labelcolor": INK, "xtick.color": INK2, "ytick.color": INK2,
    "axes.spines.top": False, "axes.spines.right": False,
})


# ---- reading the VCD waveform file ----
# A VCD file is just text: first it lists the signals and gives each a short
# id, then it lists "#time" lines followed by value changes. We only keep the
# signals we asked for.
def parse_vcd(path, wanted):
    """Returns {signal name: [(time, value), ...]}. x/z values become None."""
    ids, scope, out = {}, [], {w: [] for w in wanted}
    t = 0
    with open(path) as f:
        in_defs = True
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if in_defs:
                if tok[0] == "$scope":
                    scope.append(tok[2])
                elif tok[0] == "$upscope":
                    scope.pop()
                elif tok[0] == "$var":
                    name = ".".join(scope + [tok[4]])
                    if name in out:
                        ids.setdefault(tok[3], []).append(name)
                elif tok[0] == "$enddefinitions":
                    in_defs = False
                continue
            c = line[0]
            if c == "#":
                t = int(line[1:])
            elif c in "01xzXZ" and len(tok) == 1:
                sid = line[1:].strip()
                for n in ids.get(sid, []):
                    out[n].append((t, int(c) if c in "01" else None))
            elif c == "b":
                val, sid = tok[0][1:], tok[1]
                v = None if re.search("[xzXZ]", val) else int(val, 2)
                for n in ids.get(sid, []):
                    out[n].append((t, v))
    return out


# what was this signal's value at a given time?
def value_at(trace, time):
    v = None
    for tt, vv in trace:
        if tt > time:
            break
        v = vv
    return v


# raw bits -> signed number (two's complement)
def sgn(v, bits):
    if v is None:
        return None
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def waveform():
    vcd = os.path.join(ROOT, "sim", "waves", "tb_systolic_N4.vcd")
    pe = lambda i, j: "tb_matmul.dut.u_array.g_row[%d].g_col[%d].u_pe.acc" % (i, j)
    sigs = ["tb_matmul.clk", "tb_matmul.start", "tb_matmul.dut.u_ctrl.state",
            "tb_matmul.dut.u_ctrl.t", "tb_matmul.dut.a_left", "tb_matmul.dut.b_top",
            pe(0, 0), pe(1, 1), pe(3, 3), "tb_matmul.dut.u_obuf.capture", "tb_matmul.done"]
    tr = parse_vcd(vcd, sigs)
    t_start = next(t for t, v in tr["tb_matmul.start"] if v == 1)
    t_done = next(t for t, v in tr["tb_matmul.done"] if t > t_start and v == 1)
    period = 10000  # 10 ns in ps
    t0 = t_start - 2 * period + 5000 - 1000
    ncyc = (t_done - t0) // period + 3
    # sample each cycle a bit after the rising edge, once things have settled
    samples = [t0 + period * k + 6000 for k in range(ncyc)]

    state_names = {0: "IDLE", 1: "CLEAR", 2: "COMPUTE", 3: "CAPT", 4: "DONE"}
    rows = [
        ("clk", "clk"), ("start", "bit"), ("state", "state"), ("step t", "int"),
        ("a_left[0] (row 0)", ("lane", "tb_matmul.dut.a_left", 0)),
        ("a_left[3] (row 3)", ("lane", "tb_matmul.dut.a_left", 3)),
        ("b_top[0] (col 0)", ("lane", "tb_matmul.dut.b_top", 0)),
        ("b_top[3] (col 3)", ("lane", "tb_matmul.dut.b_top", 3)),
        ("PE(0,0).acc", ("acc", pe(0, 0))), ("PE(1,1).acc", ("acc", pe(1, 1))),
        ("PE(3,3).acc", ("acc", pe(3, 3))), ("capture", "bit"), ("done", "bit"),
    ]
    keymap = {"clk": "tb_matmul.clk", "start": "tb_matmul.start",
              "state": "tb_matmul.dut.u_ctrl.state", "step t": "tb_matmul.dut.u_ctrl.t",
              "capture": "tb_matmul.dut.u_obuf.capture", "done": "tb_matmul.done"}

    fig, ax = plt.subplots(figsize=(10, 5.2))
    H = 0.6
    for r, (label, kind) in enumerate(rows):
        y = len(rows) - 1 - r
        ax.text(-0.3, y + H / 2, label, ha="right", va="center", fontsize=8, color=INK)
        if kind == "clk":
            xs, ys = [], []
            for k in range(ncyc):
                xs += [k, k, k + 0.5, k + 0.5]
                ys += [y, y + H, y + H, y]
            ax.plot(xs, ys, color=INK2, lw=1)
            continue
        if kind == "bit":
            vals = [value_at(tr[keymap[label]], s) or 0 for s in samples]
            xs, ys = [], []
            for k, v in enumerate(vals):
                xs += [k, k + 1]
                ys += [y + v * H, y + v * H]
            ax.plot(xs, ys, color=BLUE, lw=1.6)
            continue
        vals = []
        for s in samples:
            if kind == "state":
                vals.append(state_names.get(value_at(tr[keymap[label]], s), "?"))
            elif kind == "int":
                vals.append(str(value_at(tr[keymap[label]], s)))
            elif kind[0] == "lane":
                v = value_at(tr[kind[1]], s)
                vals.append(str(sgn((v >> (8 * kind[2])) & 0xFF, 8)))
            else:
                vals.append(str(sgn(value_at(tr[kind[1]], s), 20)))
        k = 0
        while k < len(vals):
            e = k
            while e + 1 < len(vals) and vals[e + 1] == vals[k]:
                e += 1
            x0, x1 = k + 0.04, e + 1 - 0.04
            busy = vals[k] not in ("0", "IDLE")
            ax.fill([x0 + .12, x1 - .12, x1, x1 - .12, x0 + .12, x0],
                    [y, y, y + H / 2, y + H, y + H, y + H / 2],
                    color="#dbe8f8" if busy else "#f1f0ec", ec=BLUE if busy else INK2, lw=0.8)
            txt = vals[k]
            if (x1 - x0) * 5.2 >= len(txt) or (x1 - x0) > 0.9:
                ax.text((x0 + x1) / 2, y + H / 2, txt, ha="center", va="center",
                        fontsize=6.5 if len(txt) > 3 else 7.5, color=INK)
            k = e + 1
    for k in range(ncyc + 1):
        ax.axvline(k, color=GRID, lw=0.5, zorder=0)
        if k < ncyc:
            ax.text(k + 0.5, len(rows) + 0.05, str(k), ha="center", fontsize=6.5, color=INK2)
    ax.text(ncyc / 2, len(rows) + 0.55, "clock cycle (10 ns)", ha="center", fontsize=8, color=INK2)
    ax.set_xlim(-4.2, ncyc)
    ax.set_ylim(-0.4, len(rows) + 0.9)
    ax.axis("off")
    ax.set_title("4x4 systolic array - one matrix multiplication (test 0: I x B)",
                 loc="left", fontsize=10, color=INK)
    fig.tight_layout()
    fig.savefig(os.path.join(FIG, "waveform_systolic_N4.png"), dpi=220)
    plt.close(fig)


# ---- the skew picture ----
# No simulation needed here: a[i][k] and b[k][j] meet in PE(i,j) at cycle
# i+j+k+1, so for each cycle we work out which k each PE is on.
def dataflow(n=3, cycles=(1, 2, 3, 4, 5, 7)):
    fig, axes = plt.subplots(1, len(cycles), figsize=(10, 2.3))
    for ax, c in zip(axes, cycles):
        for i in range(n):
            for j in range(n):
                k = c - 1 - i - j       # operand index present at PE(i,j) in cycle c
                active = 0 <= k < n
                ax.add_patch(plt.Rectangle((j, n - 1 - i), 0.9, 0.9,
                             fc="#dbe8f8" if active else "#f1f0ec",
                             ec=BLUE if active else GRID, lw=1))
                if active:
                    ax.text(j + .45, n - 1 - i + .6, "a%d%d" % (i, k), ha="center",
                            fontsize=7, color=BLUE)
                    ax.text(j + .45, n - 1 - i + .25, "b%d%d" % (k, j), ha="center",
                            fontsize=7, color=ORANGE)
        ax.set_xlim(-0.1, n)
        ax.set_ylim(-0.1, n)
        ax.set_aspect("equal")
        ax.axis("off")
        ax.set_title("cycle %d" % c, fontsize=8, color=INK)
    fig.suptitle("Skewed operand wavefront in a 3x3 array (PE(i,j) computes a_ik * b_kj)",
                 fontsize=9, color=INK, x=0.01, ha="left")
    fig.tight_layout()
    fig.savefig(os.path.join(FIG, "dataflow_skew.png"), dpi=220)
    plt.close(fig)


# ---- performance plots, from synth/summary.json ----
def perf():
    rows = json.load(open(os.path.join(ROOT, "synth", "summary.json")))
    sysr = [r for r in rows if r["design"] == "systolic_top"]
    seqr = [r for r in rows if r["design"] == "seq_matmul"]
    ns = [r["N"] for r in sysr]

    fig, ax = plt.subplots(figsize=(4.6, 3.0))
    ax.plot(ns, [r["cycles"] for r in seqr], color=ORANGE, lw=2, marker="o", ms=6,
            mec="white", mew=1.5)
    ax.plot(ns, [r["cycles"] for r in sysr], color=BLUE, lw=2, marker="o", ms=6,
            mec="white", mew=1.5)
    ax.set_yscale("log")
    ax.set_xticks(ns)
    ax.set_xlabel("matrix size N (N x N)")
    ax.set_ylabel("start -> done latency (cycles)")
    ax.grid(axis="y", color=GRID, lw=0.6)
    ax.text(8.15, seqr[-1]["cycles"], "Sequential\n(1 MAC, N³+3)", color=INK, va="center", fontsize=8)
    ax.text(8.15, sysr[-1]["cycles"], "Systolic\n(N² PEs, 3N+2)", color=INK, va="center", fontsize=8)
    for a, b in zip(sysr, seqr):
        ax.annotate("%.1fx" % (b["cycles"] / a["cycles"]), (a["N"] + 0.35, (a["cycles"] * b["cycles"]) ** .5),
                    ha="center", fontsize=7.5, color=INK2)
    ax.set_xlim(1.6, 10.2)
    ax.set_title("Compute latency (speed-up labelled)", loc="left", fontsize=9.5, color=INK)
    fig.tight_layout()
    fig.savefig(os.path.join(FIG, "latency_vs_n.png"), dpi=220)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(4.6, 3.0))
    width = 0.38
    xs = range(len(ns))
    ax.bar([x - width / 2 - 0.01 for x in xs], [r["xc7"]["LUT"] for r in sysr], width,
           color=BLUE, label="LUTs")
    ax.bar([x + width / 2 + 0.01 for x in xs], [r["xc7"]["FF"] for r in sysr], width,
           color=AQUA, label="Flip-flops")
    for x, r in zip(xs, sysr):
        ax.text(x, max(r["xc7"]["LUT"], r["xc7"]["FF"]) * 1.04 + 20,
                "%d DSP" % r["xc7"]["DSP48E1"], ha="center", fontsize=7.5, color=INK2)
    ax.set_xticks(list(xs))
    ax.set_xticklabels(["%dx%d" % (n, n) for n in ns])
    ax.set_ylabel("count (Artix-7, Yosys)")
    ax.grid(axis="y", color=GRID, lw=0.6)
    ax.set_axisbelow(True)
    ax.legend(frameon=False, fontsize=8, loc="upper left")
    ax.set_title("Systolic array resource scaling", loc="left", fontsize=9.5, color=INK)
    fig.tight_layout()
    fig.savefig(os.path.join(FIG, "resources_vs_n.png"), dpi=220)
    plt.close(fig)


if __name__ == "__main__":
    waveform()
    dataflow()
    perf()
    print("figures written to", FIG)
