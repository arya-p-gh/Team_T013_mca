#!/usr/bin/env python3
"""
Makes the test matrices AND the correct answers for the Verilog testbench.

The idea: let NumPy do the matrix multiply (we trust it), save both the inputs
and the answers to hex files, and have tb_matmul.v check whether our hardware
gets the same numbers. If the hardware and NumPy ever disagree, the testbench
prints MISMATCH.

Number format (same as the hardware):
  inputs  - 8-bit signed, read as Q4.4 (so 1.5 is stored as 24)
  outputs - 20-bit signed, read as Q12.8 (divide by 256 to get the real value)
The hardware never rounds anything, so plain integer math here matches it
exactly.

Files it writes for each N (into sim/vectors/):
  N{N}_ab.hex     - A then B for every test, one 8-bit hex value per line
  N{N}_c.hex      - the expected C for every test, one 20-bit hex value per line
  N{N}_tests.txt  - the same tests printed nicely, handy for the report/demo

Run it like:  python3 model/gen_vectors.py 3 4 8   (defaults to 3 and 4)

Phase II additions:
  - sizes like 12 work too (used by the tiled 12x12 test)
  - --stress K  also writes N{N}_stress_ab.hex / N{N}_stress_c.hex with K extra
    random tests (different seed), for the long regression run. Random tests
    catch the weird corner cases our hand-picked ones might miss.
    e.g.  python3 model/gen_vectors.py 4 --stress 200
"""
import os
import sys
import numpy as np

DATA_W, ACC_W, FRAC = 8, 20, 4
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sim", "vectors")


def q(x):
    """Turn a normal number like 1.5 into its Q4.4 code (1.5 * 16 = 24)."""
    return int(round(x * (1 << FRAC)))


def matmul_ref(a, b):
    """The 'correct answer'. int64 so nothing can overflow on the Python side."""
    return a.astype(np.int64) @ b.astype(np.int64)


def tohex(v, bits):
    # negative numbers need to be written in two's complement for $readmemh,
    # so mask to the right width first (e.g. -1 in 8 bits -> ff)
    return format(int(v) & ((1 << bits) - 1), "0{}x".format((bits + 3) // 4))


def build_tests(n, seed=2026):
    # fixed seed, so we get the same "random" tests every run
    rng = np.random.default_rng(seed + n)
    lo, hi = -(1 << (DATA_W - 1)), (1 << (DATA_W - 1)) - 1
    idx = np.arange(n * n).reshape(n, n)
    t = []
    # simple ones first: if these fail, the wiring is wrong
    t.append(("identity x B", np.eye(n, dtype=int), idx + 1))
    t.append(("A x identity", idx - n, np.eye(n, dtype=int)))
    t.append(("zero matrix", np.zeros((n, n), int), rng.integers(lo, hi + 1, (n, n))))
    # extreme values, to make sure signs and the accumulator width are right
    t.append(("all +max (127)", np.full((n, n), hi), np.full((n, n), hi)))
    t.append(("all -max (-128)", np.full((n, n), lo), np.full((n, n), lo)))
    t.append(("+max x -max", np.full((n, n), hi), np.full((n, n), lo)))
    # every element different, so swapped rows/columns would show up
    t.append(("sequential 1..N^2", idx + 1, (idx + 1).T))
    # actual fractions like 1.5 and -2.25, to show the fixed-point side working
    base_a = np.resize([q(1.5), q(-2.25), q(0.5), q(3.0)], n)
    fx_a = np.array([base_a for _ in range(n)]) + np.arange(n).reshape(n, 1) * q(0.25)
    base_b = np.resize([q(0.75), q(-1.0), q(2.0), q(-0.5)], n)
    fx_b = np.array([np.roll(base_b, r) for r in range(n)])
    t.append(("Q4.4 fixed-point values", fx_a, fx_b))
    # and a few random ones for good measure
    for r in range(6):
        t.append(("random #%d" % (r + 1), rng.integers(lo, hi + 1, (n, n)),
                  rng.integers(lo, hi + 1, (n, n))))
    # wrap every input into the signed 8-bit range. For N <= 8 nothing changes,
    # but for bigger N (like 12) patterns such as 1..N^2 would go past 127,
    # and the hardware can only hold -128..127
    def fit(m):
        return ((np.asarray(m).astype(int) + 128) % 256) - 128
    return [(name, fit(a), fit(b), matmul_ref(fit(a), fit(b))) for name, a, b in t]


def stress_tests(n, count, seed=777):
    """count purely random tests, from a different seed than build_tests"""
    rng = np.random.default_rng(seed + n)
    lo, hi = -(1 << (DATA_W - 1)), (1 << (DATA_W - 1)) - 1
    out = []
    for r in range(count):
        a = rng.integers(lo, hi + 1, (n, n))
        b = rng.integers(lo, hi + 1, (n, n))
        out.append(("stress #%d" % (r + 1), a, b, matmul_ref(a, b)))
    return out


def write(n, tests=None, tag=""):
    os.makedirs(OUT, exist_ok=True)
    if tests is None:
        tests = build_tests(n)
    with open(os.path.join(OUT, "N%d%s_ab.hex" % (n, tag)), "w") as fab, \
         open(os.path.join(OUT, "N%d%s_c.hex" % (n, tag)), "w") as fc, \
         open(os.path.join(OUT, "N%d%s_tests.txt" % (n, tag)), "w") as ft:
        for k, (name, a, b, c) in enumerate(tests):
            # make sure the answer fits in the 20-bit accumulator, otherwise
            # the test itself would be broken
            assert c.max() < (1 << (ACC_W - 1)) and c.min() >= -(1 << (ACC_W - 1))
            assert a.min() >= -128 and a.max() <= 127 and b.min() >= -128 and b.max() <= 127
            for v in a.flatten():
                fab.write(tohex(v, DATA_W) + "\n")
            for v in b.flatten():
                fab.write(tohex(v, DATA_W) + "\n")
            for v in c.flatten():
                fc.write(tohex(v, ACC_W) + "\n")
            ft.write("Test %d: %s\nA =\n%s\nB =\n%s\nC = A x B =\n%s\n"
                     "C (Q12.8 real) =\n%s\n\n" % (k, name, a, b, c, c / 256.0))
    print("N=%d%s: %d tests written to %s" % (n, tag, len(tests), OUT))
    return len(tests)


if __name__ == "__main__":
    args = sys.argv[1:]
    stress = 0
    if "--stress" in args:
        i = args.index("--stress")
        stress = int(args[i + 1])
        del args[i:i + 2]
    sizes = [int(x) for x in args] or [3, 4]
    for n in sizes:
        write(n)
        if stress:
            write(n, stress_tests(n, stress), "_stress")
