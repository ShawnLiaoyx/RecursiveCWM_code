# Recursive Code World Models — 代码包(中文说明)

论文 **Recursive Code World Models: Building Complex Worlds through Recursive Scene Programs**(Zhiqi Li, Yuxuan Liao, Bo Zhu)的代码。
论文:https://arxiv.org/abs/2609.11499 · 项目页(可逐节点查看两个交付世界):https://zhiqili-cg.github.io/RecursiveCWM/

一张参考图进,一份可执行的参数化 3D 场景程序(three.js)出。同一份求解器指令在每个尺度递归,"整体 → 局部 → 再整体":
根节点先立整个场景,把自己解决不了的部分切成孩子,每个孩子拿到参考图的放大裁片当自己的目标、跑同一份指令,孩子回来后父节点
把子程序合进来、再看一遍整体。深度由执行模型的眼睛决定;同层孩子并行。数值分数只在事后记录,从不当门槛。英文版更详细:[usage.md](usage.md)。

## 目录

1. 仓库里有什么 · 2. 需要什么 · 3. 安装 · 4. 跑一个场景 · 5. 一次运行产出什么 · 6. 选项 · 7. 多场景并行且隔离 ·
8. 中断后续跑 · 9. 查看一次运行 · 10. 复现论文的表和图 · 11. 基线与消融 · 12. 论文运行的数字 · 13. 论文条件:代码强制的与你要核对的 · 14. 测试 · 15. 排错 · 16. 引用与许可

## 1. 仓库里有什么

[代码结构：目录、脚本参数、运行流程、trace 与选图规则](code-structure.md) · [运行环境](environment.md)

## 2. 需要什么

- Linux x86_64(运行时也支持 arm64;论文在 Ubuntu 上跑)。macOS 未测。
- Python 3.10–3.12(系统 `python3` 带 `venv`,或 conda/mamba)、`curl`、`tar`、`git`;安装与调模型都要联网。安装不会碰你当前所在的 Python 环境(见 §3)。
- OpenAI **Codex CLI** 且已登录:`npm install -g @openai/codex`(PATH 里任一 Node ≥ 18,或用安装脚本装的那个),然后 `codex login`。
  运行器每个节点调一次 `codex exec`,并解析其输出里的 `session id:` 与 `tokens used` 两行;论文用的是 codex-cli 0.154。
- 模型权限:能跑 `gpt-6-astra` 的账号。运行器每次调用都指定这个模型、推理强度 `high`(论文设置),`~/.codex/config.toml` 不用改。
  换模型必须显式给 `RCWM_MODEL`(§6);codex 能跑的任何模型在机制上都能用,效果取决于模型的眼睛。
- 磁盘:运行时约 1 GB(Node + Chromium + Python 包;加指标包再 +1.5 GB)。一次运行写 5–130 MB。
- 不需要 GPU:渲染用无头 Chromium(软件 WebGL),指标在 CPU 上算。

## 3. 安装

```bash
git clone https://github.com/ZhiqiLi-CG/RecursiveCWM_code.git
cd RecursiveCWM_code
bash setup/setup_runtime.sh /path/to/rcwm-runtime            # 只装求解器运行时(约 1 GB,几分钟)
bash setup/setup_runtime.sh /path/to/rcwm-runtime --metrics  # 再加上指标/出图所需的包(torch CPU 等)
export RCWM_ROOT=/path/to/rcwm-runtime
```

脚本按 [docs/environment.md](environment.md) 建目录:一个私有 Python 环境(Pillow、numpy)、从 nodejs.org 下载 Node.js 22
(或 `--node-from /path/to/node` 复用现有的)、three.js 0.160.1、Playwright 1.62.1 与无头 Chromium,最后渲染一个测试立方体并检查截图。
可重复执行;失败后重跑即可。

**Python 环境。** 不会往你当前的环境里装任何东西,之后也不用 activate:所有脚本都按路径调用 `$RCWM_ROOT/.venv/bin/python`。

