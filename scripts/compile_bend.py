"""Compile CPU-only programs in two processes so clang can reuse the Bend compiler's memory."""
from pathlib import Path
import subprocess
import tempfile


def native(compiler, source, binary):
    binary = Path(binary)
    with tempfile.TemporaryDirectory(dir=binary.parent) as work:
        generated = Path(work) / "main.c"
        subprocess.run([compiler, source, "-o", generated], check=True)
        subprocess.run(["clang", "-std=c11", "-O3", generated, "-lpthread", "-lm", "-o", binary], check=True)
