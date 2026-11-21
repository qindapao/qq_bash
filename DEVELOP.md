# DEVELOP — qq_bash internals

Development notes for `qq_bash`: what the project is for, how `xo` and `x` work,
the game's class tree, build/test flow, and the rules that keep the Bash version
frozen. Player-facing documentation lives in [README.md](README.md); project
conventions live in [CONSTITUTION.md](CONSTITUTION.md).

---

## Architecture at a glance

Read this before touching code: it is the map of the whole system. The
sections below expand each topic in detail. Diagrams are plain ASCII so they
stay aligned in any editor, terminal or diff viewer.

### 1.1 Layers

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
| OBJECT SYSTEM  src/bashlib/xo.in                                           |
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
| DATA STRUCTURE  src/bashlib/x.in                                           |
|   x tree: node ids, .c child table, .s order, <id>.k key, <id> value       |
|   x_walk / x_dump / XO_CLASS_INHER_TREE (class inheritance)                |
+----------------------------------------------------------------------------+
```

### 1.2 Object lifecycle

Four verbs, two hooks. Life is only born/bury; hire/fire is storage-level reuse.

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

Hard constraints:

- **Composite objects can only be buried.** A class that owns other objects
  (today only `Plane`, whose `{w1}..{w5}` fields hold weapon handles) must die
  together with its children. A retire hook cannot tell whether it runs inside
  a bury or a fire, so firing a composite leaves the parent alive and its child
  handles dangling.
- **Callers must remove the handle from their own arrays before fire** and must
  check `XO_OBJ_POOL` before using a handle.
- **With an empty market, hire is identical to born**, so code that never fires
  behaves exactly as before.

### 1.3 Tick pipeline (`_play_game_tick`)

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

### 1.4 Render pipeline (`render`)

```text
 phase 1  erase the prev cell of every live object
          waves: erase every slot old row first, then draw every current
          row (two passes, so overlapping waves cannot erase each other)
 phase 2  draw the cur cell of every live object (plus HUD, fx, banners)
 phase 3  draw the player last (topmost layer)
 ----
 one single flush of FRAME_BUF to the terminal per frame