| 你用的是 | 这样装 | 得到什么 |
|---|---|---|
| 系统 Python | `bash setup/setup_runtime.sh /path/to/rcwm-runtime` | 用 `python3` 建在 `$RCWM_ROOT/.venv` 的 venv(`--python /path/to/python3.12` 指定解释器) |
| conda / mamba / micromamba | `bash setup/setup_runtime.sh /path/to/rcwm-runtime --conda rcwm` | 一个专用 conda 环境 `rcwm`(不存在则以 `python=3.12` 创建),软链为 `$RCWM_ROOT/.venv`;锁定版本的包只装进这个环境 |

如果你的 shell 里激活着 conda 的 `base`,请用 `--conda`(或 `--python /usr/bin/python3`),不要用默认方式,免得 venv 建在 `base` 之上、包混进 `base`。
`--metrics` 把 torch/opencv/scikit-image/lpips/open_clip 的锁定版本装进同一个私有环境,不进你的环境;已有版本兼容的 conda 环境可直接 `--conda` 指过去。conda 不在 PATH 时用 `RCWM_CONDA=/path/to/conda` 指定。Chromium 浏览器文件放在 `$PLAYWRIGHT_BROWSERS_PATH`(默认 `~/.cache/ms-playwright`),想换地方就在安装前和每次发射前都设这个变量。

冒烟测试报 Chromium 起不来,说明机器缺 Chromium 的共享库,用 root 跑一次:
```bash
cd /path/to/rcwm-runtime/.render-tools && sudo npx playwright install-deps chromium
```

不给路径则运行时建在 `<仓库>/runtime`(已 git-ignore),此时不用设 `RCWM_ROOT`。

## 4. 跑一个场景

```bash
export RCWM_ROOT=/path/to/rcwm-runtime
./rcwm.sh experiments/pilot-scenes/shop-row.png shop-row
```

发生的事:参考图被拷到 `$RCWM_ROOT/runs/shop-row/fractal/scene/target.png`,写好根节点的 brief,`runner/solve_recursive.sh` 启动根会话。
每个节点用指令跑一次 `codex exec`,要么交付(`part.json` + `account.md` + 自己的渲染),要么写 `children.json`;运行器把孩子作为自身的新调用并行发射,
等齐后带着已交付孩子的清单续接父节点会话("再整体")。每节点最多 `max-depth` 层、`max-cycles` 轮"整体→孩子→再整体"。脚本会阻塞到根交付,
然后打印调用树、交付程序与渲染的路径。

默认 codex 使用私有 home(`$RCWM_ROOT/.codex-home`),里面只有两行 `config.toml`(论文的模型与推理强度)、你的登录文件副本(`auth.json`,600 权限,别分享别提交)
和本仓的 `worldgen-techniques` skill;你 `~/.codex` 里的其他 skill、记忆、`AGENTS.md`、配置项对这次运行全不可见。这就是论文的条件,§13 有完整清单。
`RCWM_CLEAN_CODEX_HOME=0 ./rcwm.sh …` 改用你机器上的正常 home:那台机器装的所有 skill 都会被求解器看到,而本仓的 skill 反而不在(除非你自己拷进 `~/.codex/skills/`)。

每个场景预计一到两小时、0.5–11 M tokens(见 §12 表)。codex 工作期间运行器不打印,另开一个 shell 看进度:

```bash
tail -f $RCWM_ROOT/runs/shop-row/fractal/scene/codex-run.log        # 根会话
tail -f $RCWM_ROOT/runs/shop-row/trace/events.jsonl                 # 每次会话起止、子调用与返回
python3 runner/trace_report.py $RCWM_ROOT/runs/shop-row              # 到目前为止的调用树
```

长场景请用 `nohup … &` 或 `tmux`;终端关了 shell 还在,运行才还在。同名运行会被拒绝(换个名字,或按 §8 续跑)。

## 5. 一次运行产出什么

