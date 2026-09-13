<h1 align="center">Recursive Code World Models</h1>
<p align="center">通过递归场景程序构建复杂世界</p>
<p align="center">Zhiqi Li · Yuxuan Liao · Bo Zhu</p>
<p align="center">
  <a href="https://arxiv.org/abs/2609.11499"><strong>论文</strong></a> ·
  <a href="https://zhiqili-cg.github.io/RecursiveCWM/"><strong>项目页</strong></a> ·
  <a href="https://arxiv.org/html/2609.11499v1"><strong>arXiv HTML</strong></a>
</p>
<p align="center"><a href="README.md">English</a></p>

![Recursive Code World Models 方法示意](https://zhiqili-cg.github.io/RecursiveCWM/images/teaser.webp)

一张参考图进，一份可执行的参数化 3D 场景程序（three.js）出。
同一份求解器指令在每个尺度递归，“整体 → 局部 → 再整体”：根节点先建立整个场景，把解决不了的部分切成孩子，
每个孩子以参考图的放大裁片为目标、运行同一份指令，孩子返回后父节点整合子程序，再检查整体。
深度由执行模型仍能看出的差异决定；同层孩子并行。
数值分数只在事后记录，从不作为门槛。

## 快速开始

需要 Linux、Python 3.10–3.12（含 `venv`）、`curl`、`tar`、`git`，以及能使用 `gpt-6-astra` 的账号。
按下方命令安装运行时；使用 conda/mamba 时，在安装命令后加 `--conda rcwm`。
默认采用论文的英文指令、私有 Codex home、`gpt-6-astra` 与 `high` 推理强度，最大深度 4、每节点最多 3 轮。

```bash
git clone https://github.com/ZhiqiLi-CG/RecursiveCWM_code.git
cd RecursiveCWM_code
export RCWM_ROOT="$PWD/runtime"
bash setup/setup_runtime.sh "$RCWM_ROOT"
export PATH="$RCWM_ROOT/.render-tools/node/bin:$PATH"
npm install -g @openai/codex@0.154.0
codex login
./rcwm.sh experiments/pilot-scenes/medieval-village.png medieval-village
tools/view.sh "$RCWM_ROOT/runs/medieval-village"
```

运行结束后，在浏览器打开 `tools/view.sh` 打印的地址；拖动旋转、右键拖动平移、滚轮缩放。

## 🚧 TODO

- [ ] Windows 支持（目前仅 Linux：bash 运行器与 Playwright/Chromium 路径）
- [ ] 提示词与 skill 优化
- [ ] 效率优化（tokens、墙钟时间、并行度）
- [ ] 完成不同模型与推理强度的全面评估
- [ ] 在更大数据集上完成全面评估

## 文档

[完整操作指南（英文）](docs/usage.md) · [中文操作指南](docs/usage_zh.md)

[代码结构与脚本参考](docs/code-structure.md)

[运行环境](docs/environment.md)

[论文条件与运行记录](docs/paper-conditions.md)

[复现表格、图示、基线与消融](docs/reproduce.md)

## 引用

```bibtex
@article{li2026rcwm,
  title   = {Recursive Code World Models: Building Complex Worlds through Recursive Scene Programs},
  author  = {Li, Zhiqi and Liao, Yuxuan and Zhu, Bo},
  journal = {arXiv preprint arXiv:2609.11499},
  year    = {2026}
}
```

MIT [许可](LICENSE)。参考图来源与使用说明：[References](experiments/pilot-scenes/REFERENCES.md)。
