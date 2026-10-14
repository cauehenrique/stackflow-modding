extends Node

## Example mod: changing core blocks without replacing them.
##
## blocks_ready fires after every core block exists, so BlockRegistry.get_block returns the live
## BaseBlock instances. Changing their fields or effects changes the game for every run.
## Core descriptions are not changed here: a second Translation for a locale the game already
## ships doesn't reliably take priority, so prefer new blocks when the text must change.

const MOD_ID := "Stackflow-VanillaTweaks"


func _ready() -> void:
    if BlockRegistry.core_blocks_ready:
        _tweak_blocks()
    else:
        BlockRegistry.blocks_ready.connect(_tweak_blocks)


func _tweak_blocks() -> void:
    # 1. Plain metadata: cheaper Iron, more of it per piece.
    var iron: BaseBlock = BlockRegistry.get_block(&"iron")
    iron.price = 1
    iron.max_amount = 6

    # 2. Extend an effect: keep the vanilla Stone effect and add points on top.
    #    get_destroy_effect() returns the current Callable (possibly already wrapped by another
    #    mod), so wrapping chains nicely instead of overwriting other mods' changes.
    var stone: BaseBlock = BlockRegistry.get_block(&"stone")
    var vanilla_stone_effect: Callable = stone.get_destroy_effect()

    stone.set_destroy_effect(func(ctx: DestroyEffectContext) -> void:
        vanilla_stone_effect.call(ctx)
        GameManager.add_points(5)
        PointNotification.create_and_slide(ctx.block.get_center_position(), PointNotification.BLUE, 5, 1.8, PointNotification.DOWN)
    )

    ModLoaderLog.success("VanillaTweaks: Iron and Stone changed", MOD_ID)

