#!/bin/bash
# img2threejs 原生基线,隔离工作区版(用户 2026-09-09 裁定):
#   每景一个独立目录 $RCWM_I2T_ISO/<scene>/,里面只有 img2threejs 的拷贝、参考图、渲染工具位置说明;
#   codex 的 cwd 就是这个目录,看不到我们的 runs/;提示词只说"按它自家规程做",不提场景/单物体,不给任何额外辅助。
#   唯一允许的干预:它的门禁拒收/硬停之后,续同一会话强行让它做完(第二段),仍不给提示。
# 用法: run_img2threejs.sh <scene> <reference.png>
set -uo pipefail
SC="$1"; REF="${2:?reference png}"
ROOT="${RCWM_ROOT:?set RCWM_ROOT (runtime root, see docs/environment.md)}"
ISO="${RCWM_I2T_ISO:?set RCWM_I2T_ISO (directory for the isolated img2threejs runs)}"
D="$ISO/$SC"
if [ -d "$D" ]; then echo "exists: $D (rename it first)"; exit 1; fi
mkdir -p "$D"
cp -r "$ROOT/vendor/img2threejs" "$D/img2threejs"
cp "$REF" "$D/reference.png"
cat > "$D/ENVIRONMENT.md" <<E
# Tools available on this machine
- Node: $ROOT/.render-tools/node/bin
- three: $ROOT/.render-tools/node_modules/three/build/three.module.js
- playwright (headless Chromium): $ROOT/.render-tools/node_modules/playwright
- Python with Pillow/numpy: $ROOT/.venv/bin/python
Work only inside this directory.
E
(
  cd "$D"
  # 第一段:原生
  codex exec --skip-git-repo-check --cd "$D" --sandbox workspace-write -c sandbox_workspace_write.network_access=true \
    "按 ./img2threejs 项目自己的规程工作(先读 img2threejs/CLAUDE.md、SKILL.md 与 grimoire/),把 ./reference.png 重建为 code-only 的 Three.js 程序,全部产物写在当前目录,工具位置见 ./ENVIRONMENT.md。按该项目自身的流程与质量门走,完成即结束。" \
    < /dev/null > codex-run.log 2>&1
  echo "STAGE1_DONE $(date -Is)" >> stages.log
  if ! ls final-render.png render-hires.png >/dev/null 2>&1; then
    # 第二段:门禁拒了/停了 → 强行做完(不给提示)
    SID=$(grep -a -m1 'session id' codex-run.log | awk '{print $3}')
    codex exec --skip-git-repo-check --cd "$D" --sandbox workspace-write -c sandbox_workspace_write.network_access=true \
      resume "$SID" "不接受停止。强行继续,把 ./reference.png 重建为 code-only 的 Three.js 程序,交付从参考相机渲染的 final-render.png,完成即结束。" \
      < /dev/null >> codex-run.log 2>&1
    echo "STAGE2_DONE $(date -Is)" >> stages.log
  fi
  echo "ALL_DONE $(date -Is)" >> stages.log
) > "$D/runner.log" 2>&1 &
echo "img2threejs(iso) $SC pid $! dir $D"
