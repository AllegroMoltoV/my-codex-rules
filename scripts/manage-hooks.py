#!/usr/bin/env python3
"""Install/remove this repository's handlers without replacing other handlers."""
import argparse
import json
import os
import re
import shlex
import sys
import tempfile
from pathlib import Path

OWNER = "my-codex-rules"
EVENTS = ("SessionStart", "PreCompact", "PostCompact", "UserPromptSubmit")


def command(args):
    if os.name == "nt":
        # Windows setup already requires PowerShell 7. Explicit invocation also
        # handles Python paths containing spaces regardless of the parent shell.
        expression = "& " + " ".join("'" + arg.replace("'", "''") + "'" for arg in args) + "; exit $LASTEXITCODE"
        import base64
        encoded = base64.b64encode(expression.encode("utf-16-le")).decode("ascii")
        return "pwsh -NoProfile -EncodedCommand " + encoded
    return shlex.join(args)


def official_event(handler):
    value = handler.get("command", "")
    match = re.fullmatch(r"bd codex-hook (SessionStart|PreCompact|PostCompact|UserPromptSubmit)", value)
    if match:
        return match[1]
    # Migrate the repository's former shell adapter after a move as well.
    match = re.search(r"(?:^|[/\\])beads-codex-hook\.sh[\"']? (SessionStart|PreCompact|PostCompact|UserPromptSubmit)$", value)
    return match[1] if match else None


def update(data, runtime, remove=False):
    hooks = data.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    for event in list(hooks):
        groups = []
        seen = set()
        for group in hooks[event]:
            remaining = []
            for handler in group.get("hooks", []):
                owned = handler.get("statusMessage", "").startswith(OWNER + ":")
                source_event = official_event(handler)
                if owned and event not in EVENTS:
                    continue
                if event in EVENTS and (owned or source_event == event):
                    if remove:
                        # Restore the official command so bd setup --remove can
                        # remove its own groups and any other integration state.
                        handler = dict(handler, command=f"bd codex-hook {event}")
                        handler.pop("statusMessage", None)
                    else:
                        handler = dict(handler, command=command([sys.executable, str(runtime / "beads-hook.py"), event]),
                                       statusMessage=f"{OWNER}: {event}")
                    key = (group.get("matcher", ""), event)
                    if key in seen:
                        continue
                    seen.add(key)
                remaining.append(handler)
            if remaining:
                groups.append(dict(group, hooks=remaining))
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    if not remove:
        for event, matcher, name in (("PreToolUse", "^Bash$", "bash-guard.py"),
                                     ("PostToolUse", "^apply_patch$", "md-lint.py")):
            hooks.setdefault(event, []).append({"matcher": matcher, "hooks": [{
                "type": "command", "command": command([sys.executable, str(runtime / name)]),
                "timeout": 10, "statusMessage": f"{OWNER}: {name}"}]})
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hooks", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    data = json.loads(args.hooks.read_text(encoding="utf-8-sig")) if args.hooks.exists() else {}
    if not isinstance(data, dict):
        raise ValueError("hooks configuration must be an object")
    update(data, args.runtime.resolve(), args.remove)
    args.hooks.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=args.hooks.parent, prefix=args.hooks.name + ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(name, args.hooks)
    finally:
        if os.path.exists(name):
            os.unlink(name)


if __name__ == "__main__":
    main()
