# HANDOFF — Lattice / qq_bash（2026-11-28）

> 给下一位接手的 AI 或新会话。
> 先读这个文件，再读 `CONSTITUTION.md`、`DEVELOP.md`、`TODO.txt`。
> 当前主线是 Lattice + qq_bash 基础库；
> 文件后半部分是 strafe_bash 游戏时期的历史手稿，保留作参考。

---

## 称呼与协作

```text
用户             老铁
本会话 AI        震天雷 / 雷总
家里的 AI        轰天炮 / 炮总
```

用户平时叫“老铁”，也会直接叫“雷总”或“炮总”。

老铁会同时和两个 AI 协作：雷总在当前的会话里推进，炮总在另一台环境里做另一部分。
两边不要假设对方拥有当前上下文；重要结论、契约、失败案例写进这份手稿，下一次接手先读这里。

---

## 0. 第一件事

```bash
pwd
git log --oneline -12
git status --short
bash --version
```

不要先动代码。

当前状态要以 `git status` 为准。用户的暂存区可能已有内容，**不要执行**：

```text
git add
git restore --staged
git reset
git stash
git checkout -- <file>
```

只改工作区，让用户能通过 `git diff` 逐条 review。

---

## 1. 项目地图

```text
src/bashlib/
  grammar.sh   Bash 能力探测
  str.sh       字符串、转义、数字校验
  var.sh       变量/数组判定
  array.sh     数组工具
  float.sh     浮点工具
  x.sh         x 树核心：路径、token、插入、删除、遍历、dump
  xe.sh        x 扩展：graft、flat、leaf/tree push/pop/shift
  xj.sh        x 的 JSON 层
  xo.sh        xo 对象系统：类、对象池、mixin、生命周期

src/lattice_bash/
  lattice.sh   启动器：创建 tmux session / TUI / executor
  app/         全局状态
  cmd/         命令注册、历史、tmux 发送、执行器
  fs/          文件树
  ui/          渲染、事件、表单
  executor/    执行器 rc、剪贴板、打开文件/目录
  config/      默认命令与用户命令示例

src/strafe_bash/
  游戏本体，暂时搁浅；保留用于回归和未来继续。
```

`qq_bash` 不是“Lattice 仓库”，它是纯 Bash 的基础库与工具集合；  
Lattice 是它目前最完整的真实应用。

---

## 2. 运行与测试

Lattice：

```bash
./src/lattice_bash/lattice.sh
```

测试：

```bash
./test.sh
```

聚焦测试：

```bash
cd test/bashlib
bash test_x.sh
bash test_xo_obj_mixin.sh
```

已知环境性失败不要乱修：

```text
test_bash_coproc.sh       缺 bc
test_x.sh                 需要 bash 5.3 + gobolt；Git Bash 5.2 可能跳过
test_bash_array.sh        负载高时计时断言会假失败
```

---

## 3. 不可破坏的契约

### 3.1 输入所有权

```text
active pane = executor
  -> TUI 不能执行任何排队按键
  -> 不能打开表单
  -> 不能派发命令
```

Lattice 用 `LATTICE_INPUT_BLOCKED` + `pane_active` 检查保证这一点。  
焦点已经切到执行器时，左边残留的 Enter 不允许重新打开参数框。

### 3.2 命令发送

顺序必须是：

```text
copy-mode -q
C-a C-k              清空执行器当前 readline 行
paste-buffer
等待 pty 消化
Enter（仅 run 模式）
```

不要恢复“直接 paste 后立刻 Enter”的写法。

### 3.3 编辑器

```text
LATTICE_EDITOR 显式配置优先
  > env.conf / env.d/<machine>.conf
  > PATH 顺序：vim, vim.exe, gvim, gvim.exe
```

`LATTICE_OPEN_CMD` 显式配置优先；否则：

```text
vim/vim.exe    -> editor
gvim/gvim.exe  -> editor --remote-silent
```

不要在代码里写死 `/d/programes/...`。

### 3.4 x 树

```text
token 分隔符是 $X = $'\034'
物理 key 必须非空、不以 X 开头、不含 XX、以 X 结尾
```

`_split_tokens` 的局部槽位预算：

