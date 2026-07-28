"""Execution runtime for reviewed asset codecells."""
from __future__ import annotations

import base64
import hashlib
import json
import mimetypes
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

try:
    from .policy import Finding, PolicyError, enforce
except ImportError:  # direct script execution
    from policy import Finding, PolicyError, enforce


SAFE_FILE_NAME = re.compile(r"[^A-Za-z0-9._-]+")


@dataclass(frozen=True)
class Artifact:
    relativePath: str
    sha256: str
    bytes: int
    mimeType: str

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class ExecutionResult:
    ok: bool
    runId: str
    cellId: str
    exitCode: int
    stdout: str
    stderr: str
    sandboxMode: str
    artifacts: list[dict[str, object]]
    policyFindings: list[str]
    durationMs: int

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


class ExecutionRejected(ValueError):
    pass


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(value: str) -> str:
    return sha256_bytes(value.encode("utf-8"))


def _safe_segment(value: str, fallback: str) -> str:
    cleaned = SAFE_FILE_NAME.sub("_", value).strip("._")
    return cleaned[:96] or fallback


def _write_inputs(input_dir: Path, values: dict[str, str]) -> None:
    for original_name, encoded in values.items():
        name = _safe_segment(str(original_name), "input.bin")
        data = base64.b64decode(encoded, validate=True)
        if len(data) > 32 * 1024 * 1024:
            raise ExecutionRejected(f"Input file {name} exceeds 32 MiB.")
        (input_dir / name).write_bytes(data)


def _bootstrap_source(
    permissions: set[str],
    blender_executable: str,
) -> str:
    permission_json = json.dumps(sorted(permissions))
    blender_json = json.dumps(blender_executable)
    return f'''from __future__ import annotations
import builtins
import json
import os
import pathlib
import subprocess
import sys

WORKSPACE = pathlib.Path(__file__).resolve().parent
INPUT_DIR = WORKSPACE / "inputs"
OUTPUT_DIR = WORKSPACE / "outputs"
CACHE_DIR = WORKSPACE / "cache"
ASSET_CONTEXT = json.loads((WORKSPACE / "asset_context.json").read_text(encoding="utf-8"))
BLENDER_EXECUTABLE = {blender_json}
APPROVED_PERMISSIONS = set({permission_json})

for directory in (
    INPUT_DIR, OUTPUT_DIR, CACHE_DIR,
    WORKSPACE / "build", WORKSPACE / "scripts", WORKSPACE / "textures",
    WORKSPACE / "reports", WORKSPACE / "previews", WORKSPACE / "exports",
    WORKSPACE / "validation_screenshots",
):
    directory.mkdir(parents=True, exist_ok=True)

_workspace = WORKSPACE.resolve()
_sensitive = (
    "/.ssh/", "/.aws/", "/.config/gcloud/", "/.kube/", "/etc/shadow",
    "/etc/sudoers", "/proc/self/environ", "appdata/roaming/microsoft/credentials",
)

def _resolved(value):
    try:
        return pathlib.Path(value).expanduser().resolve()
    except Exception:
        return None

def _inside(path):
    return path == _workspace or _workspace in path.parents

def _audit(event, args):
    if event == "open" and args:
        path = _resolved(args[0]) if isinstance(args[0], (str, bytes, os.PathLike)) else None
        mode = args[1] if len(args) > 1 and isinstance(args[1], str) else "r"
        if path is not None:
            normalized = str(path).lower().replace("\\\\", "/")
            if any(fragment in normalized for fragment in _sensitive):
                raise PermissionError(f"Sensitive host path blocked: {{path}}")
            writing = any(flag in mode for flag in "wax+")
            if writing and not _inside(path):
                raise PermissionError(f"Write outside workspace blocked: {{path}}")
    elif event in {{"os.remove", "os.rmdir", "os.rename", "os.replace", "os.chdir"}}:
        for value in args[:2]:
            if isinstance(value, (str, bytes, os.PathLike)):
                path = _resolved(value)
                if path is not None and not _inside(path):
                    raise PermissionError(f"Filesystem mutation outside workspace blocked: {{path}}")
    elif event.startswith("socket.") and "network" not in APPROVED_PERMISSIONS:
        raise PermissionError("Network access was not approved.")
    elif event == "subprocess.Popen":
        if "spawnSubprocess" not in APPROVED_PERMISSIONS:
            raise PermissionError("Subprocess execution was not approved.")
        executable = str(args[0]) if args else ""
        base = pathlib.Path(executable).name.lower()
        allowed = {{
            pathlib.Path(BLENDER_EXECUTABLE).name.lower(), "blender", "ffmpeg",
            pathlib.Path(sys.executable).name.lower(), "python", "python3",
        }}
        if base not in allowed:
            raise PermissionError(f"Subprocess executable is not approved: {{executable}}")

sys.addaudithook(_audit)

cell_path = WORKSPACE / "reviewed_cell.py"
source = cell_path.read_text(encoding="utf-8")
code = compile(source, str(cell_path), "exec", dont_inherit=True)
globals_dict = {{
    "__name__": "__asset_codecell__",
    "__file__": str(cell_path),
    "WORKSPACE": WORKSPACE,
    "INPUT_DIR": INPUT_DIR,
    "OUTPUT_DIR": OUTPUT_DIR,
    "CACHE_DIR": CACHE_DIR,
    "SCREENSHOT_DIR": WORKSPACE / "validation_screenshots",
    "ASSET_CONTEXT": ASSET_CONTEXT,
    "BLENDER_EXECUTABLE": BLENDER_EXECUTABLE,
    "APPROVED_PERMISSIONS": frozenset(APPROVED_PERMISSIONS),
}}
exec(code, globals_dict, globals_dict)
'''


