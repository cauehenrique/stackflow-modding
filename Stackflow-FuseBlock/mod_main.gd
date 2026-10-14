extends Node

## Example mod: per-instance state with set_on_place.
##
## Every placed Fuse starts a Timer that adds 1 charge per second (paused while the game is busy
## scoring). When the Fuse is cleared, it gives [points] equal to 10x its charge, so leaving it on
## the board longer pays more.

const MOD_ID := "Stackflow-FuseBlock"
const FUSE_ID := &"stackflow.fuse"
## Namespaced key in PlacedBlock.custom_variables, so it can't clash with core or other mods.
const CHARGE_KEY := &"stackflow.fuse.charge"
const POINTS_PER_CHARGE := 10


func _ready() -> void:
    _add_translations()

    if BlockRegistry.core_blocks_ready:
        _register_blocks()
    else:
        BlockRegistry.blocks_ready.connect(_register_blocks)


func _register_blocks() -> void:
    if BlockRegistry.has_block(FUSE_ID):
        return

    # EXPLOSIVES group, 2..3 per piece, costs 3 credits, offered from round 2.
    BaseBlock.new(FUSE_ID, [GameData.BlockGroups.EXPLOSIVES], 2, 3, [], 3, 2) \
        .set_complexity(2) \
        .set_on_place(_on_fuse_placed) \
        .set_destroy_effect(_on_fuse_destroyed) \
        .texture_path = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/textures/fuse.png"


## Runs once per placed Fuse. Anything per-instance (Timers, counters) belongs here.
func _on_fuse_placed(block: PlacedBlock) -> void:
    var timer := Timer.new()
    # The Timer is a child of the block, so it is freed with it.
    block.add_child(timer)
    timer.wait_time = 1.0 / GameManager.timescale

    timer.timeout.connect(func() -> void:
        if block.destroy_animation_requested:
            timer.stop()
            return

        # Don't tick while a line clear is being scored.
        if GameManager.is_game_busy():
            return

        block.custom_variables[CHARGE_KEY] = block.custom_variables.get(CHARGE_KEY, 0) + 1
        block.pulse_animation(false)
        AudioManager.play(AudioManager.SoundEffects.SINGLE_CLICK_3, randf_range(1.4, 1.6))
    )

    timer.start()


func _on_fuse_destroyed(ctx: DestroyEffectContext) -> void:
    var points: int = ctx.block.custom_variables.get(CHARGE_KEY, 0) * POINTS_PER_CHARGE
    if points <= 0:
        return

    GameManager.add_points(points)
    PointNotification.create_and_slide(ctx.block.get_center_position(), PointNotification.BLUE, points)


func _add_translations() -> void:
    var english := Translation.new()
    english.locale = "en"
    english.add_message("BLOCK_STACKFLOW.FUSE", "Fuse")
    english.add_message("BLOCK_STACKFLOW.FUSE_DESCRIPTION", "Charges every [yellow]second[white] on the board. When destroyed, gives [points:+10] per charge.")
    TranslationServer.add_translation(english)

    var portuguese := Translation.new()
    portuguese.locale = "pt"
    portuguese.add_message("BLOCK_STACKFLOW.FUSE", "Pavio")
    portuguese.add_message("BLOCK_STACKFLOW.FUSE_DESCRIPTION", "Carrega a cada [yellow]segundo[white] no tabuleiro. Quando destruído, dá [points:+10] por carga.")
    TranslationServer.add_translation(portuguese)
