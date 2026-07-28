"""Static policy for human-approved GPT-generated asset codecells.

This module is deliberately conservative. Passing the scanner does not make
arbitrary Python safe; the runner also uses a fresh workspace, an audit hook,
resource limits, a stripped environment, and bubblewrap when available.
"""
from __future__ import annotations

import ast
from dataclasses import dataclass, asdict
from typing import Iterable


PERMISSIONS = {
    "readInputs",
    "writeWorkspace",
    "useNumpy",
    "useOpenCv",
    "useTrimesh",
    "invokeBlender",
    "spawnSubprocess",
    "network",
}

BASE_IMPORTS = {
    "base64",
    "collections",
    "csv",
    "dataclasses",
    "functools",
    "hashlib",
    "heapq",
    "itertools",
    "json",
    "math",
    "operator",
    "os",
    "pathlib",
    "random",
    "re",
    "shutil",
    "statistics",
    "struct",
    "sys",
    "tempfile",
    "textwrap",
    "time",
    "typing",
    "uuid",
    "zipfile",
}

PERMISSION_IMPORTS = {
    "useNumpy": {"numpy"},
    "useOpenCv": {"cv2"},
    "useTrimesh": {"trimesh", "networkx"},
    "spawnSubprocess": {"subprocess"},
    "network": {"socket", "ssl", "urllib", "http", "requests", "httpx"},
}

BLOCKED_NAMES = {
    "eval",
    "exec",
    "compile",
    "__import__",
    "breakpoint",
    "help",
    "input",
}

BLOCKED_ROOT_MODULES = {
    "ctypes",
    "marshal",
    "pickle",
    "shelve",
    "site",
    "importlib",
    "multiprocessing",
    "pty",
    "resource",
    "runpy",
}

BLOCKED_CALLS = {
    "os.system",
    "os.popen",
    "os.spawnl",
    "os.spawnle",
    "os.spawnlp",
    "os.spawnlpe",
    "os.spawnv",
    "os.spawnve",
    "os.spawnvp",
    "os.spawnvpe",
    "shutil.rmtree",
}

SENSITIVE_PATH_FRAGMENTS = {
    "/.ssh/",
    "/.aws/",
    "/.config/gcloud/",
    "/.kube/",
    "/etc/shadow",
    "/etc/sudoers",
    "/proc/self/environ",
    "appdata\\roaming\\microsoft\\credentials",
}


@dataclass(frozen=True)
class Finding:
    severity: str
    rule: str
    message: str
    line: int = 0
    column: int = 0

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


class PolicyError(ValueError):
    def __init__(self, findings: Iterable[Finding]):
        self.findings = tuple(findings)
        super().__init__("; ".join(f.message for f in self.findings))


def _qualified_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        root = _qualified_name(node.value)
        return f"{root}.{node.attr}" if root else node.attr
    return None


def _allowed_imports(permissions: set[str]) -> set[str]:
    allowed = set(BASE_IMPORTS)
    for permission, modules in PERMISSION_IMPORTS.items():
        if permission in permissions:
            allowed.update(modules)
    return allowed


def analyze(code: str, permissions: Iterable[str]) -> list[Finding]:
    selected = set(permissions)
    findings: list[Finding] = []
    unknown = sorted(selected - PERMISSIONS)
    for permission in unknown:
        findings.append(
            Finding("block", "unknown_permission", f"Unknown permission: {permission}")
        )

    if not code.strip():
        return findings + [Finding("block", "empty_cell", "The codecell is empty.")]
    if len(code) > 120_000:
        findings.append(
            Finding(
                "block",
                "cell_size",
                "A single codecell may not exceed 120,000 characters.",
            )
        )

    try:
        tree = ast.parse(code, mode="exec", type_comments=True)
    except SyntaxError as exc:
        findings.append(
            Finding(
                "block",
                "syntax",
                exc.msg,
                exc.lineno or 0,
                exc.offset or 0,
            )
        )
        return findings

    allowed_imports = _allowed_imports(selected)
    for node in ast.walk(tree):
        line = getattr(node, "lineno", 0)
        column = getattr(node, "col_offset", 0)

        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".", 1)[0]
                if root in BLOCKED_ROOT_MODULES or root not in allowed_imports:
                    findings.append(
                        Finding(
                            "block",
                            "import",
                            f"Import is not allowed by the approved capability set: {alias.name}",
                            line,
                            column,
                        )
                    )
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                findings.append(
                    Finding(
                        "block",
                        "relative_import",
                        "Relative imports are not allowed in generated codecells.",
                        line,
                        column,
                    )
                )
                continue
            root = (node.module or "").split(".", 1)[0]
            if root in BLOCKED_ROOT_MODULES or root not in allowed_imports:
                findings.append(
                    Finding(
                        "block",
                        "import",
                        f"Import is not allowed by the approved capability set: {node.module}",
                        line,
                        column,
                    )
                )
        elif isinstance(node, ast.Name) and node.id in BLOCKED_NAMES:
            findings.append(
                Finding(
                    "block",
                    "dynamic_execution",
                    f"{node.id} is not allowed in generated codecells.",
                    line,
                    column,
                )
            )
        elif isinstance(node, ast.Attribute) and node.attr.startswith("__"):
            findings.append(
                Finding(
                    "block",
                    "dunder_access",
                    "Dunder attribute access is not allowed.",
                    line,
                    column,
                )
            )
        elif isinstance(node, ast.Call):
            name = _qualified_name(node.func)
            if name in BLOCKED_CALLS:
                findings.append(
                    Finding(
                        "block",
                        "dangerous_call",
                        f"{name} is not allowed.",
                        line,
                        column,
                    )
                )
            if name and name.startswith("subprocess.") and "spawnSubprocess" not in selected:
                findings.append(
                    Finding(
                        "block",
                        "subprocess_permission",
                        "Subprocess use was not approved by the human reviewer.",
                        line,
                        column,
                    )
                )
            if name and (
                name.startswith("socket.")
                or name.startswith("requests.")
                or name.startswith("httpx.")
                or name.startswith("urllib.")
            ) and "network" not in selected:
                findings.append(
                    Finding(
                        "block",
                        "network_permission",
                        "Network use was not approved by the human reviewer.",
                        line,
                        column,
                    )
                )
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            lowered = node.value.lower().replace("\\", "/")
            for fragment in SENSITIVE_PATH_FRAGMENTS:
                if fragment.replace("\\", "/") in lowered:
                    findings.append(
                        Finding(
                            "block",
                            "sensitive_path",
                            f"A string literal references a sensitive host path: {fragment}",
                            line,
                            column,
                        )
                    )

    if "WORKSPACE" not in code and "OUTPUT_DIR" not in code:
        findings.append(
            Finding(
                "review",
                "workspace_contract",
                "The cell does not visibly use WORKSPACE or OUTPUT_DIR.",
            )
        )
    return findings


def enforce(code: str, permissions: Iterable[str]) -> list[Finding]:
    findings = analyze(code, permissions)
    blocking = [finding for finding in findings if finding.severity == "block"]
    if blocking:
        raise PolicyError(blocking)
    return findings