```
$RCWM_ROOT/runs/<运行名>/
  conditions.json               这次运行的发射条件(指令哈希、深度、轮数、模型、推理强度、codex home、各版本)
  camera-contract.json          根为参考帧锁定的相机(求解器写的)
  trace/events.jsonl            运行器的 trace(每行一个 JSON;构建顺序的事实依据)
  trace/tree.json, recursion_report.md     调用树(runner/trace_report.py)
  fractal/scene/                根节点
    target.png                  参考图(孩子的 target.png 是它的放大裁片)
    view.json, brief.md         在父帧中的窗口与父节点的 brief(根:整图)
    task.md                     给这个节点的指令
    codex-run.log, .sid         会话记录与会话 id(续跑用)
    children.json(.prev)        这个节点请求过的孩子
    part.json                   交付的程序:{"module": "component.js", "export": "build", "children": [...]} 或 components 列表
    account.md                  节点自己的过程记述
    final.png(或 part.json 声明的名字)   参考相机下的渲染
    index.html, *.js            节点的查看器与模块(孩子从 ../<child>/ 导入)
  fractal/<child>/…             每个孩子同样布局,一节点一目录
```

`part.json` 由 `runner/check_part.py` 只查事实(模块存在、id 唯一、孩子存在)。trace 里的 `stop_reason` 是 `visual_stop`(节点自己判定本层完成)、`no_artifact` 或 `invalid_artifact`。

## 6. 选项

| 要做什么 | 怎么做 |
|---|---|
| 深度与轮数 | `./rcwm.sh ref.png name 4 3`(位置参数:最大深度、每节点最大轮数;默认 4 和 3,即论文取值)。直接调运行器时用 `RCWM_MAXD` / `RCWM_MAXCYC` |
| 中文指令与中文 skill | `RCWM_LANG=zh`(用 `solver/solver-template.zh.md` 与 `SKILL.zh.md`;运行器的续接话语仍是英文,深度上限提示随指令语言) |
| 自己的指令 | `RCWM_PROMPT=/path/to/instruction.md`(占位符 `__NODE__`、`__CHAIN__`、`__DEPTH__` 会被替换;trace 记录文件哈希) |
| codex home | 默认私有(见 §4);`RCWM_CLEAN_CODEX_HOME=0` 用机器自己的。要自己建私有 home:`tools/make_codex_home.sh $RCWM_ROOT [en\|zh]`,再用 `CODEX_HOME=$RCWM_ROOT/.codex-home` 发射 |
| 模型 / 推理强度 | `RCWM_MODEL` / `RCWM_REASONING`(默认 `gpt-6-astra` / `high`,即论文取值)。运行器把两者传给每一次 codex 调用,`~/.codex/config.toml` 改不了它们 |
| 自定义模型服务 | `RCWM_CODEX_CONFIG=/path/config.toml` 把该文件放进私有 home 代替两行论文配置(自己的 API 端点用;里面别写 `model`/`model_reasoning_effort`,或与论文一致) |
| Chromium 位置 | `PLAYWRIGHT_BROWSERS_PATH`(运行器会把它设成 codex 可写) |
| 只用运行器 | 先像 `rcwm.sh` 那样准备好 `runs/<name>/fractal/scene/{target.png,view.json,brief.md}`,再 `RCWM_ROOT=… bash runner/solve_recursive.sh runs/<name> scene - 0 <name>` |

## 7. 多场景并行且隔离

运行时只搭一次,然后每个场景一个工作区,其 `.venv` 和 `.render-tools` 是指向运行时的软链:

```bash
export RCWM_RUNTIME=/path/to/rcwm-runtime
for s in city-full school-block shop-row; do
  ws=/work/rcwm/$s
  tools/new_workspace.sh $ws $RCWM_RUNTIME
  ( RCWM_ROOT=$ws nohup ./rcwm.sh experiments/pilot-scenes/$s.png $s > $ws/rcwm.log 2>&1 & )
  sleep 15
done
```

每个工作区有自己的 `runs/` 和私有 `.codex-home`,不同场景的会话看不到彼此的文件和历史;运行根是 `$ws/runs/<name>`。
十个场景并行会陆续起几十个 codex 会话;瓶颈是模型的速率/配额与磁盘(起批之前先 `df`:盘满会让每个会话都静默失败,ENOSPC)。

## 8. 中断后续跑

机器、shell 或模型配额把运行打断了,就原地续跑,已交付的一律不重做:

```bash
RCWM_ROOT=/work/rcwm/shop-row tools/resume_run.sh shop-row
```