```

### 1.5 Global variables

Framework globals are grouped by owner; the prefix says where they come from:
`XO_`/`xo_` object system, `X_` tree system, `RES_` resource market, `_ret_*`
library return snippets, `_*_IMPORTED` import guards. These names are
framework-owned: user code must not define variables in these namespaces, and
the `*Obj` / `*StaticTemplate` suffixes are reserved (see
CONSTITUTION.md §3).

**Object system (`xo.in`) — class definitions and inheritance**

| Variable | Purpose |
|---|---|
| `BaseObj` | the `Base` class object (framework root; `{CLS}$X=Base`, `{FLT}$X=1`) |
| `BaseXStaticTemplate` | template of `BaseX`, the only framework tree class (`FLT=0`) |
| `${cls}Obj` | per-class class object. Flat classes are **defined** by this array (single source); tree classes are built from a template |
| `${cls}ObjStr` | KV snapshot of the class object; born does one `declare -gA` with it (the expensive part) |
| `${cls}StaticTemplate` | template of a tree class (FLT=0) only. A flat class that uses a template makes `xo_init` fail |
| `${cls}ResetFields` | volatile fields of a recyclable class; fire resets only those (e.g. `prev_x prev_y color`) |
| `XO_CLASS_INHER_TREE` | class inheritance chain (x tree); used by `xo_init` to build dispatch |
| `XO_METHOD_INHERITED` | forwarding table for inherited methods |
| `XO_INHER_CHAIN_DUMP_CACHE` | cached inheritance dump, avoids recomputation |
| `XO_CLASS_TREE_TMPL_VARS` | manually registered tree-class template names |
| `XO_CLASS_FLAT_OBJ_VARS` | manually registered flat-class object names |
| `XO_CLASS_METHODS[class]` | manually registered public methods owned by each class |
| `XO_CLASS_VARS_READY` | legacy one-shot scan guard; init no longer depends on it |
| `XO_FLAT_META` | metakeys kept when a flat class is built (everything else is a user field) |
| `_XO_INIT_CALLED` | `xo_init` may run only once |
| `_XO_IMPORTED` | import guard of `xo.sh` |

**Object system (`xo.in`) — instances, mixins, resource market**

| Variable | Purpose |
|---|---|
| `XO_OBJ_POOL[handle]` | handle -> class. The only registry of live objects; every "is it alive" check uses it |
| `XO_OBJ_SEQ` | anonymous handle counter, produces `OBJ_11`, `OBJ_12`, ... |
| `XO_MIXIN_METHODS[mixin]` | manually registered public methods each mixin provides |
| `XO_OBJ_METHOD[handle\|method]` | per-object method routing (mixin implementation names) |
| `XO_OBJ_MIXED[handle]` | set of objects carrying mixins (cheap gate: empty set means bury does one length check) |
| `XO_RES_COUNT[class]` | resource market: number of idle bodies of that class |
| `XO_RES_MARKET["class\|index"]` | resource market: idle handles, O(1) LIFO |
| `XO_RES_LIMIT[class]` `XO_RES_LIMIT_DEFAULT` | per-class recycle cap / default 512 |
| `XO_RESET_FIELDS[class]` | cache: the class reset list, copied from `<cls>ResetFields` |
| `XO_RESET_DEF["class\|field"]` | cache: template default of a volatile field, read from the class object |
| `XO_RESET_READY[class]` | cache: flag, the reset list was preprocessed (lazy, on first fire) |

**Init progress (diagnostics, off by default)**

| Variable | Purpose |
|---|---|
| `XO_INIT_PROGRESS` | 1 = draw the "loading classes" bar during `xo_init` |
| `XO_INIT_PROGRESS_FD` | fd the bar is written to (default 2) |
| `XO_INIT_TOTAL` / `XO_INIT_DONE` | class definitions to build / classes built so far |
| `XO_PROGRESS_BAR_MAX` | max bar width in cells |

**Tree system (`x.in`)**

| Variable | Purpose |
|---|---|
| `X` | key separator `$'\034'` between tree path components |
| `X_ROOT_ID` | root node id (1) |
| `X_TYPE_OBJ` `X_TYPE_ARR` | tree container type |
| `X_NODE_KIND_OBJ` `X_NODE_KIND_ARR` `X_NODE_KIND_OBJ_EMPTY` `X_NODE_KIND_ARR_EMPTY` `X_NODE_KIND_LEAF` `X_NODE_KIND_LEAF_NULL` `X_NODE_KIND_UNKNOWN` | node kinds returned by `x_get_node_type` |
| `X_VALUE_NULL` `X_VALUE_TRUE` `X_VALUE_FALSE` `X_VALUE_NULL_OBJ` `X_VALUE_NULL_ARR` | sentinels `null\034`, `true\034`, `false\034`, `{}\034`, `[]\034` |
| `X_FLAT_IS_MATCH` `X_FLAT_IS_NOT_MATCH` `X_FLAT_ARRAY_NULL` `X_FLAT_ASSOC_NULL` | flat-vs-tree compare results |
| `X_GOBOLT_JSONTYPENULL` `X_GOBOLT_JSONTYPETRUE` `X_GOBOLT_JSONTYPEFALSE` `X_GOBOLT_JSONTYPENUMBER` `X_GOBOLT_JSONTYPESTRING` `X_GOBOLT_JSONTYPEARRAY` `X_GOBOLT_JSONTYPEOBJECT` `X_GOBOLT_JSONTYPEUNKNOWN` | JSON type ids 1..8 used by the gobolt conversion |
| `X_RET_ENUM_OK` | success (0) |
| `X_RET_ENUM_KEY_IS_TREE` `X_RET_ENUM_KEY_IS_LEAF` `X_RET_ENUM_KEY_IS_NOTFOUND` `X_RET_ENUM_KEY_IS_INVALID` `X_RET_ENUM_KEY_OUT_OF_INDEX` `X_RET_ENUM_KEY_IS_NOT_LEAF` `X_RET_ENUM_KEY_IS_NULL` `X_RET_ENUM_KEY_UP_LEV_TYPE_MISMATCH` `X_RET_ENUM_KEY_CHILD_CNT_IS_ZERO` `X_RET_ENUM_KEY_OTHER_TOOL_NOT_INSTALLED` `X_RET_ENUM_KEY_BJSON_TYPE_INVALID` `X_RET_ENUM_KEY_BJSON_TYPE_OBJ` `X_RET_ENUM_KEY_BJSON_TYPE_ARR` `X_RET_ENUM_KEY_PARAMETER_LENGTH_EXCEEDS_LIMIT` | per-key status codes 1..14 |
| `X_RET_ENUM_TREE_IS_INVALID` `X_RET_ENUM_TREE_IS_EMPTY` `X_RET_ENUM_TREE_NOT_HAVE_ROOT` `X_RET_ENUM_TREE_IS_NOT_SAME` | whole-tree failures 50..53 |

**Library return snippets (`grammar.sh`)**

`_ret_*` are `eval` snippets that move `REPLY` into a caller-named variable
(`eval "${_ret_A/o/name}"`): `_ret_s` (declare local scalar), `_ret_s_` (assign
existing `o`), `_ret_i` (local int), `_ret_a` (local array), `_ret_A` (local
assoc), `_ret_e` (return with the current `$?`), plus global variants
`_ret_g_s`, `_ret_g_i`, `_ret_g_a`, `_ret_g_A`.

**Import guards and build metadata**

| Variable | Purpose |
|---|---|
| `_VAR_IMPORTED` `_STR_IMPORTED` `_ARRAY_IMPORTED` `_GRAMMAR_IMPORTED` `_X_IMPORTED` `_XO_IMPORTED` | one-shot source guards (each `.in` returns early on second import) |
| `BASH_GRAMMAR[...]` | bash capability switches probed at build time, used by `#@if` |
| `_STR_BUILT_IN_THRESHOLDS` | `str.in` thresholds for choosing builtin vs external tools |

The three `XO_RESET_*` tables are one lazy cache per class, filled on the first
`fire` of that class and never rebuilt:

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

**Game runtime (`config/globals.sh`, `config/const.sh`)**

Live-object handle lists, rebuilt every tick (collect first, then clean up once):
`BULLETS`, `ENEMY_BULLETS`, `MISSILES`, `ENEMIES`, `DROPS`, `WORDS`.

| Variable | Purpose |
|---|---|
| `MISSILE_TRAIL_CLEAR` | cells a missile trail still has to erase |
| `HIT_FX`, `BOMB_FX_POS`, `BOSS_DEATH_POS` | hit sparks, bomb and boss-death effect queues |
| `BOSS_DEATH_*` | boss death animation state (tick, style, centre, wave) |
| `CLEAR_BANNER_*` | the "ACE" banner remaining ticks and text |
| `FRAME_BUF` | the whole frame output buffer; render only appends, one flush per frame |
| `RENDER_FPS`, `RENDER_US` | render cadence: frames per second and its period in microseconds |
| `G_FIRE_CD`, `G_MISSILE_CD`, `G_MISSILE_SIDE` | player fire/missile cadence and left-right alternation |
| `G_INV` | player invulnerability frames (blink and damage immunity) |
| `G_DX`, `G_DY`, `G_MOUSE_ON` | input direction and mouse mode |
| `G_WANT_BOMB`, `G_FREE_BOMB` | bomb requests (paid / free) |
| `G_ENEMY_TICK`, `G_DROP_TICK`, `G_WORD_TICK` | spawn cadence for each kind (every N ticks) |
| `G_B_DRY`, `G_BOSS_DRY` | small-enemy / boss dry periods, control rarity |
| `G_RUN_TICKS` | ticks in this run (effects, i-frames, saves, diagnostics) |
| `G_KILLS`, `G_BOSS_KILLS` | kill counters (scoring) |
| `G_LAST_ESCAPE_TICK`, `G_LAST_ACE_TICK` | cooldowns for the two reward banners |
| `G_GAME_OVER` | death flag; the main loop ends the run on it |
| `G_WAVE_DMG_PENDING` | damage from all waves hitting the player this tick, settled once in the damage phase |
| `WAVE_SLOTS` | wave slot count (5 = boss burst 4 + player 1) |
| `WAVE_ON` | derived flag: any wave alive (hot-path early exit, never maintained by hand) |