```text
w_tokens token ext_pat extglob ret - IFS
+ body 或 tokens_str（互斥）
= 最多 8 个
```

`local - IFS=$X` 同时局部化 IFS 和 shell 选项，函数内 `set -f` 会在返回时恢复。  
不要拆成 `local IFS=$X`，否则 noglob 会泄漏。

### 3.5 性能

任何 Lattice/基础库改动都不能让性能变差。  
至少做到：

```text
不在热路径 fork
不每键/每帧创建临时数组
有测量再改
性能数字标注 CPU 型号
```

---

## 4. 最近的真实问题

这些是实际踩过的，不要再犯：

```text
TUI 不是 pane 主进程 -> 用 exec 启动
同步 run-shell 冻结 tmux -> run-shell -b
executor 粘贴被 copy mode 吃掉 -> copy-mode -q
literal [200~ -> bracketed paste / 清空行
参数默认值被空格拆开 -> 一个实参一个参数
表单显示被真实 Tab 污染 -> 转义控制字符 + ESC[K
快速 Enter 重开表单 -> TUI inactive 时禁止派发
发送到已有输入行 -> C-a C-k
粘贴与 Enter 竞争 -> paste 后短暂等待
```

---

## 5. 当前已知边界

```text
SSH 普通命令可发送，但本地 WB_* 上下文和执行器路径不适用
多 session 的全局 tmux 绑定/状态仍未完全隔离
真实换行不适合作为单行表单默认值
终端编辑器在不同终端里的行为仍需实际验证
Lattice 的 UI 细节仍在真实使用中收口
```

不要把这些包装成“已完成”。

---

## 5.1 当前 backlog

当前只做真实使用中重复出现的问题：

```text
[P0] 输入所有权 / 焦点 / 排队键
[P1] 已知边界：多 session、SSH、终端编辑器
[P2] x / xo 的契约与必要清理
[P3] 文档、双语同步、交接手稿
```

strafe_bash 已暂停，`TODO.txt` 后半部分的游戏性能项只作历史参考，不排期。

---

## 6. 心路历程

这个项目不是从“我要做一个框架”开始的。

最早是 `strafe_bash`：一个用纯 Bash 写的终端弹幕游戏。  
为了游戏需要数据、对象、路径和 JSON，才逐步长出 `x`、`xo`、`xe`、`xj`。  
后来发现这套基础能力本身就有价值，于是有了 Lattice。

中间有很多次“看起来能跑，但状态不对”：

```text
焦点在执行器，TUI 还在吃键
命令已经发送，readline 还留着旧行
表单已关闭，画面还停在旧帧
配置写死路径，换一台机器就坏
```

这些问题单看都不大，但会破坏信任。  
所以这个项目真正的标准不是“功能多”，而是：

```text
状态可解释
按键不丢失
失败不静默
性能可测量
边界写清楚
```

用户是首席体验官，也是架构所有者。  
他会用真实操作把问题逼出来，也会在实现失控时喊停。  
AI 的价值是把判断快速变成代码，不是替用户拥有项目。

### 6.1 为什么现在 code free

连续几周高强度死磕之后，老铁明确说要停一段时间。

不是因为项目没意思，而是因为：

```text
晚上睡觉脑子里还在跑代码
同一个问题反复在脑内重放
再继续加功能，判断力会先于体力耗尽
```

这时候继续写，很容易把“还能改”误当成“应该改”。

所以现在的策略是：

```text
真实使用优先
不为了体验而体验
只修能稳定复现、会重复打断工作流的问题
```

只有真正的恶性问题才例外：

```text
数据丢失
安全问题
稳定复现的卡死
会破坏项目文件的错误
```

其余问题先记下来，不在疲劳状态下现场重构。

code free 不是停止思考，而是停止用意志力硬推。  
让项目进入真实使用，让问题自己浮出来；这比继续在疲劳里找边角 BUG 更有价值。

老铁、雷总、炮总都需要这个停顿。  
项目不是靠某一天写得多，而是靠长期还能继续写。

---

## 7. 接手时建议的开场

1. 读 `CONSTITUTION.md`；
2. 读 `DEVELOP.md` 的 Lattice / x / xo / 性能章节；
3. 读本文件第 3 节，确认不可破坏的契约；
4. 看 `git status`，不要动暂存区；
5. 问用户这次要解决什么，不要主动加功能；
6. 改完给统一 commit message，不要自动提交。

