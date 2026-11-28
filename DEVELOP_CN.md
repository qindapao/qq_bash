[English](DEVELOP.md) | 简体中文

# DEVELOP — qq_bash internals

`qq_bash` 的开发笔记：项目是干什么的，`xo` 与 `x` 如何工作，游戏的类树，测试/运行流程，以及 Bash 版本的规则。面向玩家的文档在 [README_CN.md](README_CN.md)；项目约定在 [CONSTITUTION.md](CONSTITUTION.md)。

---

## 架构一览

改代码之前先读这一节：它是整个系统的地图。下面各节会逐个主题展开细节。示意图一律用纯 ASCII 绘制，因此在任何编辑器、终端或 diff 查看器里都能保持对齐。

### 1.1 分层

```text
+----------------------------------------------------------------------------+
| GAME LAYER  src/strafe_bash/                                               |
|   cli.sh              command line entry (-h prints the version)           |
|   intro.sh            title screen, plane choice, controls                 |
|   game/main.sh        main loop: tick + render per frame                   |
|   game/play_game.sh   all per-tick game logic (pipeline in 1.3)            |
|   game/init_game.sh   resets globals for a new run                         |
|   render/scene.sh     scene rendering (pipeline in 1.4)                    |
|   save/save.sh        save/load, versioned (v1.x.y only)                   |
|   config/version.sh   single source of the version string                  |
|   config/const.sh     tunable constants (screen, limits, waves, boss)      |
|   config/globals.sh   all runtime state (object lists, counters, waves)    |
|----------------------------------------------------------------------------|
| CLASS LAYER  src/strafe_bash/classes/   (template + _methods per class)    |
|   base_types.sh   Entity (root of movers), BulletType*, Drop, Word         |
|   projectiles/    Bullet, EnemyBullet, BossBullet, Missile, EnemyMissile   |
|   enemies/        EnemyQ/V/M/B, BossBase, Boss, BossSpinner, SkullKing     |
|   plane/          Plane -> PlaneIl2, owns OBJ_wpn1..5 (composite object)   |
|   pickups/        Drop, Word                                               |
|----------------------------------------------------------------------------|
| OBJECT SYSTEM  src/bashlib/xo.sh                                           |
|   flat class: <Cls>Obj array (direct, the only flat definition)            |
|   tree class: template --xo_init--> ${cls}Obj (x tree); templates are      |
|               allowed only for tree classes (FLT=0)                        |
|                                   +-- KV snapshot ${cls}ObjStr             |
|   instance = one assoc array; flat keys "field", tree keys "{field}\x1c"   |
|   lifecycle   born / hire / fire / bury                                    |
|   hooks       <cls>_born (enters the world)  <cls>_retire (leaves it)      |
|   dispatch    xo_call (class method)  xo_obj_call (capability, first wins) |
|               xo_obj_call_all (hook fan-out, no fallback to class)         |
|   mixins      {OBJMIX} field + XO_OBJ_METHOD routing (boss abilities)      |
|   market      where fired objects wait; hire reuses them first             |
|----------------------------------------------------------------------------|
| DATA STRUCTURE  src/bashlib/x.sh                                           |
|   x tree: node ids, .c child table, .s order, <id>.k key, <id> value       |
|   x_walk / x_dump / XO_CLASS_INHER_TREE (class inheritance)                |
+----------------------------------------------------------------------------+
```

### 1.2 对象生命周期

四个动词，两个钩子。真正的"生死"只有 born/bury；hire/fire 属于存储层的复用。

```text
      xo_obj_born / xo_obj_born_named
      one declare -gA from the class KV string
                      |
                      v
      +------------------------------------------+
      | ALIVE   (registered in XO_OBJ_POOL)      |
      +------------------------------------------+
           |                              |
           | xo_obj_fire                  | xo_obj_bury
           v                              v
      +------------------------------------------+
      | 1 <cls>_retire   (both exits share it)   |
      | 2 drop object-level mixin routes         |
      | 3 reset volatile fields (fire only)      |
      | 4 fire: push to XO_RES_MARKET            |
      |   bury: unset the variable + leave pool  |
      +------------------------------------------+
           |                              |
           v                              v
   fire -> IDLE (XO_RES_MARKET)   bury -> GONE (no variable)
           |
           +---- xo_obj_hire ----> ALIVE
```

硬性约束：

- **组合对象只能 bury。** 一个拥有其他对象的类（目前只有 `Plane`，它的 `{w1}..{w5}` 字段保存武器句柄）必须与它的子对象一起消亡。retire 钩子无法判断自己是在 bury 还是 fire 中运行，因此对组合对象执行 fire 会让父对象继续存活，而它的子对象句柄变成悬空。
- **调用方必须在 fire 之前把句柄从自己的数组里移除**，并且在使用句柄之前先检查 `XO_OBJ_POOL`。
- **市场为空时，hire 与 born 完全相同**，所以从不 fire 的代码行为与以前一模一样。

### 1.3 单帧逻辑流水线（`_play_game_tick`）

```text
 0      bonus timers decay (invulnerability, slow, laser, ...)
 0.5    expired weapons check
 1      cooldowns decay (fire, missile, bomb)
 2      player movement (keyboard/mouse direction -> new position)
 3      player fire            -> xo_obj_born Bullet
 4      player missile launch  -> xo_obj_born Missile
 5      every live object moves (bullets, enemies, missiles, drops, words)
 ----
 5.5    scanning waves advance (per slot: row, gaps, player hit)
 5.6    wave sweep clears bullets in the band it swept this tick
        (boss wave clears ours; player wave clears enemy bullets/missiles)
 ----
 6      enemy snapshot (geometry/hp/score shared by all later collisions)
 7      our bullets vs enemies
 8      our missiles vs enemies
 8.5    our waves vs enemies (once per wave per enemy)
 9      clean up what was hit (mark first, bury together)
 9.5    player damage (incl. G_WAVE_DMG_PENDING, i-frames, shield)
 10     drop pickup           10.5  word pickup
 11     death check
 12     enemy spawning (throttle counters + boss dry period)
 13     drop spawning         14    floating word spawning
```

### 1.4 渲染流水线（`render`）

```text
 phase 1  erase the prev cell of every live object
          waves: erase every slot old row first, then draw every current
          row (two passes, so overlapping waves cannot erase each other)
 phase 2  draw the cur cell of every live object (plus HUD, fx, banners)
 phase 3  draw the player last (topmost layer)
 ----
 one single flush of FRAME_BUF to the terminal per frame
```

### 1.5 全局变量

框架全局变量按归属分组，前缀即来源：`XO_`/`xo_` 属于对象系统，`X_` 属于树系统，`RES_` 属于资源市场，`_BASHLIB_IMPORTED` 是导入守卫。这些名字归框架所有：用户代码不得在这些命名空间中定义变量，`*Obj` / `*StaticTemplate` 后缀是保留的（见 CONSTITUTION.md §3）。

**对象系统（`xo.sh`）——类定义与继承**

| 变量 | 用途 |
|---|---|
| `BaseObj` | `Base` 类的类对象（框架根；`{CLS}$X=Base`，`{FLT}$X=1`） |
| `BaseXStaticTemplate` | `BaseX` 的模板，也是框架里唯一的树类（`FLT=0`） |
| `${cls}Obj` | 每个类的类对象。扁平类**由这个数组定义**（唯一来源）；树类由模板构建 |
| `${cls}ObjStr` | 类对象的 KV 快照；born 时用它做一次 `declare -gA`（开销大的那一步） |
| `${cls}StaticTemplate` | 仅树类（FLT=0）才有模板。扁平类若使用模板，`xo_init` 会失败 |
| `${cls}ResetFields` | 可回收类的易变字段；fire 只重置这些字段（例如 `prev_x prev_y color`） |
| `XO_CLASS_INHER_TREE` | 类继承链（x 树）；`xo_init` 用它构建派发表 |
| `XO_METHOD_INHERITED` | 继承方法的转发表 |
| `XO_INHER_CHAIN_DUMP_CACHE` | 缓存的继承 dump，避免重复计算 |
| `XO_CLASS_TREE_TMPL_VARS` | 手工登记的树类模板名 |
| `XO_CLASS_FLAT_OBJ_VARS` | 手工登记的扁平类对象名 |
| `XO_CLASS_METHODS[class]` | 手工登记的、各归属类自己的公开方法 |
| `XO_FLAT_META` | 构建扁平类时保留的元键（其余一切都算用户字段） |
| `_XO_INIT_CALLED` | `xo_init` 只能运行一次 |