**Wave slot table (one entry per wave)**

| Variable | Purpose |
|---|---|
| `WV_ON[slot]` | slot in use |
| `WV_Y[slot]`, `WV_DIR[slot]` | current row / direction (boss +1 down, player -1 up) |
| `WV_OWNER[slot]` | 0 = boss (hits player, clears our bullets), 1 = player (hits enemies, clears enemy bullets) |
| `WV_DMG[slot]` | damage of this wave |
| `WV_CD[slot]` | counter, advances one row every `WAVE_STEP_TICKS` |
| `WV_LAST_Y[slot]` | render bookkeeping: row drawn last frame (-1 = never) |
| `WV_HIT[slot]` | this wave already hit the player (once per wave) |
| `WV_GAP1[slot]`, `WV_GAP2[slot]` | escape gaps (string index, 0 = screen column 2; negative on player waves) |
| `WV_CLEAR_LO[slot]`, `WV_CLEAR_HI[slot]` | row band swept this tick (bullet clearing covers swaps) |
| `WV_CLR[slot]`, `WV_LINE[slot]` | colour escape / full row characters |
| `WAVE_HIT_ENEMY["slot\|enemy"]` | hit table: once per wave per enemy |

**Constants (`config/const.sh`, `config/version.sh`)**

- **screen / cadence**: `SCREEN_W`, `SCREEN_H`, `FPS`, `TICK_US`, `GAME_TOP`
- **limits**: `ENEMY_LIMIT`, `PLAYER_BULLET_LIMIT`, `ENEMY_BULLET_LIMIT`,
  `BOSS_BULLET_LIMIT`, `DROP_LIMIT`, `WORD_LIMIT`, `HIT_FX_LIMIT`, `BOSS_LIMIT`
- **waves**: `WAVE_STEP_TICKS`, `WAVE_SYMBOL`, `WAVE_GAP_COUNT`, `WAVE_GAP_W`,
  `BOSS_WAVE_DAMAGE`, `BOSS_WAVE_STRIP_SHIELD`, `PLAYER_WAVE_DAMAGE`,
  `BOSS_WAVE_BURST_MIN/MAX`, `BOSS_WAVE_GAP_MIN/MAX`
- **boss abilities**: `BOSS_INV_TICKS`, `BOSS_BUFF_MAX`, `BOSS_BUFF_INV_ON/OFF`,
  `BOSS_BUFF_HEAL_WAIT`, `BOSS_BUFF_MISSILE_*`, `BOSS_BUFF_SLOW_*`
- **SkullKing**: `SKULL_KING_ROW_BULLETS`, `SKULL_KING_RADIAL_BULLETS`,
  `SKULL_KING_WAVE_BULLETS`, `SKULL_KING_BURST_RINGS`, `SKULL_KING_RING_GAP`,
  `SKULL_KING_REST`, `SKULL_KING_FIRST_SHOT`
- **rewards**: `BONUS_T2/T3/T4/T5`, `BONUS_MT`, `BONUS_LT`, `BONUS_ST`,
  `BONUS_SLOW`, `CLEAR_SCORE_BONUS`, `BOSS_SCORE_BONUS`
- **look**: `FRAME_H`, `FRAME_V`, `FRAME_TL/TR/BL/BR`, `LOCALE_UTF8`
- **version / save**: `STRAFE_VERSION` (`version.sh`), `STRAFE_SAVE_FILE`

### 1.6 Invariants (read before changing code)

1. **A live object is always in `XO_OBJ_POOL`.** Check the pool before using a handle,
   or you may operate on an idle or dead object.
2. **Before `bury`/`fire`**, the caller must have removed the handle from its arrays
   (`BULLETS` and friends are rebuilt every tick, so this holds naturally).
3. **Composites are buried, never fired**: parent and children die together.
   `hire`/`fire` are for simple objects only.
4. **One flush per frame.** Render only appends to `FRAME_BUF`; never `printf`
   straight to the terminal from a render function.
5. **No forks on hot paths**: no `$(...)`, no external commands (`sort`, `grep`,
   `awk`); bash builtins only.
6. **Per-object loops dispatch inline.** In a loop over live objects, write
   `"${XO_OBJ_POOL[$obj]}_move" "$obj"` instead of `xo_call "$obj" move`: the
   expression is identical, so polymorphism still comes from the pool lookup,
   but the wrapper frame is gone (~20 us per object per tick). `xo_call` stays
   for one-off calls (the player, the frame) where the frame does not matter.
   Never hardcode the class (`Bullet_move`) — that would break subclass override.
7. **Class definitions and class objects are read-only** (flat `<Cls>Obj` arrays,
   tree-class templates, built class objects); an instance is one assoc array per
   object: flat keys `field`, tree keys `{field}\x1c`.
8. **Mark first, clean up once**: collisions only set `killed_*` flags; the cleanup
   phase buries everything together.
9. **Measure any mechanic change**: compare before/after with the fixed-load harness;
   "it feels faster" is not evidence. Every performance number must state the CPU
   model it was measured on (`Win32_Processor.Name` on Windows, `lscpu` on Linux);
   numbers from different machines are not comparable and are not acceptance evidence.
