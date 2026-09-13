#!/bin/bash
# make_codex_home.sh <workspace-root> [en|zh] : build a private codex home at <workspace-root>/.codex-home holding only
# a two-line config.toml (the paper's model and reasoning effort: RCWM_MODEL / RCWM_REASONING, default gpt-6-astra / high;
# or the file RCWM_CODEX_CONFIG for a custom provider), a copy of codex's login file (auth.json, mode 600 — never share
# or commit it) and this repo's worldgen-techniques skill in the chosen language. Launch with CODEX_HOME=<that dir>.
# (rcwm.sh does the same by default; this script is for launching the runner directly.)
set -euo pipefail
R="$(cd "${1:?usage: make_codex_home.sh <workspace-root> [en|zh]}" && pwd)"; LANG_="${2:-en}"
CODE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="${CODEX_HOME:-$HOME/.codex}"; CH="$R/.codex-home"
[ -f "$SRC/auth.json" ] || { echo "no codex login at $SRC/auth.json (run 'codex login' first)"; exit 1; }
mkdir -p "$CH/skills/worldgen-techniques" && chmod 700 "$CH"
if [ -n "${RCWM_CODEX_CONFIG:-}" ]; then cp "$RCWM_CODEX_CONFIG" "$CH/config.toml"
else printf 'model = "%s"\nmodel_reasoning_effort = "%s"\n' "${RCWM_MODEL:-gpt-6-astra}" "${RCWM_REASONING:-high}" > "$CH/config.toml"; fi
cp "$SRC/auth.json" "$CH/" && chmod 600 "$CH/auth.json"
rm -f "$CH/skills/worldgen-techniques"/*
if [ "$LANG_" = zh ]; then cp "$CODE/skills/worldgen-techniques/SKILL.zh.md" "$CH/skills/worldgen-techniques/SKILL.md"
else cp "$CODE/skills/worldgen-techniques/SKILL.md" "$CH/skills/worldgen-techniques/SKILL.md"; fi
echo "$CH"