**对象系统（`xo.sh`）——实例、Mixin、资源市场**

| 变量 | 用途 |
|---|---|
| `XO_OBJ_POOL[handle]` | 句柄 -> 类。活对象的唯一登记表；所有"是否存活"的判断都用它 |
| `XO_OBJ_SEQ` | 匿名句柄计数器，产出 `OBJ_11`、`OBJ_12`…… |
| `XO_MIXIN_METHODS[mixin]` | 手工登记的、每个 mixin 提供的公开方法 |
| `XO_OBJ_METHOD[handle\|method]` | 每个对象的方法路由（mixin 实现名） |
| `XO_OBJ_MIXED[handle]` | 携带 mixin 的对象集合（廉价的闸门：集合为空时 bury 只做一次长度检查） |
| `XO_RES_COUNT[class]` | 资源市场：该类的空闲实体数量 |
| `XO_RES_MARKET["class\|index"]` | 资源市场：空闲句柄，O(1) 的 LIFO |
| `XO_RES_LIMIT[class]` `XO_RES_LIMIT_DEFAULT` | 每类回收上限 / 默认 512 |
| `XO_RESET_FIELDS[class]` | 缓存：类重置列表，从 `<cls>ResetFields` 复制而来 |
| `XO_RESET_DEF["class\|field"]` | 缓存：易变字段的模板默认值，从类对象读取 |
| `XO_RESET_READY[class]` | 缓存：标志位，重置列表已预处理（惰性，首次 fire 时） |

**数据类（`data.sh`）**

| 变量 | 用途 |
|---|---|
| `XO_DATA_CLASS_POOL[handle]` | 句柄 -> `ARR` / `ASSOC` / `DTREE` / `ATREE`；一次查表同时得到存活状态与种类 |
| `XO_DATA_CLASS_IDX` | 单调递增的句柄计数器（`xo_data_clear` 从不重置它） |

**初始化进度（诊断用，默认关闭）**

| 变量 | 用途 |
|---|---|
| `XO_INIT_PROGRESS` | 1 = 在 `xo_init` 期间绘制"loading classes"进度条 |
| `XO_INIT_PROGRESS_FD` | 进度条写入的 fd（默认 2） |
| `XO_INIT_TOTAL` / `XO_INIT_DONE` | 待构建的类定义数 / 已构建的类数 |
| `XO_PROGRESS_BAR_MAX` | 进度条的最大宽度（字符格） |

**树系统（`x.sh`）**

| 变量 | 用途 |
|---|---|
| `X` | 树路径各段之间的键分隔符 `$'\034'` |
| `X_ROOT_ID` | 根节点 id（1） |
| `X_TYPE_OBJ` `X_TYPE_ARR` | 树容器类型 |
| `X_NODE_KIND_OBJ` `X_NODE_KIND_ARR` `X_NODE_KIND_OBJ_EMPTY` `X_NODE_KIND_ARR_EMPTY` `X_NODE_KIND_LEAF` `X_NODE_KIND_LEAF_NULL` `X_NODE_KIND_UNKNOWN` | `x_get_node_type` 返回的节点种类 |
| `X_VALUE_NULL` `X_VALUE_TRUE` `X_VALUE_FALSE` `X_VALUE_NULL_OBJ` `X_VALUE_NULL_ARR` | 哨兵值 `null\034`、`true\034`、`false\034`、`{}\034`、`[]\034` |
| `X_FLAT_IS_MATCH` `X_FLAT_IS_NOT_MATCH` `X_FLAT_ARRAY_NULL` `X_FLAT_ASSOC_NULL` | 扁平与树的比较结果 |
| `X_GOBOLT_JSONTYPENULL` `X_GOBOLT_JSONTYPETRUE` `X_GOBOLT_JSONTYPEFALSE` `X_GOBOLT_JSONTYPENUMBER` `X_GOBOLT_JSONTYPESTRING` `X_GOBOLT_JSONTYPEARRAY` `X_GOBOLT_JSONTYPEOBJECT` `X_GOBOLT_JSONTYPEUNKNOWN` | gobolt 转换使用的 JSON 类型 id 1..8 |
| `X_RET_ENUM_OK` | 成功（0） |
| `X_RET_ENUM_KEY_IS_TREE` `X_RET_ENUM_KEY_IS_LEAF` `X_RET_ENUM_KEY_IS_NOTFOUND` `X_RET_ENUM_KEY_IS_INVALID` `X_RET_ENUM_KEY_OUT_OF_INDEX` `X_RET_ENUM_KEY_IS_NOT_LEAF` `X_RET_ENUM_KEY_IS_NULL` `X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH` `X_RET_ENUM_KEY_CHILD_CNT_IS_ZERO` `X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED` `X_RET_ENUM_KEY_BJSON_TYPE_INVALID` `X_RET_ENUM_KEY_BJSON_TYPE_OBJ` `X_RET_ENUM_KEY_BJSON_TYPE_ARR` `X_RET_ENUM_KEY_PARAMETER_LENGTH_EXCEEDS_LIMIT` | 每键状态码 1..14 |
| `X_RET_ENUM_TREE_IS_INVALID` `X_RET_ENUM_TREE_IS_EMPTY` `X_RET_ENUM_TREE_NOT_HAVE_ROOT` `X_RET_ENUM_TREE_IS_NOT_SAME` | 整树级失败 50..53 |

`X_FLAT_*` 在 `xe.sh` 中声明；`X_GOBOLT_*` 以及 BJSON/参数类返回码在 `xj.sh` 中声明。用哪个常量就 source 拥有它的模块。`X_RET_ENUM_KEY_IS_TREE` 目前未被使用，但作为保留返回码留着；不要复用它的值。

**库返回片段（`grammar.sh`）**

旧的 `_ret_*` 兼容片段已禁用，也不再导出。要移动 `REPLY` 就用显式赋值，或者在函数边界使用 nameref/输出变量；不要重新引入 `eval "${_ret_*/...}"` 的用法。

**导入守卫与运行时元数据**

| 变量 | 用途 |
|---|---|
| `_BASHLIB_IMPORTED[module]` | 每个库模块的一次性 source 守卫（`grammar`、`var`、`str`、`array`、`float`、`x`、`xe`、`xj`、`data`、`xo`）；值统计导入尝试次数，上一次的值非零则提前返回 |
| `BASH_GRAMMAR[...]` | `grammar.sh` 探测出的运行时 bash 能力开关；不存在构建期的 `#@if` 步骤 |
| `_STR_BUILT_IN_THRESHOLDS` | `str.sh` 中用于选择内建还是外部工具的阈值 |

三张 `XO_RESET_*` 表是每类一份的惰性缓存，在该类第一次 `fire` 时填充，之后不再重建：

```text
fire(Bullet) with XO_RESET_READY[Bullet] unset
   |
   +-- read BulletResetFields = "prev_x prev_y color"
   +-- XO_RESET_FIELDS[Bullet]       = "prev_x prev_y color"  (which fields)
   +-- XO_RESET_DEF["Bullet|prev_x"] = 0                      (their defaults,
   +-- XO_RESET_DEF["Bullet|prev_y"] = 0                       straight from
   +-- XO_RESET_DEF["Bullet|color"]  = ""                      the template)
   +-- XO_RESET_READY[Bullet]        = 1                      (prepared)

every later fire: 3 hash lookups + 3 writes (~20us) instead of
declare -p + indirect lookup per field on every single fire.
```

**游戏运行时（`config/globals.sh`、`config/const.sh`）**

活对象句柄列表，每帧重建（先收集，再统一清理一次）：`BULLETS`、`ENEMY_BULLETS`、`MISSILES`、`ENEMIES`、`DROPS`、`WORDS`。