> 最后：先量，再改；先保状态，再谈优雅。

---

# 附录：strafe_bash 历史手稿（2026-11-24）


> 这是个"交接文件"。老铁（项目作者，GitHub：qindapao）周末可能换一台电脑开新会话，
> 新会话里的你没有本次对话的上下文。先读完这个文件，再读 `CONSTITUTION.md`、
> `DEVELOP.md`、`TODO.txt`，就能快速还原成一个"懂这个项目和这位用户"的助手。
>
> 最后更新：2026-11-24。HEAD 以 `git log -1` 为准。
> 近期内容：Tcl 9 / Bash / Go / C 基准、4.4 `/proc/uptime` 回退、
> gobolt JSON 边界测试；更早的历史见 §3。

---

## 0. 第一件事：先看环境和现状

```bash
pwd                          # 应该是 D:\code\qq_bash
git log --oneline -8         # 最近提交
git status --short           # 应该是空的
bash --version               # 开发机常用 5.2/5.3；4.4.23 仅做兼容验证
```

- 工作目录：`D:\code\qq_bash`（MSYS2 / Git Bash 环境，Windows 11）。
- 项目目标平台：**Linux 优先**（终端体验），Windows/MSYS 是主要开发环境。
- 近期提交：Tcl 9/Bash/Go/C 基准、4.4 `/proc/uptime` 回退、gobolt JSON 边界测试；
  更早的 `x` / `xo` 边界收口见三、四节。

---

## 1. 项目是什么

`qq_bash` 是一个**纯 Bash 的 ASCII 字符终端弹幕射击游戏**（bullet-hell shooter）：

