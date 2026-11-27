"""Run the documentation checker against a small checkout with common sources of drift."""
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


class DocsCheckTest(unittest.TestCase):
    def test_published_links_targets_and_pins(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            checker = root / "scripts/check-docs.py"
            shutil.copyfile(Path(__file__).resolve().parents[1] / "scripts/check-docs.py", checker)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            (root / "Makefile").write_text("bootstrap:\nstandalone:\n")
            (root / "toolchain.lock").write_text("BEND_VERSION=2.0.40\n")
            (root / "upstream.lock").write_text("FLASHPROVE_COMMIT=abcdef1234567890\n")
            (root / ".gitignore").write_text("/build\n")
            (root / "build").mkdir()
            (root / "build/report.md").write_text("Only on this machine\n")
            (root / "old.md").touch()
            subprocess.run(["git", "add", "old.md"], cwd=root, check=True)
            (root / "old.md").unlink()
            (root / "notes.md").touch()
            readme = root / "README.md"
            readme.write_text(
                "[Notes](notes.md)\n```sh\nmake bootstrap standalone\n```\n"
                "[Protocol](https://github.com/anthropics/FlashProve/tree/abcdef1) "
                "[Port](https://github.com/owner/port/commit/1234567)\n"
            )
            good = subprocess.run([sys.executable, checker], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stdout + good.stderr)

            with readme.open("a") as doc:
                doc.write(
                    "[Local output](build/report.md) and [deleted note](old.md)\n"
                    "`make bootstrap missing-inline`\n"
                    "```sh\nmake bootstrap missing-example\n```\n"
                    "[Stale pin](https://github.com/anthropics/FlashProve/blob/0123456/README.md)\n"
                )
            bad = subprocess.run([sys.executable, checker], capture_output=True, text=True)
            self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
            for error in ("build/report.md", "old.md", "missing-inline", "missing-example", "0123456"):
                self.assertIn(error, bad.stdout)

    def test_requirements_trace_to_workflow_commands(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for d in ("scripts", "docs/spec", ".github/workflows"):
                (root / d).mkdir(parents=True)
            checker = root / "scripts/check-docs.py"
            shutil.copyfile(Path(__file__).resolve().parents[1] / "scripts/check-docs.py", checker)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            (root / "Makefile").write_text("ci: unit | tools\nunit:\ntools:\nmanual:\nextended:\n")
            (root / "toolchain.lock").write_text("BEND_VERSION=2.0.40\n")
            (root / "upstream.lock").write_text("FLASHPROVE_COMMIT=abcdef1234567890\n")
            (root / ".github/workflows/ci.yml").write_text(
                "jobs:\n  a:\n    steps:\n      - run: make ci\n      - run: make extended FUZZ_ARGS=\"-n 1\"\n")
            spec = root / "docs/spec/reqs.md"
            head = "# Requirements\n\n> Status: living\n\n| Requirement | Evidence |\n|---|---|\n"
            spec.write_text(head + "| **REQ-A-1** | `make unit` |\n| **REQ-A-2** | `make tools` and `make extended` |\n")
            good = subprocess.run([sys.executable, checker], capture_output=True, text=True)
            self.assertEqual(good.returncode, 0, good.stdout + good.stderr)

            spec.write_text(head + "| **REQ-A-1** | `make manual` |\n| **REQ-A-2** | Read the logs. |\n")
            bad = subprocess.run([sys.executable, checker], capture_output=True, text=True)
            self.assertEqual(bad.returncode, 1, bad.stdout + bad.stderr)
            self.assertIn("REQ-A-1 cites `make manual`, which no workflow runs", bad.stdout)
            self.assertIn("REQ-A-2 cites no `make` command", bad.stdout)


if __name__ == "__main__":
    unittest.main()