| 变量 | 用途 |
|---|---|
| `MISSILE_TRAIL_CLEAR` | 导弹尾迹还需要擦除的格子数 |
| `HIT_FX`, `BOMB_FX_POS`, `BOSS_DEATH_POS` | 命中火花、炸弹与 Boss 死亡特效队列 |
| `BOSS_DEATH_*` | Boss 死亡动画状态（帧、样式、中心、波次） |
| `CLEAR_BANNER_*` | "ACE" 横幅的剩余帧数与文字 |
| `FRAME_BUF` | 整帧输出缓冲；渲染只追加，每帧 flush 一次 |
| `RENDER_FPS`, `RENDER_US` | 渲染节奏：每秒帧数及其周期（微秒） |
| `G_FIRE_CD`, `G_MISSILE_CD`, `G_MISSILE_SIDE` | 玩家开火/导弹的节奏与左右交替 |
| `G_INV` | 玩家无敌帧（闪烁与免伤） |
| `G_DX`, `G_DY`, `G_MOUSE_ON` | 输入方向与鼠标模式 |
| `G_WANT_BOMB`, `G_FREE_BOMB` | 炸弹请求（付费 / 免费） |
| `G_ENEMY_TICK`, `G_DROP_TICK`, `G_WORD_TICK` | 各类生成节奏（每 N 帧一次） |
| `G_B_DRY`, `G_BOSS_DRY` | 小怪 / Boss 的空窗期，用来控制稀有度 |
| `G_RUN_TICKS` | 本局已运行的帧数（特效、无敌帧、存档、诊断） |
| `G_KILLS`, `G_BOSS_KILLS` | 击杀计数（计分） |
| `G_LAST_ESCAPE_TICK`, `G_LAST_ACE_TICK` | 两种奖励横幅的冷却 |
| `G_GAME_OVER` | 死亡标志；主循环据此结束本局 |
| `G_WAVE_DMG_PENDING` | 本帧所有波次命中玩家造成的伤害，在伤害阶段统一结算一次 |
| `WAVE_SLOTS` | 波次槽位数量（5 = Boss 爆发 4 + 玩家 1） |
| `WAVE_ON` | 派生标志：是否有波次存活（热路径提前返回，从不手工维护） |

**波次槽位表（每个波次一项）**

| 变量 | 用途 |
|---|---|
| `WV_ON[slot]` | 该槽是否在用 |
| `WV_Y[slot]`, `WV_DIR[slot]` | 当前行 / 方向（Boss 为 +1 向下，玩家为 -1 向上） |
| `WV_OWNER[slot]` | 0 = Boss（命中玩家、清除我方子弹），1 = 玩家（命中敌人、清除敌方子弹） |
| `WV_DMG[slot]` | 该波次的伤害 |
| `WV_CD[slot]` | 计数器，每 `WAVE_STEP_TICKS` 前进一行 |
| `WV_LAST_Y[slot]` | 渲染记账：上一帧绘制的行（-1 = 从未绘制） |
| `WV_HIT[slot]` | 该波次是否已命中玩家（每波一次） |
| `WV_GAP1[slot]`, `WV_GAP2[slot]` | 逃生缺口（字符串索引，0 = 屏幕第 2 列；玩家波次为负） |
| `WV_CLEAR_LO[slot]`, `WV_CLEAR_HI[slot]` | 本帧扫过的行带（清弹需覆盖换行交换的情况） |
| `WV_CLR[slot]`, `WV_LINE[slot]` | 颜色转义 / 整行字符 |
| `WAVE_HIT_ENEMY["slot\|enemy"]` | 命中表：每波每个敌人各一次 |

**常量（`config/const.sh`、`config/version.sh`）**

- **屏幕 / 节奏**：`SCREEN_W`、`SCREEN_H`、`FPS`、`TICK_US`、`GAME_TOP`
- **上限**：`ENEMY_LIMIT`、`PLAYER_BULLET_LIMIT`、`ENEMY_BULLET_LIMIT`、`BOSS_BULLET_LIMIT`、`DROP_LIMIT`、`WORD_LIMIT`、`HIT_FX_LIMIT`、`BOSS_LIMIT`
- **波次**：`WAVE_STEP_TICKS`、`WAVE_SYMBOL`、`WAVE_GAP_COUNT`、`WAVE_GAP_W`、`BOSS_WAVE_DAMAGE`、`BOSS_WAVE_STRIP_SHIELD`、`PLAYER_WAVE_DAMAGE`、`BOSS_WAVE_BURST_MIN/MAX`、`BOSS_WAVE_GAP_MIN/MAX`
- **Boss 能力**：`BOSS_INV_TICKS`、`BOSS_BUFF_MAX`、`BOSS_BUFF_INV_ON/OFF`、`BOSS_BUFF_HEAL_WAIT`、`BOSS_BUFF_MISSILE_*`、`BOSS_BUFF_SLOW_*`
- **SkullKing**：`SKULL_KING_ROW_BULLETS`、`SKULL_KING_RADIAL_BULLETS`、`SKULL_KING_WAVE_BULLETS`、`SKULL_KING_BURST_RINGS`、`SKULL_KING_RING_GAP`、`SKULL_KING_REST`、`SKULL_KING_FIRST_SHOT`
- **奖励**：`BONUS_T2/T3/T4/T5`、`BONUS_MT`、`BONUS_LT`、`BONUS_ST`、`BONUS_SLOW`、`CLEAR_SCORE_BONUS`、`BOSS_SCORE_BONUS`
- **外观**：`FRAME_H`、`FRAME_V`、`FRAME_TL/TR/BL/BR`、`LOCALE_UTF8`
- **版本 / 存档**：`STRAFE_VERSION`（`version.sh`）、`STRAFE_SAVE_FILE`

### 1.6 不变量（改代码前必读）

1. **活对象一定在 `XO_OBJ_POOL` 里。** 使用句柄前先查池，否则你可能会操作到空闲或已死亡的对象。
2. **在 `bury`/`fire` 之前**，调用方必须已把句柄从自己的数组里移除（`BULLETS` 等数组每帧重建，因此这一点自然成立）。
3. **组合对象只 bury，不 fire**：父与子一起消亡。`hire`/`fire` 只用于简单对象。
4. **每帧只 flush 一次。** 渲染只往 `FRAME_BUF` 追加内容；渲染函数里绝不直接 `printf` 到终端。
5. **热路径上不 fork**：不用 `$(...)`，不用外部命令（`sort`、`grep`、`awk`）；只用 bash 内建。
6. **按对象循环时内联派发。** 在遍历活对象的循环里写 `"${XO_OBJ_POOL[$obj]}_move" "$obj"` 而不是 `xo_call "$obj" move`：表达式完全相同，多态依然来自池查询，但省掉了一层包装函数（每个对象每帧约 20 us）。`xo_call` 保留给一次性调用（玩家、帧），那里不在乎这层包装。永远不要硬编码类名（`Bullet_move`）——那会破坏子类覆盖。
7. **类定义和类对象是只读的**（扁平 `<Cls>Obj` 数组、树类模板、已构建的类对象）；实例是每个对象一个关联数组：扁平键 `field`，树键 `{field}\x1c`。
8. **先标记，后统一清理**：碰撞只设置 `killed_*` 标志；清理阶段统一 bury 所有对象。
9. **任何机制改动都要测量**：用固定负载的测量脚本对比改动前后；"感觉更快了"不算证据。每个性能数字都必须注明测量所用的 CPU 型号（Windows 上取 `Win32_Processor.Name`，Linux 上取 `lscpu`）；不同机器的数字不可比，也不能作为验收证据。
10. **关联数组：固定键集合用复合 `+=`。** 一次写入多个字面键——`self+=([x]=$2 [y]=$3 [symbol]=$4 ...)`——是允许的，而且为了可读性更推荐：一次赋值代替 N 次，在按调用计的微基准里指令数少约 10%。这*不是*性能论据（收益约为每键 0.5 µs，只有在每秒数万次调用时才看得出来）。规则：
    - 目标必须已经声明为 `declare -A`；否则 `+=` 会把它当成索引追加（静默变成错误的类型）；
    - 绝不要对并行的索引式 SoA 数组（`EB_X`、`EB_Y`、`EB_ALIVE` 等）使用 `+=`：那会在末尾追加，打乱列的对齐；
    - 不要用动态键拼复合赋值：那需要字符串拼接或 `eval`，既慢又不安全。用普通循环代替。
    （关联数组的复合 `+=` 需要 bash 4.3+；兼容下限是 bash 4.4.23，因此在那里可用；推荐目标是 bash 5+。）