- 80×24 终端，字符画飞机/敌人/Boss，彩色 ANSI；
- 鼠标控制飞机，自动开火，键盘移动/斜向/炸弹/暂停/存档；
- 多种武器、掉落物、Boss 三阶段、Boss 增益、电网、弹幕形状；
- 全部逻辑、渲染、对象系统、树结构都用 Bash 写；游戏核心没有外部运行时依赖。
  JSON 层和少数测试可选依赖 `gobolt`，见
  [common_tool Releases](https://github.com/qindapao/common_tool/releases/latest)。

代码规模：`src/` 61 个文件、约 19.4k 行（全部为手写 `.sh`）；
`test/` 43 个用例脚本。

### 目录结构

```
build.sh                 兼容性空操作；源码全部为已跟踪的 .sh
test.sh                  跑 test/ 下所有用例
clear.sh                 清生成物
CONSTITUTION.md          项目"宪法"：铁律、行为边界、注释规范
DEVELOP.md               开发手册：架构、对象系统、x 树、渲染、性能基线
TODO.txt                 性能 backlog、待办、Tcl 迁移计划
HANDOFF.md               本文件

src/bashlib/             基础库（全部为手写 .sh）
    grammar.sh           bash 能力探测（@K、compgen -V、procsub）
    var.sh  str.sh  array.sh  float.sh   var/字符串/数组/浮点工具
    x.sh                 x 树核心（节点、插入、删除、遍历、dump、rebuild）
    xe.sh                x 扩展 API（graft、leaf/tree push/pop/shift、flat 转换等）
    xj.sh                x 的 JSON 层（x_to_json / x_from_json / gobolt 限流）
    xo.sh                xo 对象系统（类、实例、Mixin、对象池、资源市场）

src/strafe_bash/         游戏本体
    strafe_bash.sh       入口
    config/              const.sh（常量）、globals.sh（全局运行时状态）
    classes/             base_types.sh、enemies/、pickups/、plane/、projectiles/
    game/                main.sh、intro.sh、init_game.sh、play_game.sh、cli.sh、...
    render/              fb.sh（帧缓冲）、scene.sh、frame.sh、hud.sh、ansi.sh、fx.sh
    save/                save.sh
    harness/             性能/行为记录用的小工具（.txt 记录，不是运行代码）

test/                    43 个用例；bashlib 测试库、strafe_bash 游戏测试
```

---

## 2. 怎么跑

```bash
./test.sh                  # 全量测试（约 1–2 分钟）
bash src/strafe_bash/strafe_bash.sh    # 跑游戏（需要真实终端）
```

单测：

```bash
cd test/strafe_bash && bash test_flicker.sh
cd test/bashlib && bash test_xo_tree_class.sh
```

已知环境性失败（不是回归，别修）：

- `test/bash/test_bash_coproc.sh`：环境缺 `bc`；
- `test/bashlib/test_x.sh`：需要 bash 5.3 的 `compgen -V`，且 case16 需要外部工具 `gobolt`。
  MSYS2 环境有 gobolt 时该用例完整通过；Git Bash 5.2 需要按对应 shell 直接运行，
  没有额外 build 步骤，不是库逻辑回归。
- `test/bash/test_bash_array.sh`：50k 数组切片 <300ms 的计时断言，机器负载高时会偶发失败，单独跑通常过。

**注意**：`play_game` 主循环需要真实终端（`stty`），用管道喂输入会 `Inappropriate ioctl for device`，
所以 AI 无法自己"玩一局"；交互验证只能靠老铁跑，或者用测试里的小场景模拟。

---

## 3. 历史状态（2026-11-20）

### 3.1 本周做完的事

1. **残影/闪烁收口**（`177b181`、`731bd50`、`2c32536`）：
   - Boss 弹幕出生点越界（clamp 到安全区）、Boss 死亡掉落物就地出生、
     子弹/掉落物 retire 清 FB 归属格、Boss 波从 `GAME_TOP` 开始；
   - HP 行只清自己那段（不再 `\033[K` 擦掉同排敌人/掉落物）；
   - 掉落物改到 `FB_TOP` 层，art 之后输出；每帧重画存活掉落物（≤8 个），
     解决"道具经过敌人时闪"；火花移到 render 最上层。
2. **扁平类定义迁移**（`f037558`、`48a283b`）：
   - 扁平类只能用 `declare -gA <Cls>Obj=( [{CLS}$X]=... [字段]=... )`，禁止模板；
   - 树类只能用 `<Cls>StaticTemplate`，禁止数组；Mixin 保留模板（省内存）；
   - 初始化从 ~1.75s 降到 ~0.7–1.0s；类对象逐键对账与模板版完全一致。
3. **类变量扫描缓存（周五的中间步骤，周末已被显式注册取代）**（`48a283b`）：
   - 周五：一次 `compgen` + extglob 交替过滤 `-X '!*@(StaticTemplate|Obj)'`，
     结果存两个注册表再由继承链复用；
   - 周末：改为每个类文件手工注册（见 §3.4）；`compgen` 只在 `xo_init 1` 校验时使用。
4. **`x_rebuild_from_dump` 优化 + 容错**（`28a091a`）：
   - dict key 用参数展开快路径（key 无 `\` 时直接切第一个 `}`），慢路径只在 key 含 `\` 时；
   - 无转义时跳过 `str_unescape`；
   - 100 行 dump 解析 251ms → 165ms；`xo_init` 里 BaseX 模板解析 10.9ms → 7.5–8.2ms；
   - 格式错误（`=>` 缺尾随空格）现在返回非 0，不再静默丢枝；
   - 新增 `test/bashlib/test_x_rebuild_dump.sh`（29 条断言，含复杂多行 key/value 树）。
5. **x 树输入/输出契约**写进 `DEVELOP.md`（`4153ff6`）；
6. **性能测试机器记录 + 规则**（`12ae7ba`）：TODO 里记了机器 A（i3-N305）和单核跑分，
   DEVELOP 不变式 9 要求每个性能数字标注 CPU 型号。

### 3.2 性能基线（机器 A）

```
机器 A：Intel Core i3-N305（8 × E-core，无 P-core，1.8 GHz），
        16 GB LPDDR5-4800，Windows 11 26200，电源方案"平衡"
单核参考：PassMark ST ≈ 2072–2149；CineBench R23 ST ≈ 995；Geekbench 6 ST ≈ 1261
          （约主流桌面单核的 55–60%）