def _preexec(timeout_seconds: int):
    if os.name != "posix":
        return None

    def apply_limits() -> None:
        import resource

        memory = int(os.environ.get("ASSET_FOUNDRY_MEMORY_BYTES", str(8 * 1024**3)))
        file_bytes = int(os.environ.get("ASSET_FOUNDRY_FILE_BYTES", str(4 * 1024**3)))
        resource.setrlimit(resource.RLIMIT_CPU, (timeout_seconds + 5, timeout_seconds + 15))
        resource.setrlimit(resource.RLIMIT_FSIZE, (file_bytes, file_bytes))
        resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))
        if platform.system() != "Darwin":
            resource.setrlimit(resource.RLIMIT_AS, (memory, memory))
        os.setsid()

    return apply_limits


def _command(
    run_dir: Path,
    permissions: set[str],
    require_bwrap: bool,
) -> tuple[list[str], str]:
    python = Path(sys.executable).resolve()
    bwrap = shutil.which("bwrap") if os.name == "posix" else None
    if bwrap:
        command = [
            bwrap,
            "--die-with-parent",
            "--new-session",
            "--ro-bind",
            "/",
            "/",
            "--bind",
            str(run_dir),
            str(run_dir),
            "--tmpfs",
            "/tmp",
            "--proc",
            "/proc",
            "--dev",
            "/dev",
            "--chdir",
            str(run_dir),
        ]
        if "network" not in permissions:
            command.append("--unshare-net")
        command.extend([str(python), str(run_dir / "bootstrap.py")])
        return command, "bubblewrap"
    if require_bwrap:
        raise ExecutionRejected(
            "bubblewrap is required by Settings but bwrap was not found on PATH."
        )
    return [str(python), str(run_dir / "bootstrap.py")], "process-fallback"