---

## 目的与范围

`qq_bash` 首先是一个用来验证 `xo` 对象系统的项目。`strafe_bash` 的存在是为了证明 `xo` 能建模一个真实、有状态、可交互的应用：具名对象、继承、mixin、生命周期、组合，以及在固定游戏循环下的方法派发。

`xo` **不是性能库**。它面向的归宿是 Bash 自动化的控制面：构建流水线、工业测试台架、部署步骤、测试夹具，以及小型 DSL。它用一点内存和派发开销，换取嵌套数据、继承、mixin 与可读的组合方式。它不打算用于高吞吐数据处理、实时引擎，也不适合处理不可信输入。

## Bash 版本现状

`strafe_bash` 的 Bash 版本是**主开发目标**，并且没有做特性冻结。新机制、新系统、清理工作都可以落在这里；Tcl 9 迁移仍是未来的探索，不阻塞 Bash 侧的开发。

30 FPS 的目标是有意为之。Bash/MSYS 的性能限制是可以接受的；这个游戏是验证用的展示品，不是性能基准测试。

兼容下限是 **Bash 4.4.23**。它应当能启动并游玩，但达不到 5.x 的帧率：4.4 没有 `EPOCHREALTIME`，所以游戏改用 `/proc/uptime`（10 毫秒精度），当该文件不可用时回退到 `date`/`SECONDS`。仍建议使用 UTF-8 locale；没有的话，非 ASCII 输出和对 UTF-8 敏感的辅助函数会退化。Bash 5.0+ 是推荐且经过性能测试的目标。

## Locale 要求

Bash 的字符串长度（`${#s}`）、切片（`${s:i:1}`）和排序比较（`[[ a < b ]]`）依赖不同的 locale 类别：

| 需求 | 类别 |
|---|---|
| UTF-8 字符长度/切片 | `LC_CTYPE` 必须是 UTF-8 locale |
| 确定的 ASCII 排序 | `LC_COLLATE=C` |
| 以上两者都需要 | `LC_ALL` 必须为空，或者是一个合适的 UTF-8 locale |

`LC_ALL` 会覆盖其他所有 `LC_*`。导入时，`grammar_set_locale`：

- 检查 Bash 真的按 UTF-8 字符（而不是字节）来识别输入；
- 只在 `LC_ALL` 为空时才设置 `LC_COLLATE=C` 和一个 UTF-8 的 `LC_CTYPE`；
- 如果 `LC_ALL` 已经设置，则给出警告并保持不变，而不是悄悄改掉调用方的全局环境。

必须按字节处理的代码（`str_bytes`、ASCII 数组排序）使用 `local LC_ALL=C`。工业部署要么 unset `LC_ALL`，要么在导入库之前设置一个 UTF-8 的 `LC_ALL`；纯 ASCII 部署可以忽略 UTF-8 需求。

## 未来

长期方向是 **Tcl 9 迁移**，跟踪在 `TODO.txt` 的 Tcl 9 章节里。Bash 版本仍然是行为、数值和美术的参考。只有同等负载的微基准（200 子弹的帧、100×30 diff 渲染、输入轮询）表明 Tcl 9 能守住帧预算之后，迁移才会开始；在这项决定做出之前，新机制仍然落在 Bash 版本里。

Tcl 9 的设计**不是**"到处 TclOO"或"到处 AoS"。当前方向：长期存活的对象和池化的小对象用 TclOO（复用 `hire`/`fire` 的思路，只重置易变字段），而极端批量/粒子负载保留 AoS/SoA 作为经过 profile 的后备方案。TclOO 创建对象的开销很大；要避免的是每次生成都分配，而不是 TclOO 本身。

## `xo` 对象系统

`xo` 为 Bash 提供了一个小而实用的对象模型。每个对象都是 `XO_OBJ_POOL` 中的一个关联数组；扁平类直接声明为 `<Cls>Obj` 数组。

```bash
declare -gA EnemyObj=(
    [{CLS}$X]=Enemy
    [{SUP}$X]=Entity
    [{MIX}$X]=''
    [x]=0
    [y]=0
    [hp]=1
)

Enemy_born () {
    local -n self=$1
    self[x]=10
    self[y]=5
}

Enemy_move () {
    local -n self=$1
    self[y]=$(( ${self[y]} + 1 ))
}

# Explicit registration is required before xo_init.
XO_CLASS_FLAT_OBJ_VARS[EnemyObj]=1
XO_CLASS_METHODS[Enemy]='born move'

xo_init
xo_obj_born Enemy      # -> REPLY=OBJ_1
xo_call "$REPLY" move
```

树类是例外：它们为嵌套数据而生，因此用模板声明，并在 `xo_init` 时构建成一棵 `x` 树（模板文本只解析一次，之后只保留类对象）：

```bash
readonly DivisionStaticTemplate='
    DivisionObj ->
        {CLS} => Division
        {SUP} => BaseX
        {MIX} => 
        {FLT} => 0
        {name} => unnamed
        {teams} => 
'

Division_born () {
    local -n self=$1
    # 树类实例用 {field}$X 键；嵌套节点走 x_tree 路径
    self["{name}$X"]=${2:-unnamed}
}

# Tree classes register their template name and own public methods too.
XO_CLASS_TREE_TMPL_VARS[DivisionStaticTemplate]=1
XO_CLASS_METHODS[Division]='born'
```

- `{FLT} => 0` 标记这是一个树类；扁平类从不设置它（它们从 `Base` 继承 `FLT=1`）。`Division` 继承自 `BaseX`，也就是树的根。
- 树类模板中允许嵌套对象和数组。数组元素使用 dump 语法（`o = value`）；框架会按类把它们实体化。对于大的可变默认值，优先使用空容器或在 `<Cls>_born` 里创建的字段，因为每个实例都会复制类对象的默认树。
- 模板格式：一行头（`DivisionObj ->`），后面跟若干 `{field} => default` 行，允许 `#` 注释。值会反转义一次（`\\` 变成 `\`）。
- 树实例使用 `{field}$X` 键；扁平实例使用普通键（见上面的 `EnemyObj` 例子）。
- 用模板声明的扁平类、或者声明成数组的树类，都会让 `xo_init` 失败；没有兼容路径。

关键要点：

- **显式登记是强制性的。** 每个扁平类都必须把它的对象数组加入 `XO_CLASS_FLAT_OBJ_VARS`；每个树类都必须把模板加入 `XO_CLASS_TREE_TMPL_VARS`；每个类都必须把自己的公开方法列进 `XO_CLASS_METHODS[<class>]`；每个 mixin 都必须把公开方法列进 `XO_MIXIN_METHODS[<mixin>]`。
- **不要预先列出继承来的或由 mixin 注入的方法。** 一个类的方法列表只包含该类自己定义的方法。`xo_init` 按以下顺序把 mixin 方法和继承方法追加到有效列表：自身方法、mixin、继承方法。
- **登记表就是唯一事实来源。** `XO_CLASS_METHODS` 决定什么会被继承、`xo_class_methods_print` 显示什么。一个方法函数存在但没登记的类，属于违约。
- **不要把父类方法拷进子类的登记表。** 当不存在 `Child_foo` 函数时，`-d` / `xo_init 1` 会拒绝 `XO_CLASS_METHODS[Child]='foo'` 这样的子类条目；扫描会比较声明列表与子类自己的 `Child_*` 函数。
- **重名方法会被校验拒绝。** `-d` / `--debug`（或 `xo_init 1`）会运行 `compgen` 反向检查，并拒绝任何类或 mixin 方法列表中的重名。
- **扁平类只有一种定义方式**：`<Cls>Obj` 数组。元数据键带 `$X` 分隔符（`{CLS}$X`、`{SUP}$X`、`{MIX}$X`、`{FLT}$X`）；用户字段是普通键。`xo_init` 会拒绝用模板声明的扁平类，也会拒绝声明成数组的树类。
- **模板**（`<Cls>StaticTemplate`）只存在于树类（FLT=0）。
- **Mixin 声明**保持为 `M_XxxStaticTemplate`（仅声明，从不构建成对象：模板比数组更省内存）。FLT 兼容性检查会从中读取 `{REQUIRES}`。
- **单继承** —— 类获得父类的字段和方法。
- **Mixin** —— `{MIX}` 列出纯方法 mixin；类方法优先，然后 mixin，然后继承方法。下面的 Il-2 列表就是现成的例子。
- **具名对象** —— `xo_obj_born_named OBJ_plane Plane` 用于获得稳定的句柄。
- **对象池** —— `XO_OBJ_POOL[OBJ_7]` 存的是类；`xo_obj_bury` 释放它。
- **派发** —— `xo_call "$obj" move`；用 `Enemy_move`、`Boss_move` 等特化。
- **类型检查** —— `xo_is_a "$obj" BossBase`。

### 类调试视图（`xo_debug_classes`）

要同时调试类的继承、字段、方法和 mixin，用：

```bash
xo_debug_classes        # indent 4
xo_debug_classes 2      # indent 2
```

它要求 `xo_init` 已经运行过。它构建一棵**临时的局部树**，并用 `x_dump` 打印。函数返回时这棵树即被丢弃；不会留下全局的调试树。

它**不会**修改 `XO_CLASS_INHER_TREE`、`XO_INHER_CHAIN_DUMP_CACHE`、类对象或方法表。

树的形状如下：

```text
{Base}
  {@META}       SUP / FLT / CLS / OBJMIX / MIX
  {@ATTRIBUTES} effective user fields (nested objects and arrays preserved)
  {@FUNCTIONS}  effective methods:
                  own             class's own method
                  <class>         inherited from that class
                  M_*             provided by that Mixin
  {@MIXINS}     class-level Mixin list
{__MIXINS}
  {M_Foo}
    {@FUNCTIONS}
      foo => own
