"""Check worker selection and launch order without timing verifier processes."""
import contextlib
import importlib.util
import io
import json
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
    def test_linux_arm_cpuinfo_can_omit_the_model_name(self):
        with patch.object(bench.platform, "system", return_value="Linux"), \
             patch.object(bench.platform, "processor", return_value=""), \
             patch.object(bench.platform, "machine", return_value="aarch64"), \
             patch.object(Path, "is_file", return_value=True), \
             patch.object(Path, "read_text", return_value="CPU implementer : 0x41"), \
             patch.dict(bench.os.environ, BENCH_CHECKOUT_REVISION="test"):
            self.assertEqual(bench.machine()["cpu"], "aarch64")

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

    def test_screen_uses_quiet_medians_and_reverses_trial_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binary = root / "release"
            binary.write_text("test binary")
            logs = root / "logs"
            logs.mkdir()
            for name in ("tables", "plans"):
                (root / name).mkdir()
            calls = []

            def observe(program, case, digest, sample, work, directory, workers, observe_workers=False):
                calls.append((sample, workers, observe_workers))
                # One fast outlier for 4 workers must not decide the winner.
                wall = {2: [300, 5, 5, 5], 4: [1, 1, 6, 8]}[workers][sample]
                return {"wall_s": wall}

            with patch.object(bench, "BUILD", root), patch.object(bench, "measure", observe), \
                 patch.object(bench, "bend_digest", return_value="a" * 64), \
                 patch.object(bench, "check_inputs", return_value={}), contextlib.redirect_stdout(io.StringIO()):
                bench.screen_workers(binary, [2, 4], 3, logs)
            self.assertEqual(calls, [(0, 4, True), (0, 2, True), (1, 2, False), (1, 4, False),
                                     (2, 4, False), (2, 2, False), (3, 2, False), (3, 4, False)])
            data = json.loads((logs / "results.json").read_text())
            self.assertEqual(data["selected_workers"], 2)
            self.assertEqual(len(data["samples"]), 6)

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