10. **Associative arrays: compound `+=` for fixed key sets.** Writing several literal
    keys at once — `self+=([x]=$2 [y]=$3 [symbol]=$4 ...)` — is allowed and preferred
    for readability: one assignment instead of N, and ~10% fewer instructions in a
    per-call microbenchmark. This is *not* a performance argument (the win is
    ~0.5 µs per key, only visible at tens of thousands of calls per second).
    Rules:
    - the target must already be declared `declare -A`; otherwise `+=` treats it as
      an indexed append (silent wrong type);
    - never use `+=` on the parallel indexed SoA arrays (`EB_X`, `EB_Y`, `EB_ALIVE`,
      ...): it appends at the end and desynchronises the columns;
    - do not build a compound assignment from dynamic keys: that needs string
      building or `eval` and is both slower and unsafe. Use the plain loop instead.
    (Associative compound `+=` needs bash 4.3+; the project floor is 5+, so it is
    always available.)

---

## Purpose and scope

`qq_bash` is primarily a validation project for the `xo` object system.
`strafe_bash` exists to prove that `xo` can model a real, stateful, interactive
application: named objects, inheritance, mixins, lifecycle, composition, and
method dispatch under a fixed game loop.

`xo` is **not a performance library**. Its intended home is the control plane
of Bash automation: build pipelines, industrial test harnesses, deployment
steps, test fixtures, and small DSLs. It trades a little memory and dispatch
overhead for nested data, inheritance, mixins, and readable composition. It is
not intended for high-throughput data processing, real-time engines, or
untrusted input.

## Bash version status

The Bash version of `strafe_bash` is **feature-frozen**. It is not receiving
new Bosses, weapons, mechanics, or systems. Remaining work is limited to:

- bug fixes
- balance tuning
- code cleanup and removal of code smells
- architectural cleanup, including moving responsibilities out of the main
  loop into the library/classes where they belong
- keeping `xo` reusable outside the game

The 30 FPS target is intentional. Bash/MSYS performance limits are accepted;
the game is a validation showcase, not a performance benchmark.

## Future

If the game is developed further, the likely path is a **Go rewrite**. The Bash
version would remain as a behavioral, numeric, and art reference. New gameplay
and higher performance targets belong in Go, not in this Bash codebase.

## The `xo` object system

`xo` gives Bash a small, pragmatic object model. Every object is an associative
array in `XO_OBJ_POOL`; flat classes are declared directly as `<Cls>Obj` arrays.

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

Tree classes are the exception: they exist for nested data, so they are declared
with a template and built into an `x` tree at `xo_init` (the template text is
parsed once and only the class object is kept):

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

- `{FLT} => 0` marks a tree class; flat classes never set it (they inherit
  `FLT=1` from `Base`). `Division` inherits from `BaseX`, the tree root.
- Nested objects and arrays are allowed in a tree-class template. Array elements
  use the dump syntax (`o = value`); the framework materializes them per class.
  Prefer empty containers or fields created in `<Cls>_born` for large mutable
  defaults, because every instance copies the class object's default tree.