```

说明：

- `{@ATTRIBUTES}` 显示的是**有效**字段，包括继承来的字段。从父类继承的字段仍然列在子类下面；目前的树不记录字段的定义类。
- 嵌套的字典和数组会被保留；数组元素使用普通的 `x_dump` 数组表示（`o = value`）。
- `{@...}` 键是留给调试章节的，因此名为 `META` / `ATTRIBUTES` / `FUNCTIONS` / `MIXINS` 的类字段不会与它们冲突。
- 调试树是一次性的，按需构建。它不是热路径结构。整份游戏 dump 大约 1000 行、耗时约一秒，所以不要在游戏循环里调用。
- `xo_dump_inher_chain` 仍然是原始的标准继承 dump；`xo_class_methods_print <class>` 仍然是紧凑的单类方法列表。

回归用例是 `test/bashlib/test_xo_debug_classes.sh`。

### 对象生命周期：born 与 retire

```bash
xo_obj_born Enemy                # template fields copied in, then Enemy_born runs
xo_obj_born_named OBJ_boss Boss  # same, with a stable handle
xo_obj_bury "$obj"               # <CLS>_retire runs, then the pool entry is removed
```

- `xo_obj_born*` 复制类对象的字段，把对象登记进 `XO_OBJ_POOL`，然后调用 `<CLS>_born`（默认是空操作）。
- `xo_obj_bury` 在释放任何东西之前先调用 `<CLS>_retire`。Retire 意味着"对象离开这个世界"——指记忆与灵魂，而不是躯体：它拥有的一切都随它一起 retire（`Plane_retire` 负责它的武器对象）。每个类都继承 `Base_retire`；缺少 `<CLS>_retire` 是错误。
- Retire 还会丢弃对象的 `{OBJMIX}` 路由，因此被复用的具名句柄不会继承上一个对象的能力。

#### hire / fire（复用）

`xo_obj_hire` / `xo_obj_fire` 是存储层的复用，不是新的生命周期。`hire` 从资源市场弹出一个被 fire 掉的实体（市场为空时回退到 `born`），`fire` retire 一个实体并把它留着而不是销毁。市场为空时 `hire` 与 `born` 完全相同，所以从不 fire 的代码行为与以前完全一样。

**只用于简单对象。** 组合对象——即拥有其他对象的类，目前只有 `Plane`，它的武器句柄存在 `{w1}`..`{w5}` 里——必须始终使用 `bury`，并与子对象一起消亡。retire 钩子无法判断自己是在 bury 还是 fire 里运行：fire 一个组合对象会在保留父对象的同时销毁子对象，而被重新 hire 的父对象会持有指向已死对象的句柄。要回收组合对象，就得把退出方式传给 retire 钩子，并在 born 钩子里重建父子链接；在那之前这条约束没有例外。

游戏回收五个热点子弹类——`Bullet`、`EnemyBullet`、`BossBullet`、`EnemyMissile`、`Missile`——每个族只有一个生成点（敌方子弹用 `enemy_bullet_spawn`，我方用飞机/导弹的发射代码），以及对应的死亡出口。每个类都声明 `<cls>ResetFields`，写明它存活期间会变动的字段：五个类都有 `prev_x prev_y`，玩家子弹还多了 `color`（激光会把自身的威力颜色涂到实体上）。

在参考机器上测量：一个子弹的生命周期从 ~0.95 ms（born+bury）降到 ~0.75 ms（hire+fire），其余四个类落在 1.3x 到 1.5x 之间。剩下的开销是 retire 钩子、born 钩子和重置写入，这两条路径都要付；回收省掉的只是类模板的反序列化。

游戏的类树：

```text
Base
├── BulletType
│   ├── BulletTypeDefault
│   ├── BulletTypeLaser
│   ├── BulletTypeStar
│   ├── BulletTypeAt
│   └── BulletTypeDollar
└── Entity
    ├── Plane
    │   ├── PlaneBee
    │   ├── PlaneHornet
    │   ├── PlaneEagle
    │   └── PlaneIl2
    ├── Enemy
    │   ├── EnemyQ
    │   ├── EnemyV
    │   ├── EnemyB
    │   └── EnemyM
    ├── BossBase
    │   ├── Boss
    │   ├── BossSpinner
    │   └── SkullKing
    ├── Bullet
    ├── EnemyBullet
    │   └── BossBullet
    ├── Missile
    ├── Drop
    └── Word
```

飞机类使用的纯方法 mixin：

```text
M_Blink
M_LongBlink
M_Ram
```

正是这一点让游戏能够新增敌人或 Boss 而不必写一个巨大的 `case` 语句：类定义保存数据，方法保存行为。

### 对象级 mixin

类级的 `{MIX}` 在 `xo_init` 时就固定了。单个对象也可以在运行时通过 `{OBJMIX}` 获得和失去能力——Boss 正是这样拿到五个随机增益中的两个，并在阶段切换时换掉它们：

```bash
xo_obj_mixin_add    OBJ_boss M_BuffInvuln M_BuffMissile   # one or many, idempotent
xo_obj_mixin_delete OBJ_boss M_BuffInvuln                 # no args = drop them all
xo_obj_mixin_list   OBJ_boss                              # -> "M_BuffMissile ..."
xo_obj_call         OBJ_boss buff_tick                    # first holder wins
xo_obj_call_all     OBJ_boss buff_tick                    # every holder runs
```

一个能力可以提供两个可选钩子。它们使用私有的前导下划线，因此永远不会被注入成可调用方法，两个能力也可以同时实现它们：

```bash
M_BuffMissile__init    () { local -n s=$1 ; s["{ms_cd}$X"]=0 ; }   # after add
M_BuffMissile__cleanup () { local -n s=$1 ; s["{ms_cd}$X"]=0 ; }   # before delete
```

`_init` 在能力注册之后运行，`_cleanup` 在它被注销之前运行。bury 一个对象不会运行 `_cleanup`：整个对象变量被销毁，它的状态也随之而去，而复用的句柄会从模板重新 born。Cleanup 是为了在对象还活着的时候移除能力而存在的。能力被获得时做的一切——包括对世界的影响，比如触发 Boss 波或减速玩家——都属于 `_init`；不存在单独的"获得时"钩子。

两个钩子都不是必需的。约定是：拥有对象状态的能力把 `_init` 和 `_cleanup` 成对实现（进来时创建，出去时清除）；无状态的能力至少实现 `_init`，或者提供一个公开方法。框架只拒绝既没有公开方法也没有 `_init` 的 mixin。

`xo_obj_mixin_add` 按参数顺序应用，并且是幂等的：对象已拥有的能力会被跳过，它的 `_init` 不会再次运行，所以正在走的计时器不会被重置。同一次调用里的重名会被合并，因为同一次调用中把一次性能力加两次绝不能触发两次。一次性能力可以在 `_init` 内部把自己移除；循环会在每个参数之后重新读取 `{OBJMIX}`，因此被移除的能力不会在添加下一个时被追加回去，而剩下的参数仍然生效。要再次触发一次性能力，得在另一次调用里添加——那时它已不在列表中，所以不算已拥有。

一句话：对持久能力，添加一次或多次完全一样（幂等，`_init` 只运行一次）。对一次性能力，同一次调用里的重复也一样；只有另一次调用会再次触发它，这是有意设计的。

### 扁平类

`Base` 是**扁平**类：它的所有字段都是大写元键，由它构建出的对象使用不带 `{...}$X` 包装的用户字段。`BaseX`（`Base` 的子类）是**树**类的根，树类保留包装键以及 `x` 树的机械结构。类通过 `{FLT}` 字段选择自己的形态：

```text
    {FLT} => 1     flat class  (rules above);  user field {hp}$X is stored as hp
    {FLT} => 0     tree class  (BaseX root);   user field stays {hp}$X