_play_game_tick ≈ 15–16 ms/帧（单 tick 成本 p50 ≈ 17.3 ms，p90 23.8）
render          ≈ 8–9 ms
合计 ≈ 24–26 ms；30fps 预算 33.3 ms，余量只有 ~8 ms
```

**关键结论（本周用探针测出来的）**：

- 卡顿主因是 **tick**：慢一帧就触发 2–5 个 tick 追赶，单帧 60–180ms；
- render 没有负优化（p50 7.9ms，与旧基线 8.2–8.5ms 一致）；
- 鼠标 SGR 解析每事件 ~2.5ms，拖拽时会叠加，但不是主因；
- **256 条积压上限从未命中**（cap=0）——不要再去修"积压跳旧位置"，那条路本机没发生；
- 60fps 在机器 A 上不现实（预算 16.6ms，tick 单独就超）；
- 换机器先读 CPU 型号，数字不可跨机比较。

### 3.3 下周第一步（已和用户约定）

用临时探针给 `_play_game_tick` 分段计时（默认关、测完就拆），找当前 15–16ms 里的大头；
目标 tick 17ms → 12ms 左右，把 30fps 余量从 8ms 提到 13ms。

**不要**：
- 不要把探针留进代码（上一轮 `play_game.sh` 的 `STRAFE_MOUSE_PROBE` 已经全部拆掉，
  `git diff --exit-code src/strafe_bash/game/play_game.sh` 必须干净）；
- 不要为了省 tick 去动 `render` 的层顺序或 `FB_*` 语义；
- 不要碰 `src/bashlib/x.sh` / `xo.sh` 的核心语义，除非先和老铁讨论。

### 3.4 2026-11-22 周末进展

周末没有继续游戏性能优化，主要做 `x` / `xo` 基础层的边界收口和测试补强。
详细提交见 `git log --oneline 12ae7ba..53d3932`。

**新增/调整**

1. **dataclass 容器模块**（`src/bashlib/data.sh`）：
   - `ARR / ASSOC / DTREE / ATREE` 四类；
   - 统一 `XO_DATA_CLASS_POOL` 和 `XO_DATA_CLASS_IDX`；
   - `xo_data_born_*`、`xo_data_bury`、`xo_data_is_live`、`xo_data_type`、
     `xo_data_clear`；
   - `data.sh` 是已跟踪源码，不再由 build 生成，也不在 `.gitignore` 中；
   - `test/bashlib/test_data_class.sh` 覆盖四类、pool、bury、clear。
2. **类调试树收口**：`xo_debug_classes` 改为函数内局部树，只打印到 stdout，
   不再保留全局 `XO_CLASS_DEBUG_TREE`。
3. **`xo_dcall`**：直接调用最终实现、跳过 `<Cls>_<method>` 透传层；
   已补注释和 `test_xo_dcall.sh`，覆盖 own / inherited / mixin / 参数透传。
4. **树类模板合并状态机**：
   - 非空容器不显式写，交给子节点建/合并；
   - 空容器先查父类现状，防止空对象覆盖普通标量；
   - 修正 `continue` 误用，区分模板 `type=UNKNOWN` 与父类 `node_type=UNKNOWN`；
   - 新增 `test_xo_class_merge.sh`，正向/反向齐全。
5. **轻量写入口文档**：`x_insert_dict` / `x_insert_token_dict` / `x_qinserts`
   明确 NULL/空容器前置条件与“调用方负责”的边界，不把它们改成完整校验。
6. **MSYS2 CR**：
   - `x_qinserts` 改为先声明、后赋值 `tr_insert_kv=("$@")`；
   - `x.sh` 顶部明确：MSYS2 只保证 value 的 CR；key 的 CR 不支持；
   - 新增 `test_msys2_cr.sh`，非 MSYS2 静默跳过，MSYS2 验证 workaround 和
     `x_qinserts` 的 CR 保存。
7. **`x_iter` 消费契约**：
   - 每行一个元组、字段独立 `@Q`；
   - 必须用 `local -a "tuple=($line)"` 重新解析，不能 `read -a` / awk；
   - `while read <<< ""` 会进入一次空行，已补 `[[ -n "$iter_str" ]]` 判断。
8. **生僻 x API 用例**：`test_x_rare_apis.sh`
   覆盖 `x_pop_leaf` / `x_shift_leaf` / `x_pop_tree` / `x_layer_get_flat` /
   `x_pop_to_flat_assoc` / `x_shift_to_flat_array` / `x_push_leaf_fast` /
   `x_get_arg_limits`。
9. **locale / 环境**：
   - `grammar.sh` 文件头和 `DEVELOP.md` 增加 locale 契约；
   - `LC_ALL` 已设置时只警告，不强行覆盖；
   - 记录参考部署环境，但不强制设置。
10. **宪法 / TODO**：
    - `for((;;))`、0/1 布尔 `(( flag ))`、多分支优先 `case`、local/unset 合并、
      参数展开等规则；
    - TODO 记录“等游戏稳定后统一整理 x/xo 注释”，当前不做。

**验证**

- `test_x.sh` 在 MSYS2（有 gobolt）下完整通过，包括 JSON、graft、flat；
- `test_x_rare_apis.sh` 通过；
- `test_xo_class_merge.sh`、`test_xo_tree_class.sh`、`test_xo_debug_classes.sh`、
  `test_xo_dcall.sh`、`test_data_class.sh`、`test_msys2_cr.sh` 通过。

**未做 / 下一次**

- 截至该日期，游戏 tick/render 性能优化尚未开始；后续已完成分桶、批量补脏等优化。
- `str_unescape` 的 `${var@E}` 只记录了未来方向，没有替换实现。
- `gobolt`（[common_tool](https://github.com/qindapao/common_tool)，从
  [Releases](https://github.com/qindapao/common_tool/releases/latest) 下载）
  的 NUL 限制未处理；
  NUL 是 Bash 字符串无法表示的数据，不是当前库的阻塞项。
- 全库注释整理继续延期到架构闭环之后。

---

## 4. 架构要点（够你快速定位）

### 4.1 主循环（`game/play_game.sh`）

- 三频独立：**输入**每轮排空；**逻辑 tick** 30Hz（`TICK_US`）；**渲染** 30Hz（`RENDER_US`）；
- `LOGIC_ACC_US` / `RENDER_ACC_US` 两个累加器；慢帧会一次跑多个 tick（追赶），这是卡顿放大器；
- 输入：Windows 用 `STRAFE_INPUT_POLL=1`（`read -t 0` 探测 + 自旋 `_idle_wait`），
  Linux 用 `read -t 0.002`；鼠标是 xterm SGR（1000/1002/1003/1006），逐字节解析；
- 渲染：`FRAME_BUF` 拼好整帧，`frame_flush` 一次 `printf`，外层 `DECSET 2026` 同步输出；
  **render 里禁止直接 printf**（宪法不变式），所有输出都进 `FRAME_BUF`。

### 4.2 渲染分层（`render/fb.sh`、`scene.sh`）

```
擦上一帧 → 我方子弹/敌弹 (FB_DIRTY, art 之前) → 敌人 art / HP 行
        → 掉落物 (FB_TOP, art 之后) → 飘字 → 玩家 → 电网 → 命中火花（最上层）