- Template format: one header line (`DivisionObj ->`) followed by
  `{field} => default` lines, `#` comments allowed. Values are unescaped once
  (`\\` becomes `\`).
- Tree instances use `{field}$X` keys; flat instances use plain keys (see the
  `EnemyObj` example above).
- A flat class declared as a template, or a tree class declared as an array,
  makes `xo_init` fail; there is no compatibility path.

Key ideas:

- **Explicit registration is mandatory.** Every flat class must add its object
  array to `XO_CLASS_FLAT_OBJ_VARS`; every tree class must add its template to
  `XO_CLASS_TREE_TMPL_VARS`; every class must list its own public methods in
  `XO_CLASS_METHODS[<class>]`; every mixin must list its public methods in
  `XO_MIXIN_METHODS[<mixin>]`.
- **Do not pre-list inherited or mixin-injected methods.** A class list contains
  only methods defined by that class. `xo_init` appends mixin and inherited
  methods to the effective list in this order: own methods, mixins, inherited.
- **Registration is the source of truth.** `XO_CLASS_METHODS` decides what is
  inherited and what `xo_class_methods_print` shows. A class method that exists
  as a function but is not registered is a contract violation.
- **Do not copy parent methods into a child registry.** `-d` / `xo_init 1`
  rejects a child entry like `XO_CLASS_METHODS[Child]='foo'` when no
  `Child_foo` function exists; the scan compares the declared list with the
  child's own `Child_*` functions.
- **Duplicate method names are rejected by validation.** `-d` / `--debug`
  (or `xo_init 1`) runs the `compgen` reverse check and rejects duplicate names
  in any class or mixin method list.
- **Flat classes have exactly one definition style**: the `<Cls>Obj` array.
  Metadata keys carry the `$X` separator (`{CLS}$X`, `{SUP}$X`, `{MIX}$X`,
  `{FLT}$X`); user fields are plain keys. `xo_init` rejects a flat class that is
  declared with a template, and rejects a tree class declared as an array.
- **Templates** (`<Cls>StaticTemplate`) exist only for tree classes (FLT=0).
- **Mixin declarations** stay as `M_XxxStaticTemplate` (declaration only, never
  built into objects: a template costs less memory than an array). `{REQUIRES}`
  is read from it for the FLT compatibility check.
- **Single inheritance** — a class gets its parent's fields and methods.
- **Mixins** — `{MIX}` lists method-only mixins; class methods win, then mixins,
  then inherited methods. The Il-2 list below is the worked example.
- **Named objects** — `xo_obj_born_named OBJ_plane Plane` for stable handles.
- **Object pool** — `XO_OBJ_POOL[OBJ_7]` stores the class; `xo_obj_bury` frees it.
- **Dispatch** — `xo_call "$obj" move`; specialise with `Enemy_move`,
  `Boss_move`, etc.
- **Type checks** — `xo_is_a "$obj" BossBase`.

### Class debug view (`xo_debug_classes`)

For debugging class inheritance, fields, methods and mixins together, use:

```bash
xo_debug_classes        # indent 4
xo_debug_classes 2      # indent 2
```

It requires `xo_init` to have run. It builds a **separate** global tree:

```text
XO_CLASS_DEBUG_TREE
```

and prints it with `x_dump`. It does **not** modify
`XO_CLASS_INHER_TREE`, `XO_INHER_CHAIN_DUMP_CACHE`, class objects or method
tables.

The tree has this shape:

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

Notes:

- `{@ATTRIBUTES}` shows **effective** fields, including inherited ones. A field
  inherited from a parent is still listed under the child; the tree does not
  currently record the field's defining class.
- Nested dictionaries and arrays are preserved; array elements use the normal
  `x_dump` array representation (`o = value`).
- `{@...}` keys are reserved for debug sections, so a class field named
  `META` / `ATTRIBUTES` / `FUNCTIONS` / `MIXINS` cannot collide with them.
- The debug tree is disposable; build it on demand. It is not a hot-path
  structure. A full game dump is roughly 1000 lines and about a second, so do
  not call it from the game loop.
- `xo_dump_inher_chain` remains the raw canonical inheritance dump;
  `xo_class_methods_print <class>` remains the compact per-class method list.

The regression fixture is `test/bashlib/test_xo_debug_classes.sh`.

### Object lifecycle: born and retire

```bash
xo_obj_born Enemy                # template fields copied in, then Enemy_born runs
xo_obj_born_named OBJ_boss Boss  # same, with a stable handle
xo_obj_bury "$obj"               # <CLS>_retire runs, then the pool entry is removed
```

- `xo_obj_born*` copies the class object's fields, registers the object in
  `XO_OBJ_POOL`, then calls `<CLS>_born` (default no-op).
- `xo_obj_bury` calls `<CLS>_retire` before freeing anything. Retire means "the
  object leaves the world" — the memory and soul, not the body: whatever it owns
  is retired with it (`Plane_retire` handles its weapon objects). Every class
  inherits `Base_retire`; a missing `<CLS>_retire` is an error.
- Retiring also drops the object's `{OBJMIX}` routing, so a reused named handle
  cannot inherit the previous object's abilities.

#### hire / fire (reuse)

`xo_obj_hire` / `xo_obj_fire` are storage-level reuse, not a new life cycle.
`hire` pops a fired body from the resource market (falling back to `born` when it
is empty), and `fire` retires a body and keeps it instead of destroying it. An
empty market makes `hire` identical to `born`, so code that never fires behaves
exactly as before.

**Simple objects only.** A composite object — a class that owns other objects,
today only `Plane` with its weapon handles in `{w1}`..`{w5}` — must always use
`bury` and die together with its children. A retire hook cannot tell whether it
runs inside a bury or a fire: firing a composite would destroy the children
while keeping the parent, and the re-hired parent would hold handles to dead
objects. Recycling composites would require passing the exit mode to the retire
hook and rebuilding the parent/child links in the born hook; until then this
constraint has no exceptions.

The game recycles the five hot projectile classes — `Bullet`, `EnemyBullet`,
`BossBullet`, `EnemyMissile`, `Missile` — through one spawn point per family
(`enemy_bullet_spawn` for enemy bullets, the plane/missile launch code for ours)
and the matching death exits. Each declares `<cls>ResetFields` with what its
lifetime mutates: `prev_x prev_y` for all of them, plus `color` for player
bullets (lasers paint their power colour onto the body).

Measured on the reference machine: a bullet lifecycle drops from ~0.95 ms
(born+bury) to ~0.75 ms (hire+fire), and the other four classes land between
1.3x and 1.5x. The rest of the cost is the retire hook, the born hook and the
reset writes, which both paths pay; recycling removes only the class-template
deserialisation.

The game's class tree:

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

Method-only mixins used by the plane classes:

```text
M_Blink
M_LongBlink
M_Ram
```

This is what lets the game add a new enemy or Boss without a giant `case`
statement: class definitions hold the data, methods hold the behaviour.

### Object-level mixins

Class-level `{MIX}` is fixed at `xo_init` time. An individual object can also
gain and lose abilities at runtime through `{OBJMIX}` — that is how a Boss picks
up two of its five random buffs and swaps them on phase changes:

```bash
xo_obj_mixin_add    OBJ_boss M_BuffInvuln M_BuffMissile   # one or many, idempotent
xo_obj_mixin_delete OBJ_boss M_BuffInvuln                 # no args = drop them all
xo_obj_mixin_list   OBJ_boss                              # -> "M_BuffMissile ..."
xo_obj_call         OBJ_boss buff_tick                    # first holder wins
xo_obj_call_all     OBJ_boss buff_tick                    # every holder runs
```

An ability can provide two optional hooks. They use a private leading underscore,
so they are never injected as callable methods and two abilities can both
implement them:

```bash
M_BuffMissile__init    () { local -n s=$1 ; s["{ms_cd}$X"]=0 ; }   # after add
M_BuffMissile__cleanup () { local -n s=$1 ; s["{ms_cd}$X"]=0 ; }   # before delete
```

`_init` runs after the ability is registered, `_cleanup` before it is
unregistered. Burying an object does not run `_cleanup`: the whole object
variable is destroyed, so its state goes with it, and a reused handle is born
fresh from the template. Cleanup exists for removing an ability while the object
is still alive. Everything an ability does when it is acquired — including
effects on the world, such as firing the Boss wave or slowing the player —
belongs in `_init`; there is no separate "on gain" hook.

Neither hook is required. The convention is: an ability that owns object state
implements `_init` and `_cleanup` as a pair (create on the way in, clear on the
way out); a stateless ability implements at least `_init` or provides a public
method. The framework only rejects a mixin that has neither a public method nor
an `_init`.

`xo_obj_mixin_add` applies its arguments in order and is idempotent: an ability
the object already holds is skipped and its `_init` is not run again, so a
running timer is not reset. Duplicate names inside a single call are collapsed,
because adding a one-shot ability twice in the same call must not fire it twice.
A one-shot ability may remove itself from inside `_init`; the loop re-reads
`{OBJMIX}` after every argument, so the removed ability is not appended back when
the next one is added, and the remaining arguments still take effect. To trigger
a one-shot ability again, add it in a separate call — by then it is no longer in
the list, so it does not count as already held.

In short: for a persistent ability, adding it once or many times is identical
(idempotent, `_init` runs once). For a one-shot ability, repeats in the same call
are also identical; only a separate call fires it again, which is intended.

### Flat classes

`Base` is a **flat** class: all of its fields are uppercase metakeys, and objects
built from it store user fields without the `{...}$X` wrapper. `BaseX` (a
`Base` subclass) is the root of **tree** classes, which keep the wrapped keys and
the `x` tree machinery. A class picks its shape with the `{FLT}` field:

```text
    {FLT} => 1     flat class  (rules above);  user field {hp}$X is stored as hp
    {FLT} => 0     tree class  (BaseX root);   user field stays {hp}$X
```

`{FLT}` is inherited, so every class under `Base` is flat unless it overrides the
field. `xo_init` strips flat class objects and rebuilds their `ObjStr` cache, so
instances are born flat; tree classes are left untouched.

Key names after stripping:

```text
    metakeys, kept wrapped in both shapes:   {CLS}$X {SUP}$X {MIX}$X {OBJMIX}$X {FLT}$X
    flat class user fields:   {hp}$X  ->  hp        read with  self[hp] / obj[hp]
    tree class user fields:   {hp}$X  unchanged     read with  self["{hp}$X"]
```

A flat class object has no `x` tree nodes (`1.c.*`, `max_index`, ...) any more:
it is a plain associative array, so `x_get` / `x_set`-style access does not apply
to it. `Base_print` dumps it as a plain array; `BaseX_print` keeps `x_dump`.

**No ad-hoc fields.** The flat shape makes it *possible* to write any key into an
object, but it is forbidden: every field a method touches must be declared in the
class template (with a comment, as the constitution requires), and an undeclared
key is a bug. Field names follow the table at the top of `xo.in`: public fields
are lower snake case (`hp`, `prev_x`), private ones are `_ClassName_field`
(`_Boss_phase`), and `_kind{...}` temporary containers are framework-internal and
never used for game data.

#### The `{REQUIRES}` rule for mixins

A mixin that only works with one shape must say so in `{REQUIRES}`, and the
declaration is **mandatory in the first position**:

```text
    {REQUIRES} => FLT=1 bi_cd inv_cd     # flat only, then its field dependencies
    {REQUIRES} => FLT=0                  # tree only
    {REQUIRES} => hp maxhp               # no FLT: both shapes
```

- `FLT=1` means "flat classes only", `FLT=0` means "tree classes only"; the
  framework rejects a class/mixin pair whose shapes differ.
- **No `FLT` token means the mixin supports both shapes**, and then its
  implementation must handle both key layouts itself (`self[x]` and
  `self["{x}$X"]`, or through a framework accessor). Writing it for one shape
  only will silently read empty fields on the other.
- `FLT` is required to be the first token by convention (it keeps the declaration
  readable and greppable). The framework detects it with a token-boundary regex,
  so it is found whether the next character is a field, a newline, or the end of
  the line; `FLT=10` is not mistaken for `FLT=1`.

#### Migrating to flat field access

Once a class is flat, its own methods and its `_born` / `_retire` hooks must use
the stripped keys:

```bash
    # tree style (old)                 # flat style (new)
    ${self["{x}$X"]}                    ${self[x]}
    self["{x}$X"]=$x                    self[x]=$x
    ${self["{hp}$X"]:-0}                ${self[hp]:-0}
```

Metakeys are the only exception: they stay wrapped, e.g. `${self["{CLS}$X"]}` and
`${self["{OBJMIX}$X"]}`. Mixin bodies follow the same rule (or the `{REQUIRES}`
declaration must say they only support one shape).

### Il-2 mixin stack

Il-2 uses a three-entry Mixin list:

```text
{MIX} => M_LongBlink M_Blink M_Ram
```

- `M_LongBlink` overrides `blink_start` to 4 seconds.
- `M_Blink` supplies the normal blink tick/visibility methods; other planes
  use its 3-second default.
- `M_Ram` supplies the ramming ability: while Il-2 is blinking after a hit,
  colliding with an enemy deals 5 damage. The ram has a 10-tick cooldown and
  can kill enemies or a Boss through the normal score/death paths.

Player-facing summary of the same build: take one hit to enter the 4-second
angry state, then fly into enemies. The invulnerability window matches the
blink duration.

## Single-cell projectiles: struct-of-arrays

Enemy bullets, boss bullets and homing missiles deliberately **do not** use the
`xo` object system. They have no mixins, no inheritance and no lifecycle hooks:
they are a few numbers with a glyph. Through `xo` each of them cost a method
call, a nameref bind and several hash reads per tick (~155µs); as parallel
arrays indexed by slot they cost ~30µs.

`classes/projectiles/soa_bullets.sh` owns the whole model:

| array       | meaning                                                        |
|-------------|----------------------------------------------------------------|
| `EB_ALIVE`  | 1 = slot in use                                                |
| `EB_TYPE`   | 0 = straight down (4 ticks/row), 1 = vector + step, 2 = homing |
| `EB_X/EB_Y` | position (1-based, same as the screen)                          |
| `EB_VX/VY`  | per-move delta (types 1 and 2)                                 |
| `EB_STEP`   | move every N ticks                                             |
| `EB_CD`     | current tick inside that period                                |
| `EB_DMG`    | damage when it reaches the player                              |
| `EB_FUEL`   | homing missiles only: moves left before it self-destructs      |
| `EB_GLYPH`  | ready-to-emit bytes (colour + symbol + reset)                  |
| `EB_FREE`   | stack of dead slots                                             |
| `EB_N`      | highest slot ever used (loop bound)                            |
| `EB_LIVE`   | live count (used by the spawn limits)                          |

Slots are never compacted, so a slot number is stable for the life of one
bullet and can be used as its framebuffer owner (stored as `slot + 1`, so 0
means "empty"):

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

One tick pass does everything for a bullet — move, hit test, framebuffer:

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

Spawn entry point is unchanged, so every boss pattern and test keeps working:

```bash
enemy_bullet_spawn EnemyBullet  x y sym damage
enemy_bullet_spawn BossBullet   x y vx vy sym damage step [colour]
enemy_bullet_spawn EnemyMissile x y [fuel] [step]
```

What still belongs to the object system: anything with art, HP, mixins or a
state machine — enemies, bosses, drops, words, and future giant multi-cell
projectiles (they are entities, not data; they can carry their own art and
hitbox size). The rule of thumb: *single cell and no behaviour -> SoA; art or
behaviour -> object.*

Measured at 110 bullets: tick 26.9ms -> 17.2ms. The three former classes
(`enemy_bullet.sh`, `boss_bullet.sh`, `enemy_missile.sh`) are gone; the boss
test reads slots through `eb_field`.

## The `x` tree

`x` is an in-memory tree with JSON semantics, implemented in pure Bash. It
supports objects, arrays, nulls, booleans, ordered children, and path access.

- `x_init [OBJ|ARR]` — create an empty tree
- `x_insert` / `x_delete` / `x_get_leaf` / `x_get_tree`
- `x_push_leaf` / `x_pop_leaf` / `x_shift_leaf` / `x_unshift_leaf`
- `x_walk` / `x_iter` / `x_to_flat_array` / `x_flat_to_tree`
- `x_walk_dict_tree` — fast walker for **pure `{}` trees**; it rejects arrays
  and physical-id nodes. Use `x_walk` for mixed trees.
- `x_to_json` / `x_from_json` / `x_dump` / `x_equals` / `x_graft`

Full parameters and return codes are documented in the function headers of
`src/bashlib/x.in`.

### Dataclass handles (`data.in`)

`data.in` adds lightweight external containers that are **not** `xo` classes:

```text
ARR    indexed Bash array
ASSOC  associative Bash array
DTREE  x tree with OBJ root
ATREE  x tree with ARR root
```

Handles are `ARR_1`, `ASSOC_1`, `DTREE_1`, `ATREE_1`, ... from the global
`XO_DATA_CLASS_IDX`. One pool records liveness and type:

```text
XO_DATA_CLASS_POOL[handle] = ARR|ASSOC|DTREE|ATREE
```

API:

```bash
. "$STRAFE_LIB_HOME/data.sh"   # data.in is independent of xo
xo_data_born_arr       # REPLY=ARR_N
xo_data_born_assoc     # REPLY=ASSOC_N
xo_data_born_dtree     # REPLY=DTREE_N
xo_data_born_atree     # REPLY=ATREE_N

xo_data_bury "$handle"
xo_data_is_live "$handle"
xo_data_type "$handle" # REPLY=kind
```

Typical owner:

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

Contract:

- A handle has exactly **one owner**; do not share it between objects.
- Do not store another dataclass handle inside a dataclass container.
- The owner must call `xo_data_bury`; do not `unset` a handle directly.
- `fire` runs `retire`, and `hire` runs `born`, so the owner must release in
  `retire` and recreate in `born` if the data should exist after rehire.
- `xo_data_clear` removes all live dataclasses; use it only in tests/shutdown.

Dataclasses are for an external bag attached to a flat/tree object, not for
local temporaries and not for inheritance/method dispatch.

### Input/output contract

The tree format is ours, so the contract is enforced by convention rather than
by defensive code:

- **Encoding**: keys, values and dump/template text are valid UTF-8. Invalid
  bytes and isolated C1 bytes (`0x80`–`0x9F` outside a UTF-8 sequence) are out
  of scope; the escape/unescape pair is symmetric for valid UTF-8 only.
- **Non-BMP characters** (`U+10000` and above, e.g. emoji) must be written as
  literal UTF-8. `\uXXXX` covers the BMP only; surrogate escapes such as
  `\uD83D` are not supported and are not converted back to a character.
- **Control characters**: a dump/template line must not contain bare C0, DEL or
  C1 characters (a newline is a line separator, not data). Write them as
  `\uXXXX`, or use the `\b` `\f` `\r` `\t` shorthands. Multiline values and keys
  use the `|` continuation form; the writer emits it and
  `x_rebuild_from_dump` merges it back.
- **Keys**: `{...}` delimiters, a literal `}` inside a key must be written
  `\}`, and a key must not contain a raw `$X` separator.
- **Arrays are dense**: the dump writes elements in index order and the rebuild
  renumbers them from 0. Sparse or out-of-order array dumps are not supported.
- **Malformed structure fails loudly**: for example `=>` without the trailing
  space makes `x_rebuild_from_dump` return non-zero; it never yields a partial
  tree with silently dropped branches.

`str_escape_keep_nl` (values), `str_escape_key` (keys, additionally escapes
`}`) and `str_unescape` form one inverse pair under these rules.

## Build and test

```bash
./build.sh        # generate .sh files from .in sources
./test.sh         # run the test suite
```

`build.sh` compiles the `#@if` blocks in `src/bashlib/*.in` (and
`test/bashlib/test_x.in`) into the `.sh` files that the game and tests source.
The generated `.sh` files are not tracked by git; run `./build.sh` after a fresh
clone or a clean, and `./build.sh -d` to remove them again.