```

`{FLT}` 会被继承，因此 `Base` 之下的每个类都是扁平的，除非它覆盖该字段。`xo_init` 会剥掉扁平类对象的包装并重建它们的 `ObjStr` 缓存，所以实例出生时就是扁平的；树类保持不动。

剥离后的键名：

```text
    metakeys, kept wrapped in both shapes:   {CLS}$X {SUP}$X {MIX}$X {OBJMIX}$X {FLT}$X
    flat class user fields:   {hp}$X  ->  hp        read with  self[hp] / obj[hp]
    tree class user fields:   {hp}$X  unchanged     read with  self["{hp}$X"]
```

扁平类对象不再有任何 `x` 树节点（`1.c.*`、`max_index` 等）：它是一个普通的关联数组，所以 `x_get` / `x_set` 那类访问不适用于它。`Base_print` 把它当普通数组 dump；`BaseX_print` 仍用 `x_dump`。

**不允许临时字段。** 扁平形态使往对象里写任意键成为*可能*，但这是禁止的：方法接触到的每个字段都必须在类模板中声明（并加注释，如宪法所要求），未声明的键就是 bug。字段名遵循 `xo.sh` 顶部的表格：公开字段用小写下划线风格（`hp`、`prev_x`），私有字段用 `_ClassName_field`（`_Boss_phase`），而 `_kind{...}` 这类临时容器是框架内部的，绝不用于游戏数据。

#### mixin 的 `{REQUIRES}` 规则

只适用于一种形态的 mixin 必须在 `{REQUIRES}` 中声明这一点，而且该声明**必须放在第一位**：

```text
    {REQUIRES} => FLT=1 bi_cd inv_cd     # flat only, then its field dependencies
    {REQUIRES} => FLT=0                  # tree only
    {REQUIRES} => hp maxhp               # no FLT: both shapes
```

- `FLT=1` 表示"只支持扁平类"，`FLT=0` 表示"只支持树类"；框架会拒绝形态不匹配的类/mixin 组合。
- **没有 `FLT` 记号意味着该 mixin 同时支持两种形态**，那么它的实现必须自己处理两种键布局（`self[x]` 与 `self["{x}$X"]`，或者通过框架访问器）。只为一种形态编写，会在另一种形态上静默读到空字段。
- 按约定 `FLT` 必须是第一个记号（这让声明既好读又好 grep）。框架用带词边界的正则来识别它，因此无论后面是字段、换行还是行尾都能找到；`FLT=10` 不会被误认为 `FLT=1`。

#### 迁移到扁平字段访问

一旦类变成扁平，它自己的方法以及 `_born` / `_retire` 钩子都必须使用剥离后的键：

```bash
    # tree style (old)                 # flat style (new)
    ${self["{x}$X"]}                    ${self[x]}
    self["{x}$X"]=$x                    self[x]=$x
    ${self["{hp}$X"]:-0}                ${self[hp]:-0}
```

元键是唯一的例外：它们保持包装，例如 `${self["{CLS}$X"]}` 和 `${self["{OBJMIX}$X"]}`。Mixin 的实现体遵循同样规则（或者 `{REQUIRES}` 声明必须写明它们只支持一种形态）。

### Il-2 的 mixin 栈

Il-2 使用一个三元素的 Mixin 列表：

```text
{MIX} => M_LongBlink M_Blink M_Ram
```

- `M_LongBlink` 把 `blink_start` 覆盖为 4 秒。
- `M_Blink` 提供常规的闪烁帧/可见性方法；其他飞机用它的 3 秒默认值。
- `M_Ram` 提供撞击能力：Il-2 被击中后处于闪烁状态时，撞到敌人造成 5 点伤害。撞击有 10 帧冷却，可以通过正常的计分/死亡路径杀死敌人或 Boss。

面向玩家的同一套构型总结：挨一下进入 4 秒的暴怒状态，然后撞向敌人。无敌窗口与闪烁时长一致。

## 单格子弹：结构体数组（SoA）

敌方子弹、Boss 子弹和追踪导弹刻意**不**使用 `xo` 对象系统。它们没有 mixin、没有继承、没有生命周期钩子：它们只是几个数字加一个字形。走 `xo` 时，每一个都要付出一次方法调用、一次 nameref 绑定和每帧若干次哈希读取（约 155µs）；而作为按槽位索引的并行数组，只要约 30µs。

`classes/projectiles/soa_bullets.sh` 拥有整个模型：

| 数组 | 含义 |
|-------------|----------------------------------------------------------------|
| `EB_ALIVE`  | 1 = 该槽在使用 |
| `EB_TYPE`   | 0 = 垂直向下（4 帧一行），1 = 向量 + 步进，2 = 追踪 |
| `EB_X/EB_Y` | 位置（1 起算，与屏幕一致） |
| `EB_VX/VY`  | 每次移动的增量（类型 1 和 2） |
| `EB_STEP`   | 每 N 帧移动一次 |
| `EB_CD`     | 在该周期内的当前帧 |
| `EB_DMG`    | 到达玩家时的伤害 |
| `EB_FUEL`   | 仅追踪导弹：自毁前还能移动的次数 |
| `EB_GLYPH`  | 可直接输出的字节（颜色 + 符号 + 复位） |
| `EB_FREE`   | 死亡槽位栈 |
| `EB_N`      | 用过的最高槽位（循环上界） |
| `EB_LIVE`   | 存活数量（生成上限用） |

槽位从不压缩，因此一个槽号在该子弹的整个生命周期内保持稳定，可以作为它在帧缓冲里的归属（存为 `slot + 1`，所以 0 表示"空"）：

```text
   eb_add                      eb_kill
     |                            |
     v                            v
  +-----------------+       +-----------+
  | EB_FREE (stack) | <-----+ slot i    |
  +-----------------+       +-----------+
     |  pop one, or EB_N++ when empty
     v
  slot i: ALIVE=1, X/Y/VX/VY/STEP/CD/DMG/FUEL/GLYPH filled, one cell written
```

一次帧循环就完成一颗子弹的所有事——移动、命中判定、帧缓冲：

```text
  for i in 0 .. EB_N-1:
      if not EB_ALIVE[i]: continue
      hit player?  (_HL_* already computed for this tick)
          yes -> spark, damage (unless shielded), eb_kill(i), next
      move by type:
          type 0  cd++;  only when cd == 4: y += 1
          type 1  cd++;  only when cd == step: x += vx, y += vy
          type 2  cd++;  only when cd == step: fuel--, step toward the player
                                  fuel == 0 -> eb_kill(i), next
      out of the play area? -> eb_kill(i), next
      clear the old cell, write the glyph into the new one (one dirty append)
      type 2: a player bullet on the same cell -> spark, eb_kill(i), mark that
              bullet as killed (it is buried by the normal cleanup pass)