```

- `FB_CELL` 屏幕真值；`FB_OWNER` 每格最后写入者（死亡/清弹按归属清格）；
- `FB_DIRTY` / `FB_TOP` 两套脏格；`fb_emit` / `fb_emit_top` 负责输出；
- 掉落物只在移动时标脏，所以 art 每帧重画会盖住它 → 场景里每帧重画存活掉落物；
- 擦除/补脏有批量成本模型（`_ER_*`），重 art 帧自动选批量路径，轻帧走逐格。

### 4.3 xo 对象系统（`src/bashlib/xo.sh`）

- 每个实例是一个 assoc（`OBJ_n` / `OBJ_名字`），类由类对象 `{cls}Obj` 复制字段；
- **扁平类**：`declare -gA <Cls>Obj=( [{CLS}$X]=... [{SUP}$X]=... [字段]=... )`，
  字段是裸键；元键带 `$X`（`$'\034'`）；
- **树类**（FLT=0，只有 BaseX）：用 `readonly <Cls>StaticTemplate='...'`，
  模板由 `x_rebuild_from_dump` 解析成 x 树；
- **Mixin**：`M_XxxStaticTemplate` 只做声明（`{REQUIRES}`），不建对象；
- 初始化：按手工注册表（`XO_CLASS_FLAT_OBJ_VARS` / `XO_CLASS_TREE_TMPL_VARS` /
  `XO_CLASS_METHODS` / `XO_MIXIN_METHODS`）建继承树 → 按拓扑序建类对象 →
  生成转发方法；只有 `xo_init 1`（或 `-d`）才用 `compgen` 做反向校验。
  周末已把"自动扫描类变量"改成显式注册，正常 init 不再扫描变量名；
- 生命周期：`xo_obj_born` / `xo_obj_born_named`、`hire`/`fire`（复用）、`bury`（销毁）；
  组合对象（`Plane` 持有 `w1..w5`）只能 bury，不能 hire/fire；
- 派发：热路径 `"${XO_OBJ_POOL[$h]}_method" $h` 直调；事件路径 `xo_call`；
- 字段重置：`<Cls>ResetFields='prev_x prev_y color'`，fire 时只重置这些（`XO_RESET_*` 缓存）。

### 4.4 x 树（`src/bashlib/x.sh` / `xe.sh` / `xj.sh`）

- 模块拆分：`x.sh` 是核心树；`xe.sh` 是扩展 API（graft、leaf/tree push/pop/shift、
  flat 转换等）；`xj.sh` 是 JSON 层（`x_to_json` / `x_from_json` / gobolt 限流）；
- 依赖方向单向：`xe.sh` / `xj.sh` 都只 `source x.sh`，彼此不依赖；`x.sh`
  **不 source、不调用** `xe.sh` / `xj.sh`，核心树不依赖扩展和 JSON；
- 测试按需 source：用 JSON 的测试 source `xj.sh`，用 graft/pop/flat 的测试 source
  `xe.sh`；
- 一张 assoc 存整棵树：键是路径（token 用 `$X` 分隔），值是叶子或节点元数据；
- token：`{key}$X`（字典）、`[i]$X`（数组）、`<id>$X`（物理 token）；
- 节点类型：`OBJ/ARR/OBJ_EMPTY/ARR_EMPTY/LEAF/LEAF_NULL/UNKNOWN`；
- dump 格式：缩进 + `{key} => value`、数组行 `o = value`、多行用 `|` 续行、
  注释行、`max_index` 行（重建时剔除）；`=>` 后**必须有空格**；
- `x_rebuild_from_dump`：先清洗/去公共缩进/合并多行 → 第一遍算类型/层级/键值 →
  第二遍用 `tr_path_stack` + `tr_array_indexs` 批量 `x_qinserts`；
- 输入契约（见 DEVELOP `Input/output contract`）：合法 UTF-8、BMP、dense 数组、
  key 内 `}` 写 `\}`、不允许裸 `$X`、非法结构必须失败。

### 4.5 弹幕与碰撞

- 敌弹是 SoA：`EB_ALIVE/X/Y/VX/VY/STEP/CD/DMG/GLYPH/TAG/PHASE/SEEN/FUEL/VAR/BK0..3`；
- 直下弹按出生相位分 4 桶，每 tick 只处理 1/4；曲线/追踪弹按类型；
- 命中判定用 `FB_OWNER` 反查格子，替代"每弹 vs 玩家"遍历；
- 我方子弹在 tick 内联移动时清/写格；敌弹死亡按 OWNER 清格。

---

## 5. 老铁的工作方式与铁律（必须遵守）

完整版在 `CONSTITUTION.md`，这里是要点：

1. **不能影响帧率**：所有 BUG 修复/机制变更唯一硬原则——可以变好，不能变差。
   任何性能结论必须标注 CPU 型号（`Win32_Processor.Name` / `lscpu`），跨机数字不可比。
2. **只做根因修复**：不允许打补丁。没定位到根因就先不做，继续查。
3. **增量开发**：不要影响已有功能；不要过度设计。
4. **`x` / `xo` 库不要乱动**（除非他明确同意）：它们是基础层。
5. **不动暂存区**：不执行 `git add` / `git commit` / `git stash` / `git restore` /
   `git checkout -- <file>` / `git reset`；只改工作区，让他在 `git diff` 里逐条看。
   需要对照旧版本时，`git archive HEAD` 到 `/tmp` 或 `git show`，不要把 git 当草稿纸。
6. **注释必须独占一行**：代码行尾禁止 `# ...`；注释写被注释语句上一行，缩进一致。
   注释用中文，标识符英文；注释说明"为什么/契约/边界"，不逐行翻译语法。