## Terminal and input notes

### Mouse reporting

The game uses xterm SGR mouse reporting (`1006`) plus the `1000` / `1002` /
`1003` tracking fallbacks, so terminals that implement only click or drag
tracking still move the plane. Coordinates are cell-based, not pixel-based.

- Capture is always enabled while playing; there is no toggle, which is why
  terminal text selection is unavailable until the game exits.
- `_mouse_assert` re-sends the enable sequence every 30 ticks, because some
  terminals silently drop mouse reporting after a focus change.
- The input loop caps mouse events per iteration so a fast mouse cannot starve
  the game loop.
- `ESC[?25l` hides the text cursor. ANSI cannot hide the OS pointer; that is a
  terminal preference (Windows Terminal / mintty mouse settings).
- The pointer target is two rows below the plane centre, so the pointer does not
  sit on the sprite. Mouse motion and left-click both move the plane.
- A plain Windows console window (conhost) does not translate mouse input into
  VT sequences, so the mouse is inert there; mintty provides its own pty and
  does report it.
- WindTerm may implement only click/drag tracking rather than any-event motion.
- Mouse capture is disabled on quit and on GAME OVER.

### Synchronized output

Each frame is wrapped in `DECSET 2026`: the buffer goes out between
`ESC[?2026h` and `ESC[?2026l`, so the terminal composes the frame once instead
of painting the intermediate erase/redraw state. Terminals without `2026`
ignore the sequences.

