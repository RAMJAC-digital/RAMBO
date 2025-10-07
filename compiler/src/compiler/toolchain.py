from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from rich.console import Console

console = Console()

NESASM_REPO = "https://github.com/toastynerd/nesasm.git"
NESASM_PATCHES = [
    (
        "src/pcx.c",
        "\t\t\texpr_lablcnt = NULL;",
        "\t\t\texpr_lablcnt = 0;",
    ),
    (
        "src/pcx.c",
        "\tif (strlen(name) && (strcasecmp(pcx_name, name) == NULL))",
        "\tif (strlen(name) && (strcasecmp(pcx_name, name) == 0))",
    ),
    (
        "src/defs.h",
        "#define SBOLSZ\t32",
        "#define SBOLSZ\t128",
    ),
]


class ToolchainManager:
    def __init__(self, repo_root: Path) -> None:
        self.repo_root = repo_root
        self.tool_dir = repo_root / "compiler" / ".toolchain"
        self.tool_dir.mkdir(parents=True, exist_ok=True)

    def ensure_nesasm(self, force: bool = False) -> Path:
        repo_path = self.tool_dir / "nesasm"
        if force and repo_path.exists():
            shutil.rmtree(repo_path)

        if not repo_path.exists():
            console.log(f"Cloning nesasm toolchain into {repo_path}")
            subprocess.run([
                "git",
                "clone",
                "--depth",
                "1",
                NESASM_REPO,
                str(repo_path),
            ], check=True)

        for relpath, original, replacement in NESASM_PATCHES:
            self._apply_patch(repo_path, relpath, original, replacement)

        binary = repo_path / "bin" / "nesasm"
        if not binary.exists() or force:
            env = dict(os.environ)
            cmd = ["make"]
            console.log("Building nesasm")
            subprocess.run(cmd, cwd=repo_path, env=env, check=True)
            binary = repo_path / "bin" / "nesasm"
            if not binary.exists():
                raise RuntimeError("nesasm build failed")
        return binary

    def _apply_patch(self, repo_path: Path, relative: str, original: str, replacement: str) -> None:
        path = repo_path / relative
        text = path.read_text()
        if replacement in text:
            return
        if original not in text:
            raise RuntimeError(f"Expected pattern not found in {path}")
        path.write_text(text.replace(original, replacement))
        rel = path.relative_to(repo_path)
        console.log(f"Patched {rel}")


__all__ = ["ToolchainManager"]