7. **类定义规则**：扁平类只允许 `<Cls>Obj` 数组；树类只允许 `<Cls>StaticTemplate`；
   Mixin 只允许 `M_XxxStaticTemplate`。`*Obj` / `*StaticTemplate` 是保留后缀。
8. **输入契约**：合法 UTF-8；非 BMP 写字面字符；`\uXXXX` 只支持 BMP；
   非法输入是调用方违约，不做防御分支。
9. **提交**：用户自己提交。提交信息格式：短标题 + 3–6 行"为什么/影响" +
   `Signed-off-by: qindapao <northisland2017@gmail.com>` +
   `Co-authored-by: DeepSeek <noreply@deepseek.com>`。
10. **沟通风格**：直接、有数据、不绕弯；先给结论/测量，再给方案；不要空话；
    大改动先讨论数据模型再写代码；用户会仔细 review，要让他能看懂每一处改动。
    称呼"老铁"；不要谄媚，不要过度道歉。

---

## 6. 踩过的坑（省你重复踩）

- **MSYS 函数调用 ~16µs/次**，`read -rsn1` 每字节 ~100µs；热路径要减少调用/逐字节读。
  `read -t 0` 在管道上行为怪异（可能空转），游戏里只对终端用。
- **`compgen` 本身 ~1ms，但命令替换 fork ~20ms**（bash 5.2 无 `-V`）；
  类扫描用一次 `compgen` + extglob 交替过滤，别再拆成两次。
