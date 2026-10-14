extends Node

## Example mod: registers a new block (Ruby) and hooks a core method.
##
## Shows the two extension mechanisms:
##   1. A new block through the public BaseBlock API, registered after BlockRegistry.blocks_ready
##      (the core blocks already exist at that point, so mods can also override them).
##   2. A script hook on PlacedBlock.execute_destroy_effect. PlacedBlock has a class_name,
##      so it needs add_hook, not install_script_extension.
##
## The Ruby always shows up in the block rolls: unlock_round 0, price 0, empty recipe and a
## single group pass every eligibility gate.

const MOD_ID := "Stackflow-TestBlock"
const RUBY_ID := &"stackflow.ruby"


func _init() -> void:
    ModLoaderLog.info("TestBlock: _init", MOD_ID)

    # Hooks must be installed before the hooked script runs, hence _init.
    ModLoaderMod.add_hook(_on_execute_destroy_effect, "res://scripts/placed_block.gd", "execute_destroy_effect")


func _ready() -> void:
    _add_translations()

    # If CoreBlocks already finished (mod loaded late) register now; otherwise wait for it.
    if BlockRegistry.core_blocks_ready:
        _register_blocks()
    else:
        BlockRegistry.blocks_ready.connect(_register_blocks)


func _register_blocks() -> void:
    if BlockRegistry.has_block(RUBY_ID):
        return

    # MINERALS group: synergy with the core iron/bronze/diamond. 3..5 Rubies per piece.
    var ruby := BaseBlock.new(RUBY_ID, [GameData.BlockGroups.MINERALS], 3, 5)

    # A plain PNG inside the mod folder: no Godot import needed.
    ruby.texture_path = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/textures/ruby.png"

    ruby.set_destroy_effect(func(ctx: DestroyEffectContext) -> void:
        GameManager.add_points(50)
        PointNotification.create_and_slide(ctx.block.get_center_position(), PointNotification.BLUE, 50)
    )

    ModLoaderLog.success("TestBlock: registered '%s'. Total blocks: %s" % [RUBY_ID, BlockRegistry.all_ids().size()], MOD_ID)


## Block name and description use the keys BLOCK_<ID> and BLOCK_<ID>_DESCRIPTION, with the id
## upper-cased. English is the fallback locale; add more Translation objects for other languages.
func _add_translations() -> void:
    var english := Translation.new()
    english.locale = "en"
    english.add_message("BLOCK_STACKFLOW.RUBY", "Ruby")
    english.add_message("BLOCK_STACKFLOW.RUBY_DESCRIPTION", "Gives [points:+50] when destroyed.")
    TranslationServer.add_translation(english)

    var portuguese := Translation.new()
    portuguese.locale = "pt"
    portuguese.add_message("BLOCK_STACKFLOW.RUBY", "Rubi")
    portuguese.add_message("BLOCK_STACKFLOW.RUBY_DESCRIPTION", "Dá [points:+50] quando destruído.")
    TranslationServer.add_translation(portuguese)


## Hook on PlacedBlock.execute_destroy_effect. Gets the chain as its first argument and must call
## chain.execute_next() so the vanilla method (and other mods' hooks) still run.
func _on_execute_destroy_effect(chain: ModLoaderHookChain) -> void:
    var block := chain.reference_object as PlacedBlock
    if block and block.type == String(RUBY_ID):
        ModLoaderLog.info("Hook: Ruby is about to run its destroy effect", MOD_ID)
    chain.execute_next()
