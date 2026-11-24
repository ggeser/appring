#!/usr/bin/env python3
"""Bound an off-screen check and reap all its helpers (Linux, including setsid).

A process group alone misses Qt's detached helpers. As a child subreaper we
adopt them when their parent exits; cleanup signals only our descendants.
"""
import argparse
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import time


def children(pid):
    try:
        return [int(p) for p in Path(f"/proc/{pid}/task/{pid}/children").read_text().split()]
    except FileNotFoundError:
        return []


def descendants(pid):
    result = []
    for child in children(pid):
        result.extend(descendants(child))
        result.append(child)
    return result


def cleanup():
    start = time.monotonic()
    while True:
        pids = descendants(os.getpid())
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM if time.monotonic() - start < 2 else signal.SIGKILL)
            except ProcessLookupError:
                pass
        while True:
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                return
            if pid == 0:
                break
        time.sleep(0.02)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.timeout <= 0 or not args.command:
        parser.error("positive timeout and command required")
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise OSError(ctypes.get_errno(), "cannot become child subreaper")
    interrupted = 0

    def interrupt(signum, _frame):
        nonlocal interrupted
        interrupted = signum

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupt)
    try:
        proc = subprocess.Popen(args.command, start_new_session=True)
        deadline = time.monotonic() + args.timeout
        while proc.poll() is None:
            if interrupted:
                return 128 + interrupted
            if time.monotonic() >= deadline:
                print(f"TIMEOUT after {args.timeout:g}s: {' '.join(args.command)}", flush=True)
                return 124
            time.sleep(0.02)
        return proc.returncode if proc.returncode >= 0 else 128 - proc.returncode
    finally:
        cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
