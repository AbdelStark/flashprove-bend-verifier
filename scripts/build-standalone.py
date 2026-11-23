#!/usr/bin/env python3
"""Compile the standalone Bend entry with a digest of its transitive source inputs."""
import hashlib
from pathlib import Path
import re
import tempfile
from compile_bend import native

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
ENTRY = ROOT / "src/standalone.bend"


def identity():
    files = {Path(__file__).resolve(), ROOT / "scripts/compile_bend.py", ROOT / "toolchain.lock"}
    todo = [ENTRY]
    while todo:
        source = todo.pop()
        if source not in files:
            files.add(source)
            for relative in re.findall(r"^import (\.[\w./-]+\.bend) as ", source.read_text(), re.M):
                todo.append((source.parent / relative).resolve())
    h = hashlib.sha256()
    for source in sorted(files):
        h.update(str(source.relative_to(ROOT)).encode() + b"\0")
        h.update(hashlib.sha256(source.read_bytes()).digest())
    return h.hexdigest()


if __name__ == "__main__":
    BUILD.mkdir(exist_ok=True)
    digest = identity()
    with tempfile.TemporaryDirectory(dir=BUILD) as temp:
        work = Path(temp)
        entry = work / "main.bend"
        entry.write_text('import Base\nimport ../../src/standalone.bend as CLI\n\n'
                         f'def main() -> IO(Unit): CLI.run_build("{digest}")\n')
        binary = work / "verify-bend"
        native(ROOT / ".toolchain/bend/bin/bend", entry, binary)
        hashfile = work / "verify-bend.digest"
        hashfile.write_text(digest + "\n")
        binary.replace(BUILD / binary.name)
        hashfile.replace(BUILD / hashfile.name)