### Alternate screen

The game enters the alternate screen (`ESC[?1049h`) at startup and leaves it
(`ESC[?1049l`) in `term_restore`, instead of clearing the screen on exit.

- The alternate screen has no scrollback, which avoids the scrollback-based
  mouse row offset some terminals report: mintty counts scrollback lines into
  the mouse row number, which pushed the plane to the edge of the screen.
- Leaving the alternate screen restores the player's previous content, so
  `term_restore` must not clear the screen afterwards.
- A `HUP` trap covers window close, so the terminal is not left on the
  alternate screen.

## Rendering notes

Everything the game draws is appended to one buffer (`FRAME_BUF`) and flushed
once per frame; nothing in the render path writes to the terminal directly.
That keeps two properties that later fixes depend on:

- **Frames are atomic.** `frame_flush` wraps the whole buffer in one
  synchronized-output bracket (see above), so the terminal composes one frame
  instead of showing the intermediate "erase old position, then draw new one"
  state.
- **One write per frame.** The flush is a single `printf`; adding per-frame
  work here costs frames, so keep it to one call.

Draw order in the render pass is: erase previous positions, draw bullets,
missiles, enemy bullets, enemies, drops and words, then the player last, so
nothing can cover the plane. The player's own erase is skipped while it is
stationary and its art shape is unchanged, because that frame redraws the same
cells anyway.

