#!/usr/bin/env python3
"""
PC side of the board demo. Talks to basys3_top over the Basys-3 USB cable.

What it does:
  1. pings the board ('P' -> expects 'K')
  2. makes two random 4x4 matrices (or uses the ones you give it)
  3. sends them, asks the board to multiply, reads back the 16 results
  4. checks them against numpy and prints both

Needs:  pip install pyserial numpy
Run:    python3 host/uart_host.py --port /dev/tty.usbserial-XXXX     (Mac)
        python3 host/uart_host.py --port COM5                        (Windows)
Find the port: Mac -> ls /dev/tty.usb*   Windows -> Device Manager > Ports
"""
import argparse
import sys

import numpy as np
import serial

N = 4


def to_byte(v):
    """signed 8-bit value -> the byte we actually send (two's complement)"""
    return int(v) & 0xFF


def from_24bit(b0, b1, b2):
    """3 bytes (MSB first) -> signed integer"""
    v = (b0 << 16) | (b1 << 8) | b2
    return v - (1 << 24) if v & 0x800000 else v


def read_exact(port, n):
    data = port.read(n)
    if len(data) != n:
        sys.exit("timed out: got %d of %d bytes. Is the board programmed and reset released?"
                 % (len(data), n))
    return data


def multiply_on_board(port, a, b):
    port.write(b"A" + bytes(to_byte(v) for v in a.flatten()))
    port.write(b"B" + bytes(to_byte(v) for v in b.flatten()))
    port.write(b"S")
    raw = read_exact(port, 3 * N * N)
    vals = [from_24bit(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]
    return np.array(vals).reshape(N, N)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="serial port of the Basys-3")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--runs", type=int, default=5, help="how many random multiplies to try")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    port = serial.Serial(args.port, args.baud, timeout=2)
    port.reset_input_buffer()

    port.write(b"P")
    if read_exact(port, 1) != b"K":
        sys.exit("ping failed: board didn't answer 'K'")
    print("board answered the ping, link is good\n")

    rng = np.random.default_rng(args.seed)
    fails = 0
    for run in range(args.runs):
        a = rng.integers(-128, 128, (N, N))
        b = rng.integers(-128, 128, (N, N))
        hw = multiply_on_board(port, a, b)
        sw = a @ b
        ok = np.array_equal(hw, sw)
        fails += not ok
        print("run %d: %s" % (run, "MATCH" if ok else "MISMATCH"))
        if not ok or run == 0:
            print("A =\n%s\nB =\n%s\nboard C =\n%s\nnumpy C =\n%s\n" % (a, b, hw, sw))
            # results are Q12.8 when the inputs are read as Q4.4
            print("board C as real numbers (Q12.8) =\n%s\n" % (hw / 256.0))

    print("%d/%d runs matched numpy" % (args.runs - fails, args.runs))


if __name__ == "__main__":
    main()
