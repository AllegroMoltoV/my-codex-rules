#!/usr/bin/env python3
"""Report added Markdown prose through Codex PostToolUse context."""
import json
import re
import sys
from pathlib import Path

CHECKS = (
    (re.compile(r"[（）]"), "全角かっこ"),
    (re.compile("："), "全角コロン"),
    (re.compile(r'[぀-ヿ㐀-鿿々ー]"|"[぀-ヿ㐀-鿿々ー]'), "日本語に隣接するダブルクオート"),
)


def patch_files(patch):
    """Keep postimage contexts and addition offsets; never interpret shell text."""
    lines = patch.splitlines()
    if not lines or lines[0] != "*** Begin Patch" or lines[-1] != "*** End Patch":
        return []
    files, item, hunk = [], None, None
    for line in lines[1:-1]:
        match = re.match(r"^\*\*\* (Add|Update|Delete) File: (.+)$", line)
        if match:
            item = {"kind": match[1], "path": match[2], "hunks": []}
            files.append(item)
            hunk = None
            continue
        if item is None:
            return []
        if line.startswith("*** Move to: "):
            item["path"] = line[len("*** Move to: "):]
        elif line.startswith("@@"):
            hunk = ([], [])
            item["hunks"].append(hunk)
        elif line == "*** End of File":
            continue
        elif line.startswith(("+", " ", "-")):
            if hunk is None:
                hunk = ([], [])
                item["hunks"].append(hunk)
            if line[0] != "-":
                if line[0] == "+":
                    hunk[1].append(len(hunk[0]))
                hunk[0].append(line[1:])
        else:
            return []
    return files


def changed_lines(item, lines):
    selected = set()
    cursor = 0
    for context, additions in item["hunks"]:
        if not additions:
            continue
        positions = [i for i in range(cursor, len(lines) - len(context) + 1)
                     if lines[i:i + len(context)] == context]
        if len(positions) != 1:
            # Ambiguous patch contexts must not point the user at unrelated text.
            continue
        start = positions[0]
        selected.update(start + offset for offset in additions)
        cursor = start + len(context)
    return selected


def prose(lines):
    fence, frontmatter = None, bool(lines and lines[0].strip() == "---")
    for index, line in enumerate(lines):
        if frontmatter:
            if index and line.strip() in ("---", "..."):
                frontmatter = False
            continue
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", line)
        if fence:
            if marker and marker[1][0] == fence[0] and len(marker[1]) >= len(fence) and not marker[2].strip():
                fence = None
            continue
        if marker:
            fence = marker[1]
            continue
        if line.startswith(("    ", "\t")) or line.lstrip().startswith(">"):
            continue
        yield index, re.sub(r"(`+)(.*?)\1", "", line)


def document_path(root, raw):
    path = (root / raw).resolve()
    try:
        relative = path.relative_to(root)
    except ValueError:
        return None
    if path.suffix.lower() != ".md" or any(part.startswith(".") for part in relative.parts):
        return None
    if relative.parts[0] not in ("docs", "rules", "skills") and not (
        len(relative.parts) == 1 and re.match(
            r"^(readme|contributing|changelog|design|architecture|spec|plan)([._-]|$)", path.name, re.I)):
        return None
    return path


def findings(data):
    if not isinstance(data, dict) or data.get("tool_name") != "apply_patch":
        return []
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict) or not isinstance(tool_input.get("command"), str):
        return []
    if not isinstance(data.get("cwd"), str) or not data["cwd"]:
        return []
    root = Path(data["cwd"]).resolve()
    result = []
    for item in patch_files(tool_input["command"]):
        if item["kind"] == "Delete":
            continue
        path = document_path(root, item["path"])
        if path is None:
            continue
        try:
            lines = path.read_text(encoding="utf-8-sig").splitlines()
        except (OSError, UnicodeError):
            continue
        changed = changed_lines(item, lines)
        for index, text in prose(lines):
            if index in changed:
                labels = [label for pattern, label in CHECKS if pattern.search(text)]
                if labels:
                    result.append(f"{path.relative_to(root)}:{index + 1}: {', '.join(labels)}")
    return result


def main():
    # Codex hook JSON uses UTF-8 even when Windows pipes use an ANSI codepage.
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    try:
        result = findings(json.load(sys.stdin))
    except (ValueError, TypeError, OSError):
        return 0
    if result:
        message = "編集は成功しています。日本語技術文書の表記を確認し、原文引用以外の違反を修正してください。\n" + "\n".join(result[:10])
        if len(result) > 10:
            message += f"\nほか {len(result) - 10} 件"
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PostToolUse", "additionalContext": message}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
