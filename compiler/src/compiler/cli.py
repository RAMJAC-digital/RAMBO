from __future__ import annotations

import hashlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.panel import Panel

from .toolchain import ToolchainManager

console = Console()

app = typer.Typer(help="Build helper for RAMBO test ROMs.")


def repo_root() -> Path:
    """Return the git repository root."""
    try:
        out = subprocess.check_output([
            "git",
            "rev-parse",
            "--show-toplevel",
        ], cwd=Path(__file__).resolve().parent, text=True)
    except subprocess.CalledProcessError as exc:  # pragma: no cover - git mandatory
        raise typer.Exit(code=1) from exc
    return Path(out.strip())


def copytree(src: Path, dst: Path) -> None:
    """Copy a directory tree while allowing existing destinations."""
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


@app.command()
def toolchain(force: bool = typer.Option(False, "--force", help="Rebuild toolchain binaries.")) -> None:
    """Prepare local assembler toolchain."""
    root = repo_root()
    manager = ToolchainManager(root)
    path = manager.ensure_nesasm(force=force)
    console.print(Panel.fit(f"nesasm ready: [cyan]{path}[/]"))


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def _ensure_bit_perfect(built: Path, reference: Path) -> None:
    if not reference.exists():
        console.log(f"Reference ROM missing; skipped verification ({reference})")
        return

    built_bytes = built.read_bytes()
    reference_bytes = reference.read_bytes()
    if built_bytes != reference_bytes:
        console.print(
            Panel.fit(
                "Built ROM does not match reference AccuracyCoin image. "
                "Use --skip-verify if divergence is intentional.",
                title="Verification Failed",
                style="red",
            )
        )
        raise typer.Exit(code=3)

    console.print(
        Panel.fit(
            "Bit-perfect match with repository AccuracyCoin.nes",
            title="Verified",
            style="green",
        )
    )


def _build_accuracycoin(output: Optional[Path], keep_temp: bool, skip_verify: bool) -> Path:
    root = repo_root()
    manager = ToolchainManager(root)
    nesasm = manager.ensure_nesasm()

    source_dir = root / "AccuracyCoin"
    if not source_dir.exists():
        raise typer.Exit(code=1)

    build_dir = Path(tempfile.mkdtemp(prefix="accuracycoin-"))
    try:
        copytree(source_dir, build_dir)
        console.log(f"Assembling AccuracyCoin from {build_dir}")
        cmd = [str(nesasm), "AccuracyCoin.asm"]
        subprocess.run(cmd, cwd=build_dir, check=True)

        produced = build_dir / "AccuracyCoin.nes"
        if not produced.exists():
            raise typer.Exit(code=1)

        target_dir = output if output else (root / "compiler" / "dist" / "accuracycoin")
        if target_dir.is_dir() or target_dir.suffix == "":
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / "AccuracyCoin.nes"
        else:
            target = target_dir
            target.parent.mkdir(parents=True, exist_ok=True)

        shutil.copy2(produced, target)

        sha = _hash_file(target)
        console.print(Panel.fit(f"Built AccuracyCoin → [green]{target}[/]\nSHA-256: {sha}"))

        if not skip_verify:
            reference = root / "AccuracyCoin" / "AccuracyCoin.nes"
            _ensure_bit_perfect(target, reference)
        return target
    finally:
        if keep_temp:
            console.log(f"Intermediate build preserved at {build_dir}")
        else:
            shutil.rmtree(build_dir, ignore_errors=True)


@app.command("build-accuracycoin")
def build_accuracycoin(
    output: Optional[Path] = typer.Option(None, "--output", "-o", help="Destination file or directory."),
    keep_temp: bool = typer.Option(False, help="Preserve the temporary build directory."),
    skip_verify: bool = typer.Option(False, help="Skip byte-for-byte comparison with repo AccuracyCoin.nes."),
) -> None:
    """Build the AccuracyCoin ROM using nesasm."""
    _build_accuracycoin(output, keep_temp, skip_verify)


@app.command("build-basic")
def build_basic(
    output: Optional[Path] = typer.Option(None, "--output", "-o", help="Destination file or directory."),
):
    """Stub for Microsoft BASIC port build (not yet implemented)."""
    console.print(
        Panel.fit(
            "Microsoft BASIC build pipeline is not implemented yet. "
            "See compiler/README.md for current status and "
            "compiler/docs/microsoft-basic-port-plan.md for the detailed plan.",
            title="TODO",
        )
    )
    raise typer.Exit(code=2)


__all__ = ["app"]
