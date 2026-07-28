# NAZA Asset Foundry — reviewed codecell architecture

## Product surface

Run the dedicated Flutter entry point:

```bash
flutter run -t lib/asset_foundry_main.dart
```

The app contains five primary surfaces:

- **Generate:** prompt or image to GPT-designed Python codecells, GPT Image
  reference-sheet generation, rewrite instructions, review, and local execution.
- **Library:** database-backed generation plans and completion state.
- **History:** immutable execution summaries, code hashes, logs, sandbox mode,
  duration, and artifact manifests.
- **Inspired by:** the ten proposed geometry/rigging paradigms plus the PolyFlow
  continuous-topology lane, presented as research directions rather than
  unavailable production checkpoints.
- **Settings:** encrypted OpenAI key, model IDs, Responses endpoint, Python and
  Blender paths, loopback engine settings, and fail-closed bubblewrap mode.

## Human-in-the-loop execution contract

GPT-5.6 may write custom Python. It may not run that code directly.

1. GPT returns a strict JSON bundle with ordered code, declared capabilities,
   inputs, outputs, validation checks, architecture tags, and a risk summary.
2. Flutter calculates the cell SHA-256 and runs a local static scan.
3. A full-screen popup displays the entire code and every requested capability.
4. The human may remove capabilities, reject the cell, copy it for external
   inspection, or approve the exact hash.
5. Flutter records the approval in SQLite and sends code, hash, permissions, and
   approval metadata to the loopback Python engine.
6. The engine recalculates the hash, re-runs policy analysis, and refuses any
   mismatch or unapproved capability.
7. Artifacts are written only to the run output directory and returned with
   hashes, byte sizes, and MIME types.

A rewritten cell is a new artifact and always requires a new review.

## Database model

`asset_foundry.sqlite3` stores:

- generation plans and ordered codecell JSON,
- review decisions and exact approved hashes,
- execution status, sandbox mode, logs, and duration,
- artifact manifests,
- non-secret application settings.

The OpenAI API key is not stored in SQLite. It is encrypted independently with
AES-256-GCM. The random wrapping key lives in operating-system secure storage;
the authenticated ciphertext lives in the application-support directory.

## Notebook concepts carried forward

The Flutter/Python system generalizes the uploaded PolyFlow/RigFlow notebooks:

- deterministic seeded generation,
- procedural skeleton and surface construction,
- continuous position/normal/topology vertex state,
- graph and geodesic rig descriptors,
- bounded normalized skinning influences,
- NumPy and OpenCV image/PBR processing without Pillow,
- GPT Image reference and material-source generation,
- Blender armature, render, animation, GLB, and `.blend` workflows,
- topology, manifold, collision, deformation, LOD, and output validation,
- previews, manifests, checksums, ZIP packaging, and bundle mapping.

## Practical interpretation of the advanced architectures

The app tells GPT to use real local approximations when trained model weights do
not exist. Examples include rotation-covariant frame transports for the gauge
lane, splat/SDF proxy fields, coupled velocity and surface-node optimization,
dual mesh/rig graphs, XPBD-inspired penalties, wavelet detail bands, optimized
control cages, energy-regularized trajectories, multiview silhouette fitting,
and procedural CSG grammars. Generated manifests must distinguish procedural,
optimization-based, pretrained, and speculative components.
