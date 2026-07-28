# NAZA Asset Foundry local engine

This loopback-only Python service executes GPT-generated asset codecells after a
human reviews the complete source and approves the exact SHA-256 hash.

## Install

```bash
python3 -m venv .asset-foundry-venv
source .asset-foundry-venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r asset_engine/requirements.txt
```

Install Blender separately and make `blender` available on `PATH`. On Linux,
install `bubblewrap` for the preferred sandbox:

```bash
sudo apt-get install blender bubblewrap ffmpeg
```

The engine detects the installed Blender major version before running a
reviewed cell. If a generated cell requests Blender 4's
`BLENDER_EEVEE_NEXT` engine but Blender 3.x is installed, the backend rewrites
that engine name to Blender 3's `BLENDER_EEVEE` and records the compatibility
rewrite in stderr. Blender 4.x requests are left unchanged.

## Run manually

```bash
export ASSET_FOUNDRY_ENGINE_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
python asset_engine/server.py --host 127.0.0.1 --port 47896
```

The Flutter app normally starts the service itself and passes a fresh token in
an environment variable. The server refuses non-loopback bindings.

## Security boundary

The engine layers:

1. exact-hash human approval,
2. AST policy checks,
3. permission-scoped imports and subprocess/network checks,
4. a fresh per-run workspace,
5. Python audit-hook restrictions,
6. CPU, memory, file-size, and descriptor limits on POSIX,
7. a stripped child environment,
8. bubblewrap with an unshared network namespace when available.

The plain-process fallback is compatibility containment, not a complete hostile
code sandbox. Turn on **Require bubblewrap sandbox** in Settings to fail closed.
For stronger isolation, run the engine in a dedicated VM or container with no
personal files mounted.
