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
|   class template --xo_init--> class object ${cls}Obj (x tree + fields)     |
|                                   |                                        |
|                                   +-- KV snapshot ${cls}ObjStr             |
|   instance OBJ_n = one assoc array; keys "{field}\x1c", values = fields    |
|   lifecycle   born / hire / fire / bury                                    |
|   hooks       <cls>_born (enters the world)  <cls>_retire (leaves it)      |
|   dispatch    xo_call (class method)  xo_obj_call (capability, first wins) |
|               xo_obj_call_all (hook fan-out, no fallback to class)         |
|   mixins      {OBJMIX} field + XO_OBJ_METHOD routing (boss abilities)      |
|   market      where fired objects wait; hire reuses them first             |
|----------------------------------------------------------------------------|
| DATA STRUCTURE  src/bashlib/x.in                                           |
|   x tree: node ids, .c child table, .s order, <id>.k key, <id> value       |
|   x_walk / x_dump / CLASS_INHER_TREE (class inheritance)                   |
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
      | 4 fire: push to RES_MARKET               |
      |   bury: unset the variable + leave pool  |
      +------------------------------------------+
           |                              |
           v                              v
   fire -> IDLE (RES_MARKET)   bury -> GONE (no variable)
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

**Object system (`xo.in`)**

| Variable | Purpose |
|---|---|
| `XO_OBJ_POOL[handle]` | handle -> class. The only registry of live objects; every "is it alive" check uses it |
| `XO_OBJ_SEQ` | anonymous handle counter, produces `OBJ_11`, `OBJ_12`, ... |
| `${cls}Obj` | per-class class object: x tree plus flat fields (field defaults live here) |
| `${cls}ObjStr` | KV snapshot of the class object; born does one `declare -gA` with it (the expensive part) |
| `${cls}StaticTemplate` | the class template text, the single source of a class definition |
| `${cls}ResetFields` | volatile fields of a recyclable class; fire resets only those (e.g. `prev_x prev_y color`) |
| `CLASS_INHER_TREE` | class inheritance chain (x tree); used by `xo_init` to build dispatch |
| `XO_METHOD_INHERITED` | forwarding table for inherited methods |
| `XO_INHER_CHAIN_DUMP_CACHE` | cached inheritance dump, avoids recomputation |
| `_XO_INIT_CALLED` | `xo_init` may run only once |
| `XO_MIXIN_METHODS[mixin]` | which methods each mixin provides |
| `XO_OBJ_METHOD[handle\|method]` | per-object method routing (mixin implementation names) |
| `XO_OBJ_MIXED[handle]` | set of objects carrying mixins (cheap gate: empty set means bury does one length check) |
| `RES_COUNT[class]` | resource market: number of idle bodies of that class |
| `RES_MARKET["class\|index"]` | resource market: idle handles, O(1) LIFO |
| `RES_LIMIT[class]` `RES_LIMIT_DEFAULT` | per-class recycle cap / default 512 |
| `XO_RESET_FIELDS[class]` | cache: the class reset list, copied from `<cls>ResetFields` |
| `XO_RESET_DEF["class\|field"]` | cache: template default of a volatile field, read from the class object |
| `XO_RESET_READY[class]` | cache: flag, the reset list was preprocessed (lazy, on first fire) |

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

**Data structures (`x.in`, `grammar.sh`)**

| Variable | Purpose |
|---|---|
| `BASH_GRAMMAR[...]` | bash capability switches probed at build time, used by `#@if` |
| `RENDER_FPS` `RENDER_US` | measured render figures, diagnostics only |

**Game runtime (`config/globals.sh`)**

Live-object handle lists, rebuilt every tick (collect first, then clean up once):
`BULLETS`, `ENEMY_BULLETS`, `MISSILES`, `ENEMIES`, `DROPS`, `WORDS`.

| Variable | Purpose |
|---|---|
| `MISSILE_TRAIL_CLEAR` | cells a missile trail still has to erase |
| `HIT_FX`, `BOMB_FX_POS`, `BOSS_DEATH_POS` | hit sparks, bomb and boss-death effect queues |
| `BOSS_DEATH_*` | boss death animation state (tick, style, centre, wave) |
| `CLEAR_BANNER_*` | the "ACE" banner remaining ticks and text |
| `FRAME_BUF` | the whole frame output buffer; render only appends, one flush per frame |
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
6. **Class templates and class objects are read-only**; an instance is one assoc
   array per object, keys formatted `{field}\x1c`.
7. **Mark first, clean up once**: collisions only set `killed_*` flags; the cleanup
   phase buries everything together.
8. **Measure any mechanic change**: compare before/after with the fixed-load harness;
   "it feels faster" is not evidence.

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

`xo` gives Bash a small, pragmatic object model. Classes are declared as
templates, and every object is an associative array in `XO_OBJ_POOL`.

```bash
readonly EnemyStaticTemplate='
    EnemyObj ->
        {CLS} => Enemy
        {SUP} => Entity
        {MIX} =>
        {x} => 0
        {y} => 0
        {hp} => 1
'

Enemy_born () {
    local -n self=$1
    self["{x}$X"]=10
    self["{y}$X"]=5
}

Enemy_move () {
    local -n self=$1
    self["{y}$X"]=$(( ${self["{y}$X"]} + 1 ))
}

xo_init
xo_obj_born Enemy      # -> REPLY=OBJ_1
xo_call "$REPLY" move
```

Key ideas:

- **Templates** use `{CLS}`, `{SUP}`, `{MIX}` and arbitrary `{field}` entries.
- **Single inheritance** — a class gets its parent's fields and methods.
- **Mixins** — `{MIX}` lists method-only mixins; class methods win, then mixins,
  then inherited methods. The Il-2 list below is the worked example.
- **Named objects** — `xo_obj_born_named OBJ_plane Plane` for stable handles.
- **Object pool** — `XO_OBJ_POOL[OBJ_7]` stores the class; `xo_obj_bury` frees it.
- **Dispatch** — `xo_call "$obj" move`; specialise with `Enemy_move`,
  `Boss_move`, etc.
- **Type checks** — `Base_is_a "$obj" BossBase`.

### Object lifecycle: born and retire

```bash
xo_obj_born Enemy                # template fields copied in, then Enemy_born runs
xo_obj_born_named OBJ_boss Boss  # same, with a stable handle
xo_obj_bury "$obj"               # <CLS>_retire runs, then the pool entry is removed
```

- `xo_obj_born*` copies the class template's fields, registers the object in
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
statement: class templates hold the data, methods hold the behaviour.

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

## The `x` tree

`x` is an in-memory tree with JSON semantics, implemented in pure Bash. It
supports objects, arrays, nulls, booleans, ordered children, and path access.

- `x_init [OBJ|ARR]` — create an empty tree
- `x_insert` / `x_delete` / `x_get_leaf` / `x_get_tree`
- `x_push_leaf` / `x_pop_leaf` / `x_shift_leaf` / `x_unshift_leaf`
- `x_walk` / `x_iter` / `x_to_flat_array` / `x_flat_to_tree`
- `x_to_json` / `x_from_json` / `x_dump` / `x_equals` / `x_graft`

Full parameters and return codes are documented in the function headers of
`src/bashlib/x.in`.

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
