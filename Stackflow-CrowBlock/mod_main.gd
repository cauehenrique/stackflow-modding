extends Node

## Example mod: reacting to other blocks with set_on_block_destroyed.
##
## The observer runs for every placed Crow whenever ANY block is destroyed. The Crow keeps the
## destructions next to it (diagonals included) as charge, and turns it into [multiplier] when it
## is destroyed itself.

const MOD_ID := "Stackflow-CrowBlock"
const CROW_ID := &"stackflow.crow"
const CHARGE_KEY := &"stackflow.crow.charge"


func _ready() -> void:
    _add_translations()

    if BlockRegistry.core_blocks_ready:
        _register_blocks()
    else:
        BlockRegistry.blocks_ready.connect(_register_blocks)


func _register_blocks() -> void:
    if BlockRegistry.has_block(CROW_ID):
        return

    # MONSTER group, 1..2 per piece, 5 credits. Only offered once the deck has a Skeleton or a
    # Slime (recipe = logical OR).
    BaseBlock.new(CROW_ID, [GameData.BlockGroups.MONSTER], 1, 2, [&"skeleton", &"slime"], 5) \
        .set_complexity(2) \
        .set_on_block_destroyed(_on_any_block_destroyed) \
        .set_destroy_effect(_on_crow_destroyed) \
        .texture_path = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/textures/crow.png"


## owner = this Crow, destroyed = the block that just got destroyed (can be any type).
func _on_any_block_destroyed(owner: PlacedBlock, destroyed: PlacedBlock) -> void:
    if owner == destroyed or owner.destroy_animation_requested:
        return

    # The destroyed block already left the board's group, so get_adjacent_blocks() would miss
    # it: compare grid positions instead (diagonals included).
    var offset: Vector2i = (destroyed.grid_position - owner.grid_position).abs()
    if maxi(offset.x, offset.y) > 1:
        return

    owner.custom_variables[CHARGE_KEY] = owner.custom_variables.get(CHARGE_KEY, 0) + 1
    owner.pulse_animation()


func _on_crow_destroyed(ctx: DestroyEffectContext) -> void:
    var charge: int = ctx.block.custom_variables.get(CHARGE_KEY, 0)
    if charge <= 0:
        return

    GameManager.add_multiplier(charge)
    PointNotification.create_and_slide(ctx.block.get_center_position(), PointNotification.RED, charge)
    AudioManager.play(AudioManager.SoundEffects.BLOOP_HIGH, randf_range(0.9, 1.1))


func _add_translations() -> void:
    var english := Translation.new()
    english.locale = "en"
    english.add_message("BLOCK_STACKFLOW.CROW", "Crow")
    english.add_message("BLOCK_STACKFLOW.CROW_DESCRIPTION", "Gains [multiplier:+1] whenever an adjacent block is destroyed.\n\nWhen destroyed, grants the accumulated [multiplier].")
    TranslationServer.add_translation(english)

    var portuguese := Translation.new()
    portuguese.locale = "pt"
    portuguese.add_message("BLOCK_STACKFLOW.CROW", "Corvo")
    portuguese.add_message("BLOCK_STACKFLOW.CROW_DESCRIPTION", "Ganha [multiplier:+1] sempre que um bloco adjacente é destruído.\n\nQuando destruído, concede o [multiplier] acumulado.")
    TranslationServer.add_translation(portuguese)
