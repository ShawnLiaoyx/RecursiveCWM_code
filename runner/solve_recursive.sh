#!/bin/bash
# 统一递归求解运行器:solve(node) 可生 solve(child),事件由运行器记录
# 用法: solve_recursive.sh <chain> <node> <parent_id|-> <depth> <run_id>
set -uo pipefail
# RCWM_CODE = this repo; RCWM_ROOT = runtime root (see docs/environment.md), default <repo>/runtime
CODE="${RCWM_CODE:-$(cd "$(dirname "$0")/.." && pwd)}"
ROOT="${RCWM_ROOT:-$CODE/runtime}"
cd "$ROOT"
CHAIN="$1"; NODE="$2"; PARENT="${3:--}"; DEPTH="${4:-0}"; RUN="${5:-r0}"
MAXD="${RCWM_MAXD:-4}"; MAXCYC="${RCWM_MAXCYC:-3}"
PROMPT="${RCWM_PROMPT:-$CODE/solver/solver-template.md}"
MODEL="${RCWM_MODEL:-gpt-6-astra}"; EFFORT="${RCWM_REASONING:-high}"   # the paper's model and reasoning effort; passed explicitly so codex's own config cannot change them
PWCACHE="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"   # headless Chromium lives here; codex needs write access to it
ND="$CHAIN/fractal/$NODE"
TR="$CHAIN/trace"; mkdir -p "$TR" "$ND"
EV="$TR/events.jsonl"
TPLH=$(sha256sum "$PROMPT" | cut -c1-12)   # hash of the instruction actually used (RCWM_PROMPT or the default)
CAMH=$([ -f "$CHAIN/camera-contract.json" ] && sha256sum "$CHAIN/camera-contract.json" | cut -c1-12 || echo none)
SNAP=$(git rev-parse --short HEAD 2>/dev/null || echo none)   # runtime root need not be a git repo

log_ev() { # type cycle extra_json
  printf '%s
' "{\"run_id\":\"$RUN\",\"node_id\":\"$NODE\",\"parent_id\":\"$PARENT\",\"depth\":$DEPTH,\"cycle\":$2,\"event\":\"$1\",\"ts\":\"$(date -Is)\",\"solver_hash\":\"$TPLH\",\"camera_hash\":\"$CAMH\",\"parent_snapshot\":\"$SNAP\"$3}" >> "$EV"
}

usage_delta() { # 最近一次 tokens used(codex 把数字印在同一行或下一行)
  grep -a -A1 "tokens used" "$ND/codex-run.log" 2>/dev/null | grep -o "[0-9][0-9,]*" | tail -1 | tr -d ','
}

# manifest:接口版本(继承的上下文)
[ -f "$ND/manifest.json" ] || cat > "$ND/manifest.json" <<M
{"interface_version":1,"reference_sha256":"$( [ -f "$ND/target.png" ] && sha256sum "$ND/target.png" | cut -c1-12 || echo pending)","camera_hash":"$CAMH","parent_snapshot":"$SNAP","solver_hash":"$TPLH"}
M