- **`${arr[*]@K}`**：输出是"key value"成对、每对相邻；hash 顺序随机但配对不散；
  `declare -A "X=(${a[*]@K} ${b[*]@K})"` 后者覆盖前者——已验证；
  `@K` 的引号只在 `declare` / `eval` 重新解析时生效，不能拿去裸展开。
- **关联数组顺序随机**，别把 dump 当规范化文本逐字节比；比较结构/键值。
- **Python 写文件默认会转 CRLF**（Windows），写 Bash 源码时用 `newline='\n'`；
- **没有 `.in` 源文件，也没有生成物**：所有 `.sh` 都直接进 git；`build.sh` 只保留为空操作兼容入口。
- **`test_bash_array.sh` 计时断言在负载下会假失败**；`test_x.sh` 需要 bash 5.3 + gobolt。
- **终端游戏不能管道跑**：`stty` 需要真 tty；交互验证只能让老铁跑。
- 之前为了 A/B 用 `git stash` 把用户的暂存区弄丢过一次——**绝对不要再这么干**。

---

## 7. 待办与开放问题

- [P0] 下周：`_play_game_tick` 分段计时，定位 15–16ms 的大头，目标 12ms；
- [ ] 60fps 只在新 CPU（单核 ~2×）上现实，机器 A 上不作为目标；
- [ ] `TODO.txt` 里还有渲染/弹幕的递减收益项（P2 之后），按数据决定做不做；
- [ ] Tcl 9 迁移是**独立项目**（`D:\code\tcl_fun` 是工具库 `tutils`，不是游戏框架）；
  已看过并做了 Tcl 9.1 / Bash / Go / C 基准；架构决策见 `TODO.txt` 的 Tcl 9 章节。
- 文档状态：`DEVELOP.md`、`TODO.txt`、`CONSTITUTION.md` 都是最新，且已提交。

---

## 8. 你接手时建议的开场

1. `git log --oneline -10` + `git status --short`；
2. 读 `CONSTITUTION.md`（10 分钟）；
3. 读 `DEVELOP.md` §1.5 全局变量、`The xo object system`、`The x tree`、`Input/output contract`；
4. 读 `TODO.txt` 顶部"测试机器"和性能基线；
5. 问老铁这次要做什么；如果要动性能，先读 CPU 型号、先量再改。

> 最后一句：这个项目的代码质量要求高、用户 review 很细；宁可慢一点、量清楚，
> 也不要"感觉快了"就提交。
