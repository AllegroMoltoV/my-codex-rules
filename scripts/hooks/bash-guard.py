#!/usr/bin/env python3
"""Guard identifiable command prefixes, without treating quoted arguments as commands."""
import json
import re
import shlex
import sys


def violation(command):
    if not isinstance(command, str):
        return None
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return None
    # Examine only the first simple command. Shell programs, substitutions and
    # later commands remain subject to the written rule, not this limited guard.
    if not tokens or any(x in command for x in ("$(", "`", "<<")):
        return None
    i = 0
    while i < len(tokens) and re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", tokens[i]):
        i += 1
    if i >= len(tokens):
        return None
    executable = tokens[i]
    args = tokens[i + 1:]
    if executable == "git" and args and (args[0] == "-C" or args[0].startswith("-C")):
        return "git -C を使わず、実行ツールの作業ディレクトリ (workdir) を指定してください。"
    if executable == "cd":
        # Match raw syntax so a quoted directory named '&&' is not a separator.
        word = r'''(?:[^\s;&|()'"\\]|\\.|'[^']*'|"(?:[^"\\]|\\.)*")+'''
        if re.match(r"^\s*cd\s+(?:--\s+)?" + word + r"\s*&&", command):
            return "cd と後続コマンドを連結せず、実行ツールの作業ディレクトリ (workdir) を指定してください。"
    return None


def main():
    # Codex hook JSON uses UTF-8 even when Windows pipes use an ANSI codepage.
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    try:
        data = json.load(sys.stdin)
        if not isinstance(data, dict) or data.get("tool_name") != "Bash":
            return 0
        tool_input = data.get("tool_input")
        if not isinstance(tool_input, dict):
            return 0
        reason = violation(tool_input.get("command"))
    except (ValueError, TypeError):
        return 0
    if reason:
        print(reason, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
