from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from .policy import PolicyError, analyze, enforce
from .runner import ExecutionRejected, execute


class PolicyTests(unittest.TestCase):
    def test_allows_numpy_workspace_cell(self) -> None:
        code = """
from pathlib import Path
import numpy as np
values = np.arange(9).reshape(3, 3)
(OUTPUT_DIR / 'matrix.json').write_text(str(values.tolist()), encoding='utf-8')
"""
        findings = enforce(code, {"useNumpy", "writeWorkspace"})
        self.assertFalse(any(f.severity == "block" for f in findings))

    def test_blocks_dynamic_exec(self) -> None:
        with self.assertRaises(PolicyError):
            enforce("exec('print(1)')", {"writeWorkspace"})

    def test_subprocess_requires_permission(self) -> None:
        findings = analyze(
            "import subprocess\nsubprocess.run(['blender'])\nOUTPUT_DIR.mkdir(exist_ok=True)",
            {"writeWorkspace"},
        )
        self.assertTrue(any(f.rule in {"import", "subprocess_permission"} and f.severity == "block" for f in findings))

    def test_exact_hash_approval_is_required(self) -> None:
        code = "(OUTPUT_DIR / 'ok.txt').write_text('ok', encoding='utf-8')"
        digest = hashlib.sha256(code.encode()).hexdigest()
        payload = {
            "planId": "plan",
            "runId": "run",
            "cellId": "cell",
            "code": code,
            "codeSha256": digest,
            "humanApproval": {
                "approved": True,
                "approvedSha256": "0" * 64,
                "allowedPermissions": ["writeWorkspace"],
            },
            "assetContext": {"seed": 1},
        }
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ExecutionRejected):
                execute(payload, Path(temp))


if __name__ == "__main__":
    unittest.main()