根运行器会用同一份指令重新调用(`RCWM_PROMPT` / `RCWM_LANG` / `RCWM_MAXD` / `RCWM_MAXCYC` 要与原发射一致;默认值与 `rcwm.sh` 一致)。
每个节点按自己的 `.sid` 续接会话。曾请求过孩子但部分孩子没交付的节点,只重新发射那些没交付的(trace 事件 `recover_children`),而不是带着不完整的集合唤醒父节点。
运行的私有 codex home 会被沿用,并先从 `~/.codex/auth.json` 刷新登录文件(所以配额或凭据出问题时先重新登录再续跑);用 `RCWM_CLEAN_CODEX_HOME=0` 发射的运行继续用机器自己的 home。§6 里直接调运行器同样可以续跑。

## 9. 查看一次运行

**调用树。** `python3 runner/trace_report.py $RCWM_ROOT/runs/<name>` 打印并写出 `trace/recursion_report.md`(每个 `solve(node)` 的深度、会话数、tokens、停机原因)与 `trace/tree.json`。

**打分。** 装了指标包(`--metrics`)后,一行 JSON:选中的最终渲染、对参考图的 PSNR / SSIM / edge-F1 / LPIPS / CLIP、节点数、深度、每层节点数、交付件数、tokens 与墙钟:

```bash
RCWM_REFS=experiments/pilot-scenes $RCWM_ROOT/.venv/bin/python tools/score_run.py shop-row $RCWM_ROOT/runs/shop-row
```

`RCWM_REFS` 是放 `<scene>.png` 的目录(默认 `experiments/pilot-scenes`)。这行同时写到 `runs/<name>/trace/score.json`;设了 `RCWM_SCORES` 就追加到那个文件。第一次会下载 LPIPS 与 CLIP 权重。

**在 3D 里打开世界(可拖动)。** 交付的是场景程序不是图片,可以交互地看:

```bash
tools/view.sh $RCWM_ROOT/runs/shop-row            # 打印  http://127.0.0.1:8000/runs/shop-row/fractal/scene/index.html
```

浏览器打开这个地址:拖动旋转,右键拖(或 shift+拖)平移,滚轮缩放,`R` 回到交付时的相机,`H` 隐藏提示;地址后加 `?clean=1` 隐藏查看器自己的叠加层(视角标签、徽章、图钉)。
服务器只读地提供工作区,并在页面加载时注入轨道控制,所以任何交付查看器都能用、不改它的文件(交付的 `index.html` 本身只渲染固定相机)。第二个参数指定端口。
在远程机器上跑时先转发端口,再在本地打开同一地址:

```bash
ssh -L 8000:127.0.0.1:8000 <服务器>               # 在你的笔记本上;然后在服务器上 tools/view.sh …
```

自带 `index.html` 的子节点同样可以打开(`/runs/<name>/fractal/<node>/index.html`);大多数孩子交付的是模块,经根的查看器渲染。不用这个工具的话,任何以工作区根为目录的静态服务器(`python3 -m http.server`)只能看到固定相机的交付页面。

**高清与新视角渲染。** 把交付程序按参考帧 4 倍重渲,并从它没见过的五个相机渲染(方位角 ±35°、高轨、两处特写):

```bash
tools/render_views.sh $RCWM_ROOT/runs/shop-row 4
# -> runs/shop-row/fractal/scene/final-hires.png 与 fractal/scene/novel-views/view-{L35,R35,orbit,close1,close2}.png
```

渲染工具(`tools/hires_render.mjs`、`tools/novel_views.mjs`、`tools/teaser_render.mjs`)在服务出的 `three.module.js` 上挂钩子拿到查看器的 renderer、scene、camera,
所以任何交付查看器都不用改就能用。参数:工作区根、页面在其下的路径、输出,可选倍率、JS 的 "ready" 表达式(默认 `window.ready` 及常见变体;没有 ready 标志的查看器超时后截取,`RCWM_READY_TIMEOUT_MS`)和 `WxH`。
`teaser_render.mjs` 隐藏所有屏幕空间叠加层,给名字正则还能隐藏指定场景对象(如位置图钉),只写 WebGL 画布。

## 10. 复现论文的表和图

脚本通过 `experiments/pickers.py`(每个方法一条"哪张图是它的最终渲染"规则)读取运行,全部用环境变量配置,不含任何机器路径:

| 变量 | 含义 |
|---|---|
| `RCWM_ROOT` | 含 `runs/` 的运行时/工作区根 |
| `RCWM_REFS` | 十张参考图 `<scene>.png` 所在目录(五张 WorldClaw 裁片的重建方法见 `experiments/pilot-scenes/REFERENCES.md`;精确文件在论文仓) |
| `RCWM_OURS_CHAIN` | 每个场景我们的运行在哪,`{scene}` 会被替换:如 `'/work/rcwm/{scene}/runs/{scene}'`(绝对模式 = 一景一工作区)。默认 `runs/pilot/{scene}-recursive-r1` |
| `RCWM_OURS_OVERRIDE` | `scene=/path/render.png,…` 强制某景出图所用的渲染(我们用了 4 倍渲染) |
| `RCWM_SEIG`、`RCWM_SEIG_RUN`、`RCWM_VIGA`、`RCWM_VIGA_TESTID`、`RCWM_I2T_ISO`、`RCWM_I2T_ISO_ALL=1` | 基线输出在哪(见 `baselines/external/README.md`) |
| `RCWM_METRICS_CSV` | 指标累积到的 CSV(默认 `$RCWM_ROOT/runs/pilot/metrics/all-methods-full.csv`) |
| `RCWM_PAPER` / `RCWM_NO_PAPER=1` | 接收表格的论文 checkout(`sections/04_experiments.tex`),或只把表写在 CSV 旁边 |

```bash
PY=$RCWM_ROOT/.venv/bin/python
$PY experiments/refresh_metrics.py                      # 每个(场景, 方法)的指标 → $RCWM_METRICS_CSV
RCWM_NO_PAPER=1 python3 experiments/main_table.py       # 表 1(LaTeX + markdown,写在 CSV 旁)
$PY experiments/make_case_figures.py OUT --full city-full,medieval-village \
   --ours snow-village,island-harbor,japan-island,school-block,police-corner,park-lake,shop-row,valley-village
                                                        # 图 3-4(参考 | 我们 | 基线,渐进细节窗)与图 5-8(参考 vs 我们);
                                                        # 4 倍渲染时 RCWM_CASE_CANW=2000;RCWM_CASE_FIX='scene=idx:fx,fy,ws;…' 手工钉细节窗
$PY experiments/make_novel_views.py OUT/novel-views-grid.png   # 图 9:每景一行 = 参考相机 + 五个新视角(读 tools/render_views.sh 写的 novel-views/)
python3 experiments/variant_table.py                    # 消融表(表 2/3),来自 runs/pilot/<scene>-<variant>-r1
```

`experiments/eval_metrics.py reference.png render.png` 算一对图的指标(JSON);缺库的项为 `null`。分数只记录,流程里没有任何东西读它。

## 11. 基线与消融

**消融(结构对照)。** 同一运行器、不同指令与深度上限:

```bash
experiments/run_matrix.sh "school-block medieval-village" "flat localglobal globallocal twolevel recursive" 1 4
```

`flat` = `baselines/variants/flat-zoom.md`、深度 0;`localglobal` 深度 1;`globallocal` 深度 0;`twolevel` = 主指令加 `RCWM_MAXD=1`;`recursive` = 主指令、深度 4。
运行落在 `$RCWM_ROOT/runs/pilot/<scene>-<variant>-r1`,行写入 `runs/pilot/results.csv`;最后一个参数限制并发的 codex 进程数(数的是全机所有 `codex exec`)。参考图取 `$RCWM_REFS/<scene>.png`(默认 `experiments/pilot-scenes/`)。

**外部基线。** `baselines/external/README.md` 介绍三个基线(SEIG 复现、VIGA 官方 runner + codex shim、每景一个隔离目录的 img2threejs)及发射脚本;各需自己的 checkout(`RCWM_SEIG`;`RCWM_VIGA` + `BLENDER`;`$RCWM_ROOT/vendor/img2threejs` + `RCWM_I2T_ISO`)。每个方法拿到的都是未修改的参考图。

## 12. 论文运行的数字

论文主表(表 1)背后的十次运行,用 `tools/score_run.py` 打分。可用来估计一个场景大概要多少节点、时间和 tokens:

| 场景 | 节点 | 最大深度 | 每层节点数 | PSNR↑ | SSIM↑ | Edge F1↑ | LPIPS↓ | CLIP↑ | tokens (M) | 墙钟 (min) |
|---|---|---|---|---|---|---|---|---|---|---|
| city-full | 24 | 4 | 1/4/12/6/1 | 18.2 | 0.66 | 0.94 | 0.158 | 0.95 | 2.4 | 69 |
| snow-village | 83 | 4 | 1/3/10/27/42 | 17.9 | 0.73 | 0.84 | 0.237 | 0.83 | 9.2 | 79 |
| island-harbor | 57 | 4 | 1/3/11/22/20 | 17.4 | 0.74 | 0.90 | 0.186 | 0.93 | 10.9 | 121 |
| medieval-village | 24 | 4 | 1/2/6/11/4 | 18.7 | 0.71 | 0.89 | 0.200 | 0.93 | 3.2 | 77 |
| japan-island | 29 | 3 | 1/4/10/14 | 19.3 | 0.73 | 0.87 | 0.201 | 0.96 | 3.9 | 79 |
| school-block | 12 | 3 | 1/3/6/2 | 16.4 | 0.56 | 0.97 | 0.171 | 0.94 | 1.1 | 65 |
| police-corner | 7 | 2 | 1/3/3 | 16.6 | 0.44 | 0.97 | 0.159 | 0.91 | 0.5 | 31 |
| park-lake | 12 | 3 | 1/3/6/2 | 23.3 | 0.83 | 0.99 | 0.075 | 0.95 | 1.1 | 55 |
| shop-row | 9 | 2 | 1/3/5 | 17.4 | 0.65 | 0.96 | 0.120 | 0.96 | 0.8 | 54 |
| valley-village | 21 | 3 | 1/3/9/8 | 14.1 | 0.38 | 0.48 | 0.583 | 0.87 | 3.2 | 86 |

深度 0 是根,"最大深度 4"即五层。tokens 是该运行所有会话之和;墙钟是 trace 首尾事件之差。medieval-village 与 city-full 的交付程序和完整 trace 可在项目页逐节点查看。

## 13. 论文条件:代码强制的与你要核对的

照 §3、§4 写的命令做,得到的就是论文的条件。哪些由代码保证、哪些只有你能核对:

| 条件 | 论文 | 由谁保证 |
|---|---|---|
| 指令 | `solver/solver-template.md`,sha256 `8f194d22f285…` | `RCWM_PROMPT` 默认值;发射时打印哈希,写进 `conditions.json` 和每条 trace 事件 |
| 递归上限 | 深度 ≤ 4,每节点 ≤ 3 轮 | `rcwm.sh` 默认值 |
| 执行体 | `gpt-6-astra`,推理强度 `high` | 每次 `codex exec` 都显式传入(`-c model`、`-c model_reasoning_effort`),`~/.codex/config.toml` 写什么都不影响;记录在 `conditions.json` 和每条 `session_start` 事件 |
| codex 能看到什么 | 只有本仓的 `worldgen-techniques` skill(英文);没有其他 skill、记忆、`AGENTS.md`、配置项 | 发射时建的私有 codex home(默认)。`rcwm.sh` 会打印 `codex home: private (…); skills: worldgen-techniques` |
| 沙盒 | workspace-write,联网,Chromium 缓存可写 | 运行器的 `codex exec` 参数 |
| 根节点 brief 与环境说明 | 同一段文字 | `rcwm.sh` |
| 运行时 | Node 22.14、three 0.160.1、Playwright 1.62.1 + Chromium;Python 3.12 + Pillow 12.3、numpy 2.5 | `setup/setup_runtime.sh` 锁定版本;版本写进 `conditions.json` |
| codex CLI | 0.154 | **你**:版本不同时 `rcwm.sh` 会提示;运行器解析 codex 输出的 `session id` 与 `tokens used` 两行 |
| 模型权限 | 能跑 `gpt-6-astra` 的账号 | **你**:`codex login`;换模型必须显式给 `RCWM_MODEL` |
| 参考图 | 原图原尺寸不改动(图里的标注一并保留) | **你**:文件原样传入 |
| 隔离 | 一景一工作区,里面没有别的东西 | **你**:每景用 `tools/new_workspace.sh`(§7);别把其他材料放在 `$RCWM_ROOT` 下 |

