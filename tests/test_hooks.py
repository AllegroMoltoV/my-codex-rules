import copy
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import shutil
from unittest import mock
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / "scripts/hooks"
GUARD = runpy.run_path(str(HOOKS / "bash-guard.py"))
LINT = runpy.run_path(str(HOOKS / "md-lint.py"))
MANAGER = runpy.run_path(str(ROOT / "scripts/manage-hooks.py"))


def invoke(name, payload, env=None):
    return subprocess.run([sys.executable, str(HOOKS / name)],
                          input=json.dumps(payload, ensure_ascii=False), capture_output=True, text=True, env=env)


class GuardTests(unittest.TestCase):
    def test_actual_commands_are_blocked(self):
        for command in ("git -C /tmp status", "git -C/tmp status", "cd /tmp && pwd",
                        "cd -- '/a b' && git status"):
            with self.subTest(command=command):
                result = invoke("bash-guard.py", {"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertEqual(2, result.returncode)
                self.assertIn("workdir", result.stderr)

    def test_arguments_quotes_and_complex_programs_are_not_commands(self):
        for command in ("printf %s git -C", "printf '%s' 'cd /tmp && pwd'",
                        "echo 'git -C /tmp'", "cd '&&'", "git status",
                        "python3 -c 'print(1)'", "for x in a; do echo $x; done",
                        "echo $(git -C /tmp status)", "echo 'unclosed"):
            with self.subTest(command=command):
                self.assertIsNone(GUARD["violation"](command))

    def test_windows_pipe_encoding_does_not_change_json(self):
        env = dict(os.environ, PYTHONIOENCODING="cp932")
        result = invoke("bash-guard.py", {"tool_name": "Bash", "tool_input": {"command": "git -C /tmp/日本語 status"}}, env)
        self.assertEqual(2, result.returncode)
        self.assertIn("作業ディレクトリ", result.stderr)

    def test_malformed_and_unrelated_input(self):
        for payload in (None, [], {"tool_name": "other"}, {"tool_name": "Bash", "tool_input": []}):
            self.assertEqual(0, invoke("bash-guard.py", payload).returncode)


class LintTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def check(self, path, text, patch):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return invoke("md-lint.py", {"tool_name": "apply_patch", "cwd": str(self.root),
                                    "tool_input": {"command": patch}})

    def test_add_reports_context_without_failing_edit(self):
        result = self.check("README.md", '新規（本文）："値"\n',
                            '*** Begin Patch\n*** Add File: README.md\n+新規（本文）："値"\n*** End Patch')
        self.assertEqual(0, result.returncode)
        data = json.loads(result.stdout)
        self.assertEqual("PostToolUse", data["hookSpecificOutput"]["hookEventName"])
        self.assertIn("README.md:1", data["hookSpecificOutput"]["additionalContext"])
        self.assertNotIn("decision", data)

    def test_windows_pipe_encoding_keeps_japanese_findings(self):
        target = self.root / "README.md"
        target.write_text("日本語：\n")
        payload = {"tool_name": "apply_patch", "cwd": str(self.root), "tool_input": {
            "command": "*** Begin Patch\n*** Add File: README.md\n+日本語：\n*** End Patch"}}
        result = invoke("md-lint.py", payload, dict(os.environ, PYTHONIOENCODING="cp932"))
        self.assertEqual(0, result.returncode)
        self.assertIn("全角コロン", json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"])

    def test_existing_violations_are_not_reported(self):
        result = self.check("docs/design.md", "既存（違反）\n新しい本文\n",
                            "*** Begin Patch\n*** Update File: docs/design.md\n@@\n 既存（違反）\n-古い本文\n+新しい本文\n*** End Patch")
        self.assertEqual("", result.stdout)

    def test_edit_inside_existing_code_fence_is_ignored(self):
        result = self.check("README.md", '```python\nprint("値：")\n```\n',
                            '*** Begin Patch\n*** Update File: README.md\n@@\n-print("旧")\n+print("値：")\n*** End Patch')
        self.assertEqual("", result.stdout)

    def test_markdown_regions_and_inline_code(self):
        text = '---\ntitle: 値：\n---\n````python\n```\n値：\n````\n本文 `値：` と ``値（型）``\n> 引用：\n    値：\n'
        patch = '*** Begin Patch\n*** Add File: README.md\n' + '\n'.join('+' + line for line in text.splitlines()) + '\n*** End Patch'
        self.assertEqual("", self.check("README.md", text, patch).stdout)

    def test_rename_and_multiple_hunks(self):
        result = self.check("docs/new.md", "先頭\n追加：\n中間\n末尾：\n",
                            "*** Begin Patch\n*** Update File: docs/old.md\n*** Move to: docs/new.md\n@@\n 先頭\n+追加：\n@@\n 中間\n-末尾\n+末尾：\n*** End Patch")
        message = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("docs/new.md:2", message)
        self.assertIn("docs/new.md:4", message)

    def test_ambiguous_context_does_not_select_unrelated_line(self):
        result = self.check("README.md", "値：\n値：\n",
                            "*** Begin Patch\n*** Update File: README.md\n@@\n-旧\n+値：\n*** End Patch")
        self.assertEqual("", result.stdout)

    def test_out_of_scope_and_deleted_files(self):
        for path in (".prompts/DRAFT/ticket.md", "message.md", "other.md"):
            result = self.check(path, "値：\n", f"*** Begin Patch\n*** Add File: {path}\n+値：\n*** End Patch")
            self.assertEqual("", result.stdout)
        self.assertEqual([], LINT["findings"]({"tool_name": "apply_patch", "cwd": str(self.root),
                                             "tool_input": {"command": "*** Begin Patch\n*** Delete File: README.md\n*** End Patch"}}))

    def test_outside_and_symlink_escape(self):
        with tempfile.TemporaryDirectory() as outside:
            path = Path(outside) / "README.md"
            path.write_text("値：\n")
            self.assertIsNone(LINT["document_path"](self.root, str(path)))
            (self.root / "README.md").symlink_to(path)
            self.assertIsNone(LINT["document_path"](self.root, "README.md"))


class RegistrationTests(unittest.TestCase):
    def test_install_move_remove_preserves_foreign_handlers(self):
        data = {"description": "keep", "hooks": {
            "SessionStart": [{"matcher": "startup|resume|clear", "hooks": [
                {"type": "command", "command": "bd codex-hook SessionStart"},
                {"type": "command", "command": "echo user"}]}],
            "PreToolUse": [{"matcher": "Bash", "custom": True, "hooks": [
                {"type": "command", "command": "echo user guard"}]}]}}
        first = MANAGER["update"](copy.deepcopy(data), Path("/old/hooks"))
        second = MANAGER["update"](copy.deepcopy(first), Path("/old/hooks"))
        self.assertEqual(first, second)
        moved = MANAGER["update"](second, Path("/new/hooks"))
        self.assertNotIn("/old/hooks", json.dumps(moved))
        removed = MANAGER["update"](moved, Path("/new/hooks"), True)
        self.assertEqual(data, removed)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is required for Windows command transport verification")
    def test_windows_transport_preserves_exit_code_and_quoted_arguments(self):
        for code in (0, 2, 7):
            args = [sys.executable, "-c", "import sys; print(sys.argv[1]); sys.exit(int(sys.argv[2]))", "path with spaces and 'quotes'", str(code)]
            with mock.patch.object(MANAGER["os"], "name", "nt"):
                generated = MANAGER["command"](args)
            result = subprocess.run(generated.split(), capture_output=True, text=True)
            self.assertEqual(code, result.returncode)
            self.assertEqual("path with spaces and 'quotes'", result.stdout.strip())

    def test_official_reregistration_and_legacy_adapter(self):
        data = {"hooks": {event: [{"hooks": [
            {"command": f"/old/beads-codex-hook.sh {event}"},
            {"command": f"bd codex-hook {event}"}]}] for event in MANAGER["EVENTS"]}}
        MANAGER["update"](data, Path("/hooks"))
        for event in MANAGER["EVENTS"]:
            self.assertEqual(1, len(data["hooks"][event][0]["hooks"]))


@unittest.skipIf(os.name == "nt", "POSIX executable fixture; real bd is covered by integration verification")
class BeadsAdapterTests(unittest.TestCase):
    def test_environment_io_event_and_failure_are_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            bd = Path(temp) / "bd"
            bd.write_text('#!' + sys.executable + '\nimport os,sys,json\nprint(json.dumps([sys.argv[1:],os.environ["BD_NO_GIT_OPS"],sys.stdin.read()]))\nprint("diagnostic",file=sys.stderr)\nsys.exit(7)\n')
            bd.chmod(0o755)
            for value in (None, "true", "false"):
                env = os.environ.copy()
                env["PATH"] = temp + os.pathsep + env["PATH"]
                env.pop("BD_NO_GIT_OPS", None)
                if value is not None:
                    env["BD_NO_GIT_OPS"] = value
                result = subprocess.run([sys.executable, str(HOOKS / "beads-hook.py"), "PostCompact"],
                                        input='{"session_id":"test"}', env=env, capture_output=True, text=True)
                self.assertEqual(7, result.returncode)
                args, actual, stdin = json.loads(result.stdout)
                self.assertEqual(["codex-hook", "PostCompact"], args)
                self.assertEqual(value or "false", actual)
                self.assertEqual('{"session_id":"test"}', stdin)
                self.assertEqual("diagnostic\n", result.stderr)


if __name__ == "__main__":
    unittest.main()
