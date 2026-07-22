# Modding Stackflow

Stackflow supports mods through the [Godot Mod Loader (GML)](https://wiki.godotmodding.com/#mod-developer). This guide shows you how to build a mod that adds **new blocks** and **hooks into existing game logic** — no core files edited.

If you've never used GML before, read the official [Mod Developer wiki](https://wiki.godotmodding.com/#mod-developer) first. This document covers the parts that are **specific to Stackflow**.

---

## Table of contents

1. [How mods load](#how-mods-load)
2. [Mod folder structure](#mod-folder-structure)
3. [The manifest](#the-manifest)
4. [Your mod entry script](#your-mod-entry-script)
5. [Adding a new block](#adding-a-new-block)
6. [Hooking existing logic](#hooking-existing-logic)
7. [Textures](#textures)
8. [Packing & distributing](#packing--distributing)
9. [Full working example](#full-working-example)

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

A mod is a folder inside `mods-unpacked/` during development (GML unpacks packed mods here at runtime):

```
mods-unpacked/
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
            "compatible_game_version": ["1.1.0"],
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
| `recipe` | `Array[StringName]` | Crafting recipe (empty = always available). |
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

`get_unpacked_dir()` resolves to wherever GML unpacked your mod, so the path works both in dev and from a packed mod. You can also reuse a core sprite (`"res://images/blocks/default/red.png"`) if you don't ship your own art.

---

## Packing & distributing

1. Develop inside `mods-unpacked/YourName-YourMod/`.
2. Pack the folder into a `.zip` following the [GML export guide](https://wiki.godotmodding.com/guides/modding/distributing_mods/).
3. Ship the zip; players drop it in the game's `mods/` folder.

---

## Full working example

The repo ships a reference mod at `mods-unpacked/Stackflow-TestBlock/` that proves both mechanisms — a new `stackflow.ruby` block and a `PlacedBlock` hook. Read `mod_main.gd` there for a complete, commented example.
