# Godot integration workspace

This folder is the reserved destination for generated Godot project adapters,
import profiles, shaders, scene manifests, runtime controllers, and headless
validation reports.

Generated Godot skills must:

- write only inside the run workspace or this project folder when explicitly
  approved;
- record the Godot version and renderer;
- keep imported assets and generated scripts in named subfolders;
- validate scene loading, shader parsing, resource paths, and screenshots;
- produce a project health manifest with hashes;
- provide mobile and fallback material paths for water, grass, hair, and glass;
- stop before modifying an unrelated existing project.

The intended pipeline is:

Blender/GLB export -> Godot import profile -> scene compiler -> shader/material
compiler -> runtime controller -> screenshot regression -> project health manifest

This workspace is deliberately engine-aware. Assets are not considered
Godot-ready merely because a GLB exists; import settings, node ownership,
materials, animation tracks, visibility/LOD behavior, and runtime screenshots
must also pass.