CYC=1
while [ "$CYC" -le "$MAXCYC" ]; do
  rm -f "$ND/children.json.consumed"
  [ -f "$ND/children.json" ] && mv "$ND/children.json" "$ND/children.json.prev"
  # Interruption recovery: a fresh invocation of a node that already has a session, no deliverable, and a
  # previous children request with undelivered children re-launches just those children (they resume by
  # their own .sid) instead of waking this node with an incomplete set.
  RECOVER=0
  if [ "$CYC" -eq 1 ] && [ -f "$ND/.sid" ] && [ ! -f "$ND/part.json" ] && [ -f "$ND/children.json.prev" ] && [ "$DEPTH" -lt "$MAXD" ]; then
    MISSING=$(python3 -c "import json,os; ks=json.load(open('$ND/children.json.prev')); print(json.dumps([k for k in ks if not os.path.exists('$CHAIN/fractal/'+k+'/part.json')]))" 2>/dev/null)
    if [ -n "$MISSING" ] && [ "$MISSING" != "[]" ]; then echo "$MISSING" > "$ND/children.json"; RECOVER=1; log_ev "recover_children" "$CYC" ",\"children\":$MISSING"; fi
  fi
  if [ "$RECOVER" = "1" ]; then :; else
  log_ev "session_start" "$CYC" ",\"model\":\"$MODEL\",\"reasoning\":\"$EFFORT\""
  sed "s#__NODE__#$NODE#g; s#__CHAIN__#$CHAIN#g; s#__DEPTH__#$DEPTH#g" \
      "$PROMPT" > "$ND/task.md"
  # At the maximum depth the runner will not launch children; the node must know, or it keeps writing children.json and never delivers.
  if [ "$DEPTH" -ge "$MAXD" ]; then
    if grep -q '[一-龥]' "$PROMPT"; then MAXNOTE="本层深度已到上限:运行器不会再执行孩子,不要写 children.json;把本层自己做完,交付 part.json。"
    else MAXNOTE="This level is at the maximum depth: the runner will not launch children, so do not write children.json; finish this level yourself and deliver part.json."; fi
    printf '\n%s\n' "$MAXNOTE" >> "$ND/task.md"
  else MAXNOTE=""; fi
  if [ -f "$ND/.sid" ] && grep -q "[0-9a-f]" "$ND/.sid"; then
    codex exec --skip-git-repo-check --cd "$ROOT" --sandbox workspace-write \
      -c "model=\"$MODEL\"" -c "model_reasoning_effort=\"$EFFORT\"" \
      -c sandbox_workspace_write.network_access=true \
      -c "sandbox_workspace_write.writable_roots=[\"$PWCACHE\"]" \
      resume "$(cat "$ND/.sid")" "Continue this level:$( [ -s "$ND/.children_done" ] && echo " children delivered:$(cat "$ND/.children_done"). Do the whole-again step: integrate the children, settle continuity and relations;" ) proceed per the protocol to write this level's part.json + account.md and finish; if more descent is needed, write a new children.json and end.${MAXNOTE:+ $MAXNOTE}" \
      < /dev/null >> "$ND/codex-run.log" 2>&1
  else
    codex exec --skip-git-repo-check --cd "$ROOT" --sandbox workspace-write \
      -c "model=\"$MODEL\"" -c "model_reasoning_effort=\"$EFFORT\"" \
      -c sandbox_workspace_write.network_access=true \
      -c "sandbox_workspace_write.writable_roots=[\"$PWCACHE\"]" \
      "$(cat "$ND/task.md")" < /dev/null >> "$ND/codex-run.log" 2>&1
    grep -m1 "session id" "$ND/codex-run.log" | awk '{print $3}' > "$ND/.sid"
  fi
  U=$(usage_delta); U=${U:-0}
  log_ev "session_end" "$CYC" ",\"usage_total\":$U"
  fi   # end of the codex call skipped by recovery

  # 孩子请求?
  KIDS=$([ -f "$ND/children.json" ] && python3 -c "import json;print(' '.join(json.load(open('$ND/children.json'))))" 2>/dev/null || echo "")
  if [ -n "$KIDS" ] && [ "$DEPTH" -lt "$MAXD" ]; then   # an empty list means "no children": finish, don't resume
    PIDS=""
    for K in $KIDS; do
      log_ev "child_call" "$CYC" ",\"child\":\"$K\""
      bash "$CODE"/runner/solve_recursive.sh "$CHAIN" "$K" "$NODE" "$((DEPTH+1))" "$RUN" &
      PIDS="$PIDS $!"
    done
    for P in $PIDS; do wait "$P"; done
    DONE=""
    for K in $KIDS; do
      [ -f "$CHAIN/fractal/$K/part.json" ] && DONE="$DONE $K"
      log_ev "child_return" "$CYC" ",\"child\":\"$K\",\"delivered\":$([ -f "$CHAIN/fractal/$K/part.json" ] && echo true || echo false)"
    done
    echo "$DONE" > "$ND/.children_done"
    CYC=$((CYC+1))
    continue
  fi
  break
done

# 运行器级交付校验(只查机器可判事实,不设仪式)
REASON="visual_stop"
if [ -f "$ND/part.json" ]; then
  python3 "$CODE"/runner/check_part.py "$ND/part.json" || REASON="invalid_artifact"
else
  REASON="no_artifact"
fi
log_ev "stop" "$CYC" ",\"stop_reason\":\"$REASON\""
