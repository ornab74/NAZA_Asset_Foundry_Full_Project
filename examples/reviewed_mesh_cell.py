"""Example only. The app still requires human approval before execution."""
from pathlib import Path
import json
import numpy as np

seed = int(ASSET_CONTEXT.get('seed', 0))
rng = np.random.default_rng(seed)
vertices = rng.normal(size=(128, 3)).astype(np.float32)
vertices /= np.maximum(np.linalg.norm(vertices, axis=1, keepdims=True), 1e-6)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
(OUTPUT_DIR / 'example_vertices.json').write_text(
    json.dumps({'vertices': vertices.tolist()}, indent=2),
    encoding='utf-8',
)
