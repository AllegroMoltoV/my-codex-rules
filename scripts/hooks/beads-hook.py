#!/usr/bin/env python3
"""Forward the official hook unchanged, with a process-local default."""
import os
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        return 1
    env = os.environ.copy()
    env.setdefault("BD_NO_GIT_OPS", "false")
    try:
        return subprocess.call(["bd", "codex-hook", sys.argv[1]], env=env)
    except OSError as error:
        print(f"Beads hook could not run: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
