# Runtime environment (RCWM_ROOT layout)

Every solver session is pointed at a runtime root (env `RCWM_ROOT`, default `<repo>/runtime`). It holds four things:

```
$RCWM_ROOT/
  .venv/bin/python                         # CPython 3.12.x with Pillow and numpy (side-by-sides, crops, diffs)
  .render-tools/node/bin/node              # Node.js 22
  .render-tools/node_modules/three/        # three.js 0.160.1 (build/three.module.js)
  .render-tools/node_modules/playwright/   # Playwright 1.62.1 with headless Chromium (renders, screenshots)
  runs/<run-name>/                         # one directory per run; the runner creates it
```

`setup/setup_runtime.sh <dir>` builds exactly this (plus a smoke render) without touching the Python environment you
are in: `.venv` is a private venv made from `python3.12` when available, otherwise `python3` (`--python <interpreter>` to choose), or, with `--conda <env>`, a
symlink to a dedicated conda env (created with python=3.12 if missing). Add `--metrics` to also install the packages the
record-only metrics, tables and figures need (torch CPU, opencv, scikit-image, lpips, open_clip); those are never seen
by the solver. `--node-from <dir>` symlinks an existing Node.js installation instead of downloading one.

Headless Chromium lives in `$PLAYWRIGHT_BROWSERS_PATH` (default `~/.cache/ms-playwright`). The runner grants codex write
access to that directory (Playwright touches it), so set the variable before launching if you moved the browsers.

Shell setup a solver session uses:

```bash
cd $RCWM_ROOT
export PATH="$RCWM_ROOT/.render-tools/node/bin:$PATH"
# three:      $RCWM_ROOT/.render-tools/node_modules/three/build/three.module.js
# playwright: $RCWM_ROOT/.render-tools/node_modules/playwright  (Chromium in $PLAYWRIGHT_BROWSERS_PATH or ~/.cache/ms-playwright)
```

Recommended render size 1400×900. Each run keeps its own `camera-contract.json` at the run root.
Nothing else is required: the scene programs the solver writes import three.js directly and drive Playwright themselves.

## Python compatibility

The supported interpreter for both the runtime and `--metrics` is **CPython 3.12.x**.
[`.python-version`](../.python-version) is the setup script's source of truth for the version check,
default interpreter lookup, and new conda environments. Any 3.12 patch release is accepted.
The pins remain the paper's versions:

| Package | Python constraint for the pinned release |
|---|---|
| [numpy 2.5.2](https://pypi.org/project/numpy/2.5.2/) | Requires Python >=3.12 |
| [Pillow 12.3.0](https://pypi.org/project/pillow/12.3.0/) | Requires Python >=3.10 |
| [torch 2.5.1 / torchvision 0.20.1](https://pypi.org/project/torchvision/0.20.1/) | The supported pair covers Python 3.9–3.12 |
| [scikit-image 0.26.0](https://pypi.org/project/scikit-image/0.26.0/) | Requires Python >=3.11 |
| Other metrics/test pins | Permit Python 3.12 |

The previous 3.10–3.12 claim was incompatible with the NumPy pin. Python 3.13+ is outside the
supported range of the pinned torch/torchvision pair. Use 3.12 for the base runtime too so that
adding `--metrics` later uses the same environment. Setup resolves runtime and metrics requirements
together and runs `pip check` before installing the rendering tools.

For a new venv, setup honors `--python`, then `PYTHON`; otherwise it tries `python3.12` on PATH,
then checks `python3`. With `--conda`, it creates a missing environment with Python 3.12 or validates
the existing one before linking it. An incompatible interpreter fails before packages are installed.

**Recovering from an earlier failed setup:** an existing `.venv` is reused and checked, even if
`--python` is supplied. Choose a fresh runtime directory or move the old `.venv` aside first, then run:

```bash
bash setup/setup_runtime.sh "$RCWM_ROOT" --python /path/to/python3.12
# Or let conda/mamba create a dedicated Python 3.12 environment:
bash setup/setup_runtime.sh "$RCWM_ROOT" --conda rcwm-py312
```

Moving a `.venv` symlink leaves its original conda environment intact. An existing conda environment
with the wrong Python version is rejected; choose a new environment name. Setup does not change its
Python version automatically.

## One runtime, many isolated workspaces

A workspace is any directory with this layout. `tools/new_workspace.sh <dir> <runtime>` creates one whose `.venv` and
`.render-tools` are symlinks to a runtime built once, with its own `runs/` and its own private `.codex-home` (the default
of `rcwm.sh`). Running each scene in its own workspace keeps sessions of different scenes from seeing each other's files;
the paper's final batch was run that way, one workspace per scene, all ten in parallel.

## What the paper's runs used

| piece | version |
|---|---|
| executor | `codex` CLI 0.153.0 (0.154 verified compatible), model `gpt-6-astra`, reasoning effort `high` |
| Python | 3.12.3; Pillow 12.3.0, numpy 2.5.2 |
| Node.js | 22.14.0; three 0.160.1; Playwright 1.62.1 (Chromium build 1234) |
| metrics only | torch 2.5.1 (CPU), opencv-python-headless 5.0, scikit-image 0.26, lpips 0.1.4, open_clip_torch 3.3 |
| OS | Linux x86_64 (Ubuntu, kernel 6.8) |