def _adapt_blender_engine(code: str, blender_executable: str) -> tuple[str, str]:
    """Adapt generated Blender engine names to the installed Blender version."""
    notes: list[str] = []
    adapted = code
    if "scene.world.color" in adapted:
        lines: list[str] = []
        for line in adapted.splitlines(keepends=True):
            if re.match(r"^\s*scene\.world\.color\s*=", line):
                indent = line[: len(line) - len(line.lstrip())]
                lines.append(
                    f'{indent}if scene.world is None: '
                    'scene.world = bpy.data.worlds.new("World")\n'
                )
            lines.append(line)
        adapted = "".join(lines)
        notes.append("Compatibility guard: created a missing Blender scene World.")
    if "BLENDER_EEVEE_NEXT" not in adapted:
        return adapted, " ".join(notes)
    executable = shutil.which(blender_executable) or blender_executable
    try:
        version = subprocess.run(
            [executable, "--version"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        ).stdout
        match = re.search(r"Blender\s+(\d+)", version)
    except (OSError, subprocess.SubprocessError):
        match = None
    if match is not None and int(match.group(1)) < 4:
        adapted = adapted.replace("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE")
        notes.append(
            "Compatibility rewrite: BLENDER_EEVEE_NEXT -> BLENDER_EEVEE for Blender < 4.0."
        )
        # Blender 3.x can fail with EGL_BAD_MATCH when Eevee renders several
        # views in one headless process. Use Workbench only for preview cells;
        # production/export cells continue to use Eevee.
        if "views = {" in adapted and "bpy.ops.render.render" in adapted:
            adapted = adapted.replace(
                "scene.render.engine = 'BLENDER_EEVEE'",
                "scene.render.engine = 'BLENDER_WORKBENCH'",
            )
            notes.append(
                "Preview fallback: BLENDER_WORKBENCH used for multi-view rendering on Blender < 4.0."
            )
    return adapted, " ".join(notes)


_CONTROL_FILES = {
    "asset_context.json",
    "bootstrap.py",
    "reviewed_cell.py",
}


def _artifacts(run_dir: Path) -> list[dict[str, object]]:
    """Collect generated workspace files, not just the legacy outputs folder.

    Cells are given WORKSPACE and commonly write to declared folders such as
    build/, reports/, textures/, previews/, and exports/. The old collector
    searched only WORKSPACE/outputs, which incorrectly reported successful
    cells as producing zero artifacts.
    """
    results: list[dict[str, object]] = []
    if not run_dir.exists():
        return results
    ignored_directories = {"inputs", "cache", "__pycache__"}
    ignored_prefixes = ("approval_", "result_")
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        relative_path = path.relative_to(run_dir)
        if relative_path.parts[0] in ignored_directories:
            continue
        if path.name in _CONTROL_FILES or path.name.startswith(ignored_prefixes):
            continue
        relative = relative_path.as_posix()
        data_hash = hashlib.sha256()
        size = 0
        with path.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                data_hash.update(chunk)
                size += len(chunk)
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        results.append(
            Artifact(relative, data_hash.hexdigest(), size, mime).to_dict()
        )
    return results


def execute(payload: dict[str, Any], root: Path) -> ExecutionResult:
    plan_id = _safe_segment(str(payload.get("planId", "")), "plan")
    run_id = _safe_segment(str(payload.get("runId", "")), "run")
    cell_id = _safe_segment(str(payload.get("cellId", "")), "cell")
    code = str(payload.get("code", ""))
    submitted_hash = str(payload.get("codeSha256", ""))
    approval = payload.get("humanApproval")
    if not isinstance(approval, dict) or approval.get("approved") is not True:
        raise ExecutionRejected("A human approval object is required.")
    approved_hash = str(approval.get("approvedSha256", ""))
    actual_hash = sha256_text(code)
    if not submitted_hash or submitted_hash != actual_hash or approved_hash != actual_hash:
        raise ExecutionRejected(
            "The submitted code does not match the exact SHA-256 hash approved by the human reviewer."
        )
    permissions = {
        str(value) for value in approval.get("allowedPermissions", [])
    }
    policy_findings = enforce(code, permissions)

    timeout_seconds = int(payload.get("timeoutSeconds", 600))
    timeout_seconds = max(10, min(7200, timeout_seconds))
    run_dir = (root / plan_id / run_id).resolve()
    root_resolved = root.resolve()
    if root_resolved not in run_dir.parents:
        raise ExecutionRejected("Invalid run path.")
    input_dir = run_dir / "inputs"
    output_dir = run_dir / "outputs"
    cache_dir = run_dir / "cache"
    for directory in (input_dir, output_dir, cache_dir):
        directory.mkdir(parents=True, exist_ok=True)

    input_files = payload.get("inputFiles") or {}
    if not isinstance(input_files, dict):
        raise ExecutionRejected("inputFiles must be an object.")
    _write_inputs(input_dir, {str(k): str(v) for k, v in input_files.items()})

    context = payload.get("assetContext") or {}
    if not isinstance(context, dict):
        raise ExecutionRejected("assetContext must be an object.")
    (run_dir / "asset_context.json").write_text(
        json.dumps(context, indent=2, sort_keys=True), encoding="utf-8"
    )
    blender = os.environ.get("ASSET_FOUNDRY_BLENDER", "blender")
    execution_code, compatibility_note = _adapt_blender_engine(code, blender)
    (run_dir / "reviewed_cell.py").write_text(execution_code, encoding="utf-8")
    (run_dir / "bootstrap.py").write_text(
        _bootstrap_source(permissions, blender), encoding="utf-8"
    )
    approval_record = {
        "planId": plan_id,
        "runId": run_id,
        "cellId": cell_id,
        "codeSha256": actual_hash,
        "allowedPermissions": sorted(permissions),
        "reviewerNote": str(approval.get("reviewerNote", "")),
        "approvedAt": str(approval.get("approvedAt", "")),
    }
    (run_dir / f"approval_{cell_id}.json").write_text(
        json.dumps(approval_record, indent=2, sort_keys=True), encoding="utf-8"
    )

    require_bwrap = os.environ.get("ASSET_FOUNDRY_REQUIRE_BWRAP") == "1"
    command, sandbox_mode = _command(run_dir, permissions, require_bwrap)
    environment = {
        "PATH": os.environ.get("PATH", ""),
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "LC_ALL": os.environ.get("LC_ALL", "C.UTF-8"),
        "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
        "PYTHONHASHSEED": str(context.get("seed", 0)),
        "ASSET_FOUNDRY_WORKSPACE": str(run_dir),
        "ASSET_FOUNDRY_BLENDER": blender,
        # Blender is often launched headlessly from a reviewed cell. Keep its
        # child render process on CPU Mesa/EGL too, especially on Linux VMs.
        "LIBGL_ALWAYS_SOFTWARE": "true",
        "GALLIUM_DRIVER": "llvmpipe",
        "MESA_LOADER_DRIVER_OVERRIDE": "llvmpipe",
        "LIBGL_DRI3_DISABLE": "true",
        "EGL_PLATFORM": "x11" if os.environ.get("DISPLAY") else "surfaceless",
    }
    # Preserve the active desktop display for Blender previews. Without this,
    # Blender falls back to surfaceless EGL even when Flutter is running under
    # X11, and Blender 3.x can fail on the second render in that mode.
    for display_variable in ("DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY"):
        value = os.environ.get(display_variable)
        if display_variable == "XAUTHORITY" and not value:
            default_xauthority = Path.home() / ".Xauthority"
            if default_xauthority.exists():
                value = str(default_xauthority)
        if value:
            environment[display_variable] = value
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            cwd=run_dir,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout_seconds,
            preexec_fn=_preexec(timeout_seconds),
            check=False,
        )
        exit_code = completed.returncode
        stdout = completed.stdout[-2_000_000:]
        stderr = completed.stderr[-2_000_000:]
    except subprocess.TimeoutExpired as exc:
        exit_code = 124
        stdout = (exc.stdout or "")[-2_000_000:]
        stderr = ((exc.stderr or "") + f"\nCell timed out after {timeout_seconds}s.")[-2_000_000:]
    if compatibility_note:
        stderr = f"[asset-engine] {compatibility_note}\n{stderr}"
    if exit_code != 0:
        preview_log = run_dir / "reports" / "preview_stdout.txt"
        if preview_log.exists():
            diagnostic = preview_log.read_text(encoding="utf-8", errors="replace")[-20_000:]
            stderr = f"{stderr}\n[asset-engine] Blender diagnostic report:\n{diagnostic}"
    duration_ms = int((time.monotonic() - started) * 1000)
    artifacts = _artifacts(run_dir)
    result = ExecutionResult(
        ok=exit_code == 0,
        runId=run_id,
        cellId=cell_id,
        exitCode=exit_code,
        stdout=stdout,
        stderr=stderr,
        sandboxMode=sandbox_mode,
        artifacts=artifacts,
        policyFindings=[finding.message for finding in policy_findings],
        durationMs=duration_ms,
    )
    (run_dir / f"result_{cell_id}.json").write_text(
        json.dumps(result.to_dict(), indent=2, sort_keys=True), encoding="utf-8"
    )
    return result