你有意改的任何东西(`RCWM_MODEL`、`RCWM_REASONING`、`RCWM_PROMPT`、`RCWM_LANG=zh`、`RCWM_CLEAN_CODEX_HOME=0`、`RCWM_CODEX_CONFIG`)都会写进 `runs/<name>/conditions.json`,
一次运行永远带着"它与论文哪里不同"的记录。`tests/test_runner_offline.sh` 用假 codex 检查上面"由代码保证"的各行(§14)。

## 14. 测试

```bash
bash tests/test_runner_offline.sh $RCWM_ROOT          # 用假 codex 走完整个发射(不调模型、不联网):私有 home、论文模型/强度已传入、
                                                      # 根切两个孩子、孩子交付、父节点续接、trace、conditions.json、trace_report、check_part
$RCWM_ROOT/.venv/bin/python -m pytest tests/                              # 相机裁剪几何(pytest 在 --metrics 包里)
$RCWM_ROOT/.render-tools/node/bin/node setup/smoke_test.mjs $RCWM_ROOT   # 渲染链路(无头 Chromium 里的 three.js + Pillow)
```

## 15. 排错

- **`codex CLI not found` / `RCWM_ROOT … is not a runtime root`。** 安装并登录 codex;跑 `setup/setup_runtime.sh`。
- **最深一层的节点反复请求孩子。** 运行器会在 `RCWM_MAXD` 那层给指令追加深度上限提示;发射后改小了上限,续跑时要用同一个上限。
- **某个 `codex-run.log` 出现 `hit your usage limit`。** 模型配额用完,会话不交付就结束。等待或换账号登录,再 `tools/resume_run.sh <name>`(它会把新的 `auth.json` 拷进私有 home)。
- **所有会话同时失败。** 先 `df`:盘满(ENOSPC)会让渲染和 codex 静默死掉。
- **Chromium 起不来。** 在 `$RCWM_ROOT/.render-tools` 里 `sudo npx playwright install-deps chromium`;安装与发射时 `PLAYWRIGHT_BROWSERS_PATH` 保持一致。
- **渲染工具报 `hookMissing`。** 查看器没有经服务根导入 `three.module.js`(打包或 CDN 的 three);用查看器自己的控件渲染,或把页面的导入改指向 `/.render-tools/node_modules/three/build/three.module.js`。
- **渲染工具等三分钟才截图。** 查看器没设 `window.ready`;把自己的 ready 表达式当第四个参数传入,或调低 `RCWM_READY_TIMEOUT_MS`。
- **`pickers.ours` 警告 "no recognised final render name"。** 节点交付了但渲染名字不常见;去 `fractal/scene/` 看一眼,用 `RCWM_OURS_OVERRIDE=scene=/path.png` 指定,或把名字写进 `part.json` 的 `evidence.final_render`。
- **中文运行配了英文 skill(或反过来)。** 用 `RCWM_LANG=zh`(拷进私有 home 的 skill 随它),直接调运行器时用 `tools/make_codex_home.sh $RCWM_ROOT zh`。
- **换台机器求解器表现不一样。** 拿 `runs/<name>/conditions.json` 对照 §13 的表:指令哈希、模型、强度、codex home、各版本都在里面。`codex home: … the machine's own` 说明是用 `RCWM_CLEAN_CODEX_HOME=0` 发射的,看得到那台机器的 skill。

## 16. 引用与许可

```bibtex
@article{li2026rcwm,
  title   = {Recursive Code World Models: Building Complex Worlds through Recursive Scene Programs},
  author  = {Li, Zhiqi and Liao, Yuxuan and Zhu, Bo},
  journal = {arXiv preprint arXiv:2609.11499},
  year    = {2026}
}
```

MIT 许可(见 `LICENSE`)。城市参考图来自 JanaChumi 的 CC0 "Isometric city" 精灵包(OpenGameArt);`medieval-village.png` 是 WorldClaw 论文图 9 的裁片、只作输入图;其余四张源自 WorldClaw 的参考图不分发(`experiments/pilot-scenes/REFERENCES.md`)。
