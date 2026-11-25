"""Check worker selection and launch order without timing verifier processes."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("benchmark_standalone", SCRIPTS / "benchmark-standalone.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class PairedRevisions(unittest.TestCase):
    def test_both_revisions_get_same_worker_count_and_verified_warmups(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("tables", "plans"):
                (root / name).mkdir()
            before, after = root / "old", root / "new"
            for binary, digest in ((before, "a" * 64), (after, "b" * 64)):
                binary.write_bytes(binary.name.encode())
                Path(str(binary) + ".digest").write_text(digest)
            order = []

            def observe(program, case, digest, sample, work, logs, workers, observe_workers=False):
                order.append((program.name, workers, observe_workers))
                return {"fixture": case.name, "program": program.name, "wall_s": 1, "cpu_s": 1, "rss_kib": 1}

            args = ["bench", "--compare", "bend", "--before", str(before), "--after", str(after),
                    "--workers", "16", "--fixture", "full-size", "--output", str(root / "result")]
            with patch.object(bench, "BUILD", root), patch.object(bench, "measure", observe), \
                 patch.object(bench, "check_inputs", return_value={}), patch.object(sys, "argv", args), \
                 contextlib.redirect_stdout(io.StringIO()):
                bench.main()
            self.assertEqual(order, [("before", 16, True), ("verify-bend", 16, True),
                                     ("before", 16, False), ("verify-bend", 16, False),
                                     ("verify-bend", 16, False), ("before", 16, False),
                                     ("before", 16, False), ("verify-bend", 16, False)])

    def test_warmup_refuses_ignored_worker_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "ID.txt").write_text("model")
            output = "commitment: test\nproof of work: test\nresult-v1 test\nYES\n"

            def ignored_switch(cmd, *, cwd, env, stdout, stderr):
                self.assertEqual(cmd[-3:], ["-j", "16", "-timing"])
                stdout.write(output)
                stderr.write("timing: workers 1\n")
                return bench.subprocess.CompletedProcess(cmd, 0)

            with patch.object(bench, "expected", return_value=output.splitlines()), \
                 patch.object(bench.subprocess, "run", ignored_switch):
                with self.assertRaisesRegex(RuntimeError, "expected 16 runtime workers"):
                    bench.measure(root / "before", root, "", 1, root, root, 16, observe_workers=True)


if __name__ == "__main__":
    unittest.main()
