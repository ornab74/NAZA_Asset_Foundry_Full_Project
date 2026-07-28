# Orca Godot Import

- Import `orca_godot.glb` as a scene with animation and skin import enabled.
- `Orca_Rig` is shared by LOD0 through LOD3.
- Mesh node names contain `LOD0`, `LOD1`, `LOD2`, or `LOD3`; switch visibility by distance in a Godot script or editor setup.
- Suggested distance bands in meters: LOD0 0-18, LOD1 18-38, LOD2 38-75, LOD3 75+.
- `Orca-col` is the low-resolution collision helper.
- Actions: `SwimLoop` and `BiteLoop`.
- Blender source remains editable in `orca_production.blend`.
- Blender +X is the authored swimming direction; glTF export applies Y-up conversion.
