# Modding Stackflow

Stackflow supports mods through the [Godot Mod Loader (GML)](https://wiki.godotmodding.com/#mod-developer). This guide shows you how to build a mod that adds **new blocks** and **hooks into existing game logic** — no core files edited.

If you've never used GML before, read the official [Mod Developer wiki](https://wiki.godotmodding.com/#mod-developer) first. This document covers the parts that are **specific to Stackflow**.

---

## Table of contents

1. [Quick start (no Godot needed)](#quick-start-no-godot-needed)
2. [Examples](#examples)
3. [API reference](#api-reference)
4. [How mods load](#how-mods-load)
5. [Mod folder structure](#mod-folder-structure)
6. [The manifest](#the-manifest)
7. [Your mod entry script](#your-mod-entry-script)
8. [Adding a new block](#adding-a-new-block)
   - [Recipe](#recipe)
   - [Name & description](#name--description)
9. [Changing core blocks](#changing-core-blocks)
10. [Hooking existing logic](#hooking-existing-logic)
11. [Textures](#textures)
12. [Packing & publishing to the Steam Workshop](#packing--publishing-to-the-steam-workshop)

---

## Quick start (no Godot needed)

You only need a text editor and the game.

1. Open Stackflow → **Mods** (bottom-right of the main menu) → **Open folder**. This opens `mods-source/` next to the game executable.
2. Copy [`Stackflow-TestBlock/`](Stackflow-TestBlock) from this repo into it and rename it `YourName-YourMod` (also update `namespace`/`name` in `manifest.json`).
3. Edit `mod_main.gd`, drop PNGs in `textures/` (plain PNGs work — no import step).
4. Back in the **Mods** screen, click **Pack**: your folder is zipped into `mods/YourName-YourMod.zip`.
5. Restart the game. Your mod shows under **Loaded mods** (red = failed; details in the log, see below).
6. When it works, click **Publish** to upload it to the Steam Workshop.

**Logs:** every load error is written to `modloader.log` in the game's user data folder (`%APPDATA%/Stackflow/logs/` on Windows, `~/.local/share/Stackflow/logs/` on Linux).

---

## Examples

Each folder in this repo is a complete mod: copy one into `mods-source/` and click **Pack**.

| Mod | Shows |
|---|---|
| [`Stackflow-TestBlock`](Stackflow-TestBlock) | Minimal new block (Ruby) with its own PNG, translations, and a script hook. Start here. |
| [`Stackflow-FuseBlock`](Stackflow-FuseBlock) | Per-instance state: `set_on_place` starts a `Timer` that charges the block every second. |
| [`Stackflow-CrowBlock`](Stackflow-CrowBlock) | Reacting to other blocks: `set_on_block_destroyed`, plus a `recipe` gate. |
| [`Stackflow-VanillaTweaks`](Stackflow-VanillaTweaks) | Changing core blocks: edit metadata and wrap a vanilla effect. |

---

## API reference

[`API.md`](API.md) lists every class, method, property, signal and enum a mod is meant to use (`BaseBlock`, `PlacedBlock`, `GameManager`, `GameData`, ...), with their doc comments. Anything not listed there is internal and may change between game versions.

`API.md` is generated from the game's source with Godot's doctool:

```sh
python3 tools/generate_api.py --game ../stackflow --godot godot
```

---

## How mods load

At boot Stackflow registers all of its **core blocks** through a single public API (`BaseBlock`). Every block — core or modded — lives in one place: the `BlockRegistry` autoload.

The boot order that matters to you:

1. `BlockRegistry` autoload loads (the central store).
2. `CoreBlocks` autoload runs and registers **all vanilla blocks**.
3. When done, `CoreBlocks` sets `BlockRegistry.core_blocks_ready = true` and emits the `BlockRegistry.blocks_ready` signal.
4. **Godot Mod Loader runs your mod**, which reacts to that signal and registers your content.

> **Why wait for the signal?** By registering *after* the core blocks exist, your mod can safely **add**, **override**, or **extend** vanilla blocks without racing the core.

---

## Mod folder structure

A mod is a folder inside `mods-source/` (next to the game executable). Inside the packed zip it lives under `mods-unpacked/`, which is the path your code sees at runtime:

```
mods-source/
└── YourName-YourMod/
    ├── manifest.json      # required metadata
    ├── mod_main.gd        # required entry script
    └── textures/          # your PNGs (optional)
        └── ruby.png
```

The folder name **must** be `Namespace-Name` and match the `namespace` + `name` in your manifest (e.g. `Stackflow-TestBlock`).

---

## The manifest

`manifest.json` describes your mod to GML. Minimal Stackflow example:

```json
{
    "name": "TestBlock",
    "namespace": "Stackflow",
    "version_number": "1.0.0",
    "website_url": "https://github.com/stackflow",
    "description": "Registers a new block (Ruby) and hooks PlacedBlock.",
    "dependencies": [],
    "extra": {
        "godot": {
            "authors": ["YourName"],
            "compatible_mod_loader_version": ["7.0.0"],
            "compatible_game_version": ["1.3.0"],
            "incompatibilities": []
        }
    }
}
```

- `namespace` + `name` form your mod id (`Stackflow-TestBlock`). Keep it unique.
- `compatible_game_version` — the Stackflow version(s) you tested against.
- `dependencies` — other mod ids you require.

---

## Your mod entry script

`mod_main.gd` extends `Node` and is instanced by GML. Two lifecycle points:

- **`_init()`** — install script **hooks** here (they must be registered before the target script runs).
- **`_ready()`** — register your **blocks** here, gated on the `blocks_ready` signal.

```gdscript
extends Node

const MOD_ID := "YourName-YourMod"


func _init() -> void:
    # Hooks must be added before the hooked script executes.
    ModLoaderMod.add_hook(_my_hook, "res://scripts/placed_block.gd", "execute_destroy_effect")


func _ready() -> void:
    # blocks_ready guarantees the core blocks already exist.
    if BlockRegistry.core_blocks_ready:
        _register_blocks()
    else:
        BlockRegistry.blocks_ready.connect(_register_blocks)
```

> **Important:** always guard with the `core_blocks_ready` check *and* the signal connect. If your mod loads late the signal may have already fired — the boolean handles that case; otherwise the connect handles the normal case.

---

## Adding a new block

Blocks are **code-driven** — no `.tres` resources. You build a `BaseBlock` and it auto-registers itself in the `BlockRegistry` the moment you construct it.

### Constructor

```gdscript
BaseBlock.new(id, groups, min_amount, max_amount, recipe = [], price = 0, unlock_round = 0)
```

| Param | Type | Meaning |
|-------|------|---------|
| `id` | `StringName` | Unique id. **Namespace it** (`"yourmod.ruby"`) to avoid collisions. |
| `groups` | `Array[GameData.BlockGroups]` | Synergy groups (e.g. `MINERALS`, `CASINO`). |
| `min_amount` / `max_amount` | `int` | How many of this block a piece can contain. |
| `recipe` | `Array[StringName]` | **Unlock requirement** — the block only appears in the Block Reward once the player already owns **at least one** of these block ids in their original deck. Empty = no requirement, always eligible. See [Recipe](#recipe). |
| `price` | `int` | Cost in the Block Selection screen (`0` = free). |
| `unlock_round` | `int` | Round the block becomes eligible (`0` = from the start). |

### Fluent setters

Each setter returns the block, so they chain. All are optional:

- `set_destroy_effect(func(ctx: DestroyEffectContext) -> void)` — the block's own effect when cleared by a line. `ctx.block` is the `PlacedBlock`; `ctx.payload` is a `Dictionary` for extra data.
- `set_on_place(func(block: PlacedBlock) -> void)` — per-instance setup when the block is placed (e.g. start a Timer).
- `set_on_block_destroyed(func(owner: PlacedBlock, destroyed: PlacedBlock) -> void)` — observer fired whenever **any** block is destroyed, for blocks that react to others.

### Example

```gdscript
func _register_blocks() -> void:
    if BlockRegistry.has_block(&"yourmod.ruby"):
        return  # already registered

    var ruby := BaseBlock.new(&"yourmod.ruby", [GameData.BlockGroups.MINERALS], 3, 5)
    ruby.texture_path = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/textures/ruby.png"

    ruby.set_destroy_effect(func(ctx: DestroyEffectContext) -> void:
        GameManager.add_points(50)
        PointNotification.create_and_slide(ctx.block.get_center_position(), PointNotification.BLUE, 50)
    )
```

That's it — the block now shows up in rolls and runs its effect on line clear.

### Recipe

`recipe` controls **when** a block becomes eligible to appear in the Block Reward, based on what the player already has. It is **not** a crafting recipe.

The rule is a logical **OR**: the block is only offered once the player owns **at least one** of the listed block ids in their **original deck**. If the list is empty there's no requirement and the block is eligible from the start (subject to `unlock_round` and `price`).

```gdscript
# Only offered once the player already runs iron OR bronze.
var ruby := BaseBlock.new(&"yourmod.ruby", [GameData.BlockGroups.MINERALS], 3, 5, [&"iron", &"bronze"])
```

Use it to gate synergy blocks behind their partners — the reward stays hidden until owning it makes sense.

Note that `recipe` is one of several eligibility gates. A block is offered only when **all** of these pass: `max_amount > 0`, `current_round >= unlock_round`, the player can afford `price`, the recipe requirement (above) is met, and — for blocks with more than one group — the player already owns a block from at least one of those groups.

### Name & description

Block texts come from translation keys built from the **upper-cased id**: `BLOCK_<ID>` and `BLOCK_<ID>_DESCRIPTION` (`yourmod.ruby` → `BLOCK_YOURMOD.RUBY`). Register them at runtime in `_ready()`; English is the fallback for languages you don't provide:

```gdscript
var english := Translation.new()
english.locale = "en"
english.add_message("BLOCK_YOURMOD.RUBY", "Ruby")
english.add_message("BLOCK_YOURMOD.RUBY_DESCRIPTION", "Gives [points:+50] when destroyed.")
TranslationServer.add_translation(english)
```

Descriptions support the game's tags: `[points:+50]`, `[multiplier:+10]`, `[group:minerals]`, and colors such as `[yellow]text[white]`.

---

## Changing core blocks

Inside your `blocks_ready` handler, `BlockRegistry.get_block(&"iron")` returns the live core block. Change its fields directly (`price`, `min_amount`, `max_amount`, `recipe`, ...) or extend its effect by wrapping the current one, so other mods' changes are kept:

```gdscript
var stone: BaseBlock = BlockRegistry.get_block(&"stone")
var previous_effect: Callable = stone.get_destroy_effect()

stone.set_destroy_effect(func(ctx: DestroyEffectContext) -> void:
    previous_effect.call(ctx)
    GameManager.add_points(5)
)
```

See [`Stackflow-VanillaTweaks`](Stackflow-VanillaTweaks).

---

## Hooking existing logic

To change behavior of a core method (not just add a block), use **script hooks**. Stackflow's core scripts use `class_name`, so you **must** use `ModLoaderMod.add_hook` (not `install_script_extension`).

```gdscript
func _init() -> void:
    ModLoaderMod.add_hook(
        _on_execute_destroy_effect,
        "res://scripts/placed_block.gd",
        "execute_destroy_effect"
    )


func _on_execute_destroy_effect(chain: ModLoaderHookChain) -> void:
    var block := chain.reference_object as PlacedBlock
    if block and block.type == "yourmod.ruby":
        print("Ruby about to run its destroy effect")

    chain.execute_next()  # <-- REQUIRED: runs the vanilla method + other mods' hooks
```

> **Always call `chain.execute_next()`** or the original method (and every other mod's hook) never runs. `chain.reference_object` is the instance the method was called on.

Common hook targets in Stackflow:

- `res://scripts/placed_block.gd` → `execute_destroy_effect` — every block's clear effect.
- `res://scripts/moving_piece.gd` — piece movement / placement.
- `res://scripts/board.gd` — board-level logic.

---

## Textures

Point a block's `texture_path` at a PNG inside your mod folder:

```gdscript
ruby.texture_path = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/textures/ruby.png"
```

`get_unpacked_dir()` is the `res://mods-unpacked/` path your zip is mounted at. Plain PNGs work as-is (no Godot import step); block sprites are 12×12 pixels. You can also reuse a core sprite (`"res://images/blocks/default/red.png"`) if you don't ship your own art.

---

## Packing & publishing to the Steam Workshop

Everything happens in the in-game **Mods** screen; you never build the zip by hand.

```
mods-source/
└── YourName-YourMod/
    ├── manifest.json
    ├── mod_main.gd
    ├── textures/ruby.png
    ├── preview.png      # optional: Workshop thumbnail (under 1 MB, not packed)
    └── workshop.json    # created on first publish: keeps your item id (not packed)
```

- **Pack** builds the zip GML expects (`mods-unpacked/YourName-YourMod/...` inside) and installs it in `mods/` for local testing.
- **Publish** packs, then uploads to the Workshop. The first publish creates the item (title and description come from `manifest.json`) and opens its page in the Steam overlay: accept the Workshop agreement there if Steam asks, then edit the description, tags and visibility. Later publishes update the same item (via `workshop.json`) and only replace the files; the change note is your `version_number`.
- Players subscribe on the Workshop page; Steam downloads the item and the game loads it on the next launch.

> Remove your local `mods/YourName-YourMod.zip` once you're subscribed to your own Workshop item, or the mod loads twice.

You can still share the zip from `mods/` directly: players drop it into their own `mods/` folder.