## Scanning waves

A wave is one full-width row of `~` that sweeps the playfield, damages whatever
it passes over and clears the bullets on the rows it sweeps. One shared system
drives both sides; only the owner differs.

- Boss wave (`M_BuffWave`): red, top to bottom, 3 damage, strips the player's
  shield even though the damage itself still respects invulnerability frames.
  It also clears *our* bullets. One grant fires a burst of 2-4 waves, 1-3 seconds
  apart, and the ability uninstalls itself as soon as the last one is fired — so
  it is driven by `buff_tick`, not fired once from `_init`.
- Player wave (drop `W`, fired on pickup): green, bottom to top, 30 damage per
  enemy and per wave, and it clears enemy bullets and homing missiles. No gaps:
  a defensive tool should not have holes in it.

Waves live in a small fixed slot table (`WAVE_SLOTS` = 5), so several can be on
screen at once — that overlap is the point of the boss burst: each wave re-rolls
its gaps, so the safe corridor keeps moving and the player has to reposition
continuously. State is one parallel array per attribute (`WV_ON`, `WV_Y`,
`WV_DIR`, `WV_OWNER`, `WV_DMG`, `WV_CD`, `WV_LAST_Y`, `WV_HIT`, `WV_GAP1/2`,
`WV_LINE`, `WV_CLR`); `WAVE_ON` is only a derived "any wave alive" flag for hot
paths. `_wave_start` takes the first free slot and returns its index in `REPLY`,
or fails when the table is full (the ability then retries on the next tick rather
than dropping a shot).

Player damage from overlapping waves is summed per tick and then still goes
through the usual invulnerability window, so three waves sweeping over the player
in quick succession cost one hit, not three. The pressure is about dodging, not
about melting the health bar.

### Why clearing uses a swept band, not a row comparison

Naively clearing "bullets whose row equals the wave row" misses most of them,
and there are two independent reasons:

1. The wave dwells `WAVE_STEP_TICKS` (3) ticks per row while `EnemyBullet`
   moves every 4 ticks. At the tick the wave arrives, most bullets are not on
   that row yet, and by the time they are, the wave has moved on.
2. A bullet and the wave can even swap rows inside a single tick: the wave goes
   9 -> 8 while a bullet goes 8 -> 9, so they never share a cell at all.

So the wave records the row band it swept during the current tick (one row
while it dwells, two rows on the tick it advances) and clears bullets inside
that band, on every tick it dwells. The check is two comparisons instead of one
and removes both misses.

### Escape gaps

The boss wave punches `WAVE_GAP_COUNT` (2) gaps of `WAVE_GAP_W` (3) cells at
random, and the positions stay fixed for that wave. Re-rolling them per row
would force the player to chase the gap downwards while the wave descends,
which is harder than standing still. The player's hitbox is a single cell, so a
three-cell gap is comfortable to stand in but still has to be hit.

Gaps also let bullets through: the clear check skips bullets inside a gap, so
"the net only catches what it touches" holds for both damage and bullets.

### Rendering and cost

The wave is drawn right after the erase pass and before the objects, so it
never hides bullets or enemies, and the objects redraw over it. When the wave
advances, the previous row is erased; when it ends, the last row is erased
once. A row costs roughly 260 bytes per frame (about 4% of a frame), and the
clearing pass only runs while a wave is alive (~90 ticks), so the frame budget
is untouched. `WAVE_LINE` is built once per wave and reused every frame.