```

生成入口没有变化，所以每个 Boss 弹幕形态和测试都照常工作：

```bash
enemy_bullet_spawn EnemyBullet  x y sym damage
enemy_bullet_spawn BossBullet   x y vx vy sym damage step [colour]
enemy_bullet_spawn EnemyMissile x y [fuel] [step]
```

仍然属于对象系统的是：任何有美术表现、HP、mixin 或状态机的东西——敌人、Boss、掉落物、浮字，以及未来巨大的多格子弹（它们是实体而不是数据；可以自带美术和碰撞盒尺寸）。经验法则是：*单格且无行为 -> SoA；有美术表现或行为 -> 对象。*

在 110 颗子弹时测量：单帧 26.9ms -> 17.2ms。原先的三个类（`enemy_bullet.sh`、`boss_bullet.sh`、`enemy_missile.sh`）已不存在；Boss 测试通过 `eb_field` 读取槽位。

## `x` 树

`x` 是一棵具备 JSON 语义的内存树，用纯 Bash 实现。它支持对象、数组、null、布尔、有序子节点和路径访问。

- **核心（`x.sh`）** —— `x_init`、`x_insert`、`x_delete`、`x_walk`、`x_iter`、`x_walk_dict_tree`、`x_dump`、`x_rebuild_from_dump`、节点/类型查询
- **扩展（`xe.sh`）** —— `x_get_leaf` / `x_get_tree`、叶子/子树的 push/pop/shift、扁平/分层转换、`x_equals`、`x_graft`、`x_id_rebuild`
- `x_walk_dict_tree` —— 面向**纯 `{}` 树**的快速遍历器；它拒绝数组和物理 id 节点。混合树请用 `x_walk`。
- **JSON（`xj.sh`）** —— `x_to_json` / `x_from_json`；需先 source `xj.sh`
- **gobolt 依赖** —— `xj.sh` 会调用外部程序 `gobolt`，来自 [qindapao/common_tool](https://github.com/qindapao/common_tool)。从 [common_tool Releases](https://github.com/qindapao/common_tool/releases/latest) 下载对应平台的最新构建，并放进 `PATH`。游戏核心不需要 gobolt；只有 JSON 互操作和 JSON 测试需要。
- 依赖方向：`xe.sh` 和 `xj.sh` 都只 source `x.sh`，彼此独立；`x.sh` 不得 source 或调用 `xe.sh` / `xj.sh`。测试只 source 自己用到的层。
- MSYS2 CR 约定：**值**在 insert/get/walk/dump/rebuild/iter/flat/JSON 之间保持不变；**键**不做保证。该平台限制与确切保证记录在 `x.sh` 顶部，并由 `test/bashlib/test_msys2_cr.sh` 覆盖。

完整参数与返回码见 `src/bashlib/x.sh`、`src/bashlib/xe.sh` 和 `src/bashlib/xj.sh` 的函数头注释。

### 节点状态转换

null 叶子可以升级为空容器，空容器随后可以接收子节点：

```text
LEAF --X_VALUE_NULL--> LEAF_NULL
LEAF_NULL --X_VALUE_NULL_OBJ / X_VALUE_NULL_ARR--> OBJ_EMPTY / ARR_EMPTY
OBJ_EMPTY / ARR_EMPTY --child insert--> OBJ / ARR
```

在普通标量叶子下写入子节点会被拒绝；调用方必须先写入 `X_VALUE_NULL`。

Null 是唯一透明的叶子：当 `x_insert` 在任意深度下穿过一个 `LEAF_NULL` 时，它会按下一个路径记号所需的容器类型升级该节点。普通标量叶子是终止节点；它们可以在同一路径上被覆盖为空容器，但无法被穿透。

`x_insert` 是叶子写入器。`null`、空对象和空数组都是叶子值，因此用 `X_VALUE_NULL_OBJ` / `X_VALUE_NULL_ARR` 替换普通标量叶子属于正常的叶子覆盖。非空容器不是叶子：在标量下写子节点会被拒绝，所以从标量转到非空容器仍然需要显式的 `X_VALUE_NULL` 转换。

严格的两步转换是一条 schema 层策略。需要它的代码——例如树类模板合并——必须先检查目标类型，并拒绝标量直接转空容器。不要依赖 `x_insert` 去执行这条策略。

轻量插入路径不实现这个状态机：

- `x_insert_token_dict` 要求已存在的容器父节点，并且不做 NULL 升级。它的 `{key}` 更新路径不得指向已存在的空容器节点；在那里写标量会留下 `.t` 并损坏节点。
- `x_insert_dict` 用于可信的 OBJ 路径，不升级 NULL 叶子，也不校验完整路径上已存在的空容器。
- 单值模式下的 `x_qinserts` 继承 `x_insert` 的叶子覆盖语义；空容器哨兵可以替换该路径上的标量。

### 如何选择插入 API

| API | 路径 | 校验 | 使用场景 |
|---|---|---|---|
| `x_insert` | 完整物理路径 | 完整 | NULL 叶子升级、`[]`/`()`、已存在的容器 |
| `x_insert_dict` | 完整物理路径 | 轻量 | 父节点已是 OBJ；只用于 `{}` / `<id>`；不做升级 |
| `x_insert_token_dict` | 已知父节点下的一层 | 无 | 批量插入直接子节点 |

`x_insert_dict` 刻意**不**做以下事情：

- 从 `[i]` / `()` 创建数组
- 把 NULL 叶子升级为对象
- 校验中间父节点是对象
- 拒绝完整路径上已存在的容器

它可能在 NULL 叶子上留下 `.k` 以及 `.t`/子节点；`x_get_node_type` 仍会报告为叶子，于是那些子节点变得不可见。升级/数组场景请用 `x_insert`，`x_insert_dict` 只保留在可信的 OBJ 路径上。

### 数据类句柄（`data.sh`）

`data.sh` 提供轻量的外部容器，它们**不是** `xo` 类：

```text
ARR    indexed Bash array
ASSOC  associative Bash array
DTREE  x tree with OBJ root
ATREE  x tree with ARR root
```

句柄形如 `ARR_1`、`ASSOC_1`、`DTREE_1`、`ATREE_1`……来自全局的 `XO_DATA_CLASS_IDX`。一个池记录存活状态和类型：

```text
XO_DATA_CLASS_POOL[handle] = ARR|ASSOC|DTREE|ATREE
```

API：

```bash
. "$STRAFE_LIB_HOME/data.sh"   # data.sh is independent of xo
xo_data_born_arr       # REPLY=ARR_N
xo_data_born_assoc     # REPLY=ASSOC_N
xo_data_born_dtree     # REPLY=DTREE_N
xo_data_born_atree     # REPLY=ATREE_N

xo_data_bury "$handle"
xo_data_is_live "$handle"
xo_data_type "$handle" # REPLY=kind
```

典型的拥有者：

```bash
Bag_born () {
    local -n self=$1
    xo_data_born_assoc || return 1
    self[bag]=$REPLY
}

Bag_retire () {
    local -n self=$1
    xo_data_bury "${self[bag]}" || return 1
    self[bag]=''
}
```

约定：

- 一个句柄只有**一个拥有者**；不要在对象之间共享它。
- 不要在数据类容器里存另一个数据类句柄。
- 拥有者必须调用 `xo_data_bury`；不要直接 `unset` 一个句柄。
- `fire` 会运行 `retire`，`hire` 会运行 `born`，所以如果数据在重新 hire 之后还应存在，拥有者必须在 `retire` 里释放、在 `born` 里重建。
- `xo_data_clear` 移除所有存活的数据类；只在测试/关停时使用它。

数据类是给扁平/树对象挂载的外部袋子，不是给局部临时变量用的，也不用于继承/方法派发。

### 输入/输出约定

树格式是我们自己的，因此这份约定靠惯例而非防御性代码来保证：

- **编码**：键、值和 dump/模板文本都是合法 UTF-8。非法字节和孤立的 C1 字节（`0x80`–`0x9F`，不在 UTF-8 序列内）不在承诺范围之内；转义/反转义只在合法 UTF-8 上互逆。
- **非 BMP 字符**（`U+10000` 及以上，例如 emoji）必须写成字面 UTF-8。`\uXXXX` 只覆盖 BMP；`\uD83D` 这类代理对转义不受支持，也不会被转换回字符。
- **控制字符**：dump/模板行里不得包含裸 C0、DEL 或 C1 字符（换行是行分隔符，不是数据）。把它们写成 `\uXXXX`，或使用 `\b` `\f` `\r` `\t` 简写。多行的值和键使用 `|` 续行形式；写入方输出它，`x_rebuild_from_dump` 再把它合并回去。
- **键**：用 `{...}` 作定界符，键内的字面 `}` 必须写成 `\}`，并且键内不得包含裸的 `$X` 分隔符。
- **数组是稠密的**：dump 按索引顺序写出元素，rebuild 从 0 开始重新编号。不支持稀疏或乱序的数组 dump。
- **结构错误会大声失败**：例如 `=>` 缺少尾随空格会让 `x_rebuild_from_dump` 返回非零；它绝不会产出一棵静默丢掉分支的半成品树。
- **容器不会被 `x_insert` 降级**：非空容器不能被叶子覆盖，也不能被任一类型的空容器覆盖（即使是同类型），空容器也不能改变类型。要清空子树，先用 `x_delete`；哨兵只用于初始化或匹配空容器。

在以上规则下，`str_escape_keep_nl`（值）、`str_escape_key`（键，额外转义 `}`）和 `str_unescape` 构成一对互逆函数。

## 构建与测试

```bash
./build.sh        # no-op compatibility shim; all sources are tracked .sh files
./test.sh         # run the test suite
```

所有库和测试模块现在都是已跟踪的 `.sh` 源文件；不再有 `.in` 文件。保留 `build.sh` 只是为了让 `clear.sh` 等既有脚本继续工作。

## 终端与输入说明

### 鼠标上报

游戏使用 xterm SGR 鼠标上报（`1006`），外加 `1000` / `1002` / `1003` 追踪回退模式，因此只实现点击或拖拽追踪的终端也能移动飞机。坐标基于字符格，而不是像素。

- 游戏过程中捕获始终开启；没有开关，所以终端文本选择在游戏退出前不可用。
- `_mouse_assert` 每 30 帧重发一次启用序列，因为某些终端在焦点变化后会静默丢弃鼠标上报。
- 输入循环会限制每次迭代的鼠标事件数，这样移动很快的鼠标不会饿死游戏循环。
- `ESC[?25l` 隐藏文本光标。ANSI 无法隐藏操作系统指针；那是终端偏好（Windows Terminal / mintty 的鼠标设置）。
- 指针的目标是飞机中心下方两行，这样指针不会压在精灵上。鼠标移动和左键点击都能移动飞机。
- 普通 Windows 控制台窗口（conhost）不会把鼠标输入转换成 VT 序列，所以那里的鼠标是无效的；mintty 自带 pty，确实会上报。
- WindTerm 可能只实现点击/拖拽追踪，而没有 any-event 移动。
- 退出时和 GAME OVER 时会关闭鼠标捕获。

### 同步输出

每一帧都包在 `DECSET 2026` 中：缓冲内容在 `ESC[?2026h` 与 `ESC[?2026l` 之间发出，于是终端一次性合成整帧，而不是把擦除/重绘的中间状态画出来。不支持 `2026` 的终端会忽略这些序列。

### 备用屏幕

游戏在启动时进入备用屏幕（`ESC[?1049h`），并在 `term_restore` 中离开（`ESC[?1049l`），而不是在退出时清屏。

- 备用屏幕没有回滚缓冲，这避开了某些终端会按回滚缓冲行数偏移鼠标行号的问题：mintty 会把回滚行数计入鼠标行号，曾把飞机顶到屏幕边缘。
- 离开备用屏幕会恢复玩家之前的内容，所以 `term_restore` 之后不得再清屏。
- `HUP` trap 覆盖窗口关闭的情况，因此终端不会滞留在备用屏幕上。

## 渲染说明

游戏绘制的一切都追加到一个缓冲（`FRAME_BUF`）里，每帧 flush 一次；渲染路径上没有任何东西直接写终端。这保住了两条后续修复所依赖的性质：

- **帧是原子的。** `frame_flush` 把整个缓冲包在一个同步输出括号里（见上文），于是终端合成一帧，而不是显示"先擦掉旧位置、再画新位置"的中间状态。
- **每帧一次写入。** flush 是一次 `printf`；在这里增加每帧的工作会直接花掉帧数，所以保持为一次调用。

渲染阶段的绘制顺序是：擦除上一帧位置，绘制子弹、导弹、敌方子弹、敌人、掉落物和浮字，最后绘制玩家，这样任何东西都盖不住飞机。玩家静止且美术形状未变时会跳过它自己的擦除，因为那一帧反正会重绘同样的格子。

## 扫描波（电网）

一波是一整行 `~` 横扫战场，伤害它经过的一切，并清除它扫过行上的子弹。同一套系统驱动双方；区别只在归属。

- Boss 波（`M_BuffWave`）：红色，自上而下，3 点伤害，即使伤害本身仍受无敌帧保护，也会剥掉玩家的护盾。它还会清除*我方*子弹。一次授予会连发 2-4 波，间隔 1-3 秒，最后一批发出后能力立即自行卸载——所以它由 `buff_tick` 驱动，而不是在 `_init` 里发一次。
- 玩家波（掉落物 `W`，拾取时触发）：绿色，自下而上，每个敌人每波 30 点伤害，并清除敌方子弹和追踪导弹。没有缺口：防御性工具不该有漏洞。

波次存在一个小型固定槽位表（`WAVE_SLOTS` = 5）里，因此可以同时存在多个——这种重叠正是 Boss 爆发的意义：每一波都会重新随机自己的缺口，安全走廊不断移动，玩家必须持续调整位置。状态按属性各是一个并行数组（`WV_ON`、`WV_Y`、`WV_DIR`、`WV_OWNER`、`WV_DMG`、`WV_CD`、`WV_LAST_Y`、`WV_HIT`、`WV_GAP1/2`、`WV_LINE`、`WV_CLR`）；`WAVE_ON` 只是给热路径用的派生"有波存活"标志。`_wave_start` 取第一个空闲槽位并在 `REPLY` 中返回其索引，表满时失败（此时能力会在下一帧重试，而不是丢掉一次发射）。

重叠波次对玩家造成的伤害按帧累加，然后仍然走通常的无敌窗口，因此三波快速扫过玩家只算一次命中，而不是三次。压力在于躲避，而不是把血条瞬间烧空。

### 清弹为什么用扫过的行带，而不是比较行号

天真地清除"行号等于波次行号"的子弹会漏掉大部分，而且有两个独立原因：

1. 波次每行停留 `WAVE_STEP_TICKS`（3）帧，而 `EnemyBullet` 每 4 帧移动一次。波次到达的那一帧，大多数子弹还不在那一行；等它们到达时，波次已经走了。
2. 子弹和波次甚至可以在同一帧内交换行：波次从 9 -> 8，而子弹从 8 -> 9，于是它们根本不曾共享同一格。

所以波次记录它在本帧扫过的行带（停留时一行，前进那一帧两行），并在它停留的每一帧清除该行带内的子弹。检查从一次比较变成两次，同时消除了两类漏检。

### 逃生缺口

Boss 波随机打出 `WAVE_GAP_COUNT`（2）个宽 `WAVE_GAP_W`（3）格的缺口，其位置在该波次期间固定。如果每行都重新随机，玩家就得在波次下降时追着缺口往下跑，那比站着不动还难。玩家的碰撞盒只有一格，所以三格宽的缺口站进去很舒服，但仍然必须去打。

缺口也会放子弹通过：清弹检查会跳过缺口内的子弹，因此"网只抓住它碰到的东西"对伤害和子弹都成立。

### 渲染与开销

波次在擦除阶段之后、对象之前绘制，因此它永远不会盖住子弹或敌人，而对象会重绘在它之上。波次前进时擦掉上一行；结束时，最后一行只擦一次。一行每帧大约 260 字节（约占一帧的 4%），而清弹阶段只在有波存活时运行（约 90 帧），所以帧预算不受影响。`WAVE_LINE` 每个波次只构建一次，之后每帧复用。
