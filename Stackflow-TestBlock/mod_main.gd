extends Node

## Mod de teste da integracao GodotModLoader no Stackflow.
##
## Prova dois mecanismos:
##   1. Registro de bloco novo via a API publica BaseBlock + sinal BlockRegistry.blocks_ready
##      (o padrao recomendado -- espera o core popular antes de registrar/sobrescrever).
##   2. Um script hook em PlacedBlock.execute_destroy_effect (PlacedBlock tem class_name,
##      entao usa add_hook, nao install_script_extension).
##
## O bloco "stackflow.ruby" e desenhado para SEMPRE aparecer no roll de teste:
## unlock_round 0, price 0, recipe vazia, 1 grupo -> passa todos os gates de elegibilidade.

const MOD_ID := "Stackflow-TestBlock"
const RUBY_ID := &"stackflow.ruby"


func _init() -> void:
	ModLoaderLog.info("TestBlock: _init", MOD_ID)

	# Hook em PlacedBlock (global class -> hook obrigatorio). Adiciona um log toda vez
	# que qualquer bloco executa seu efeito de destruicao, provando que o preprocessor
	# de hooks funciona neste build.
	ModLoaderMod.add_hook(_on_execute_destroy_effect, "res://scripts/placed_block.gd", "execute_destroy_effect")


func _ready() -> void:
	# blocks_ready garante que os blocos do core ja existem. Se o CoreBlocks ja emitiu
	# (mod carregado tarde), registra imediatamente; senao aguarda o sinal.
	if BlockRegistry.core_blocks_ready:
		_register_blocks()
	else:
		BlockRegistry.blocks_ready.connect(_register_blocks)


func _register_blocks() -> void:
	# Nao registrar duas vezes (blocks_ready so emite uma vez, mas guarda por seguranca).
	if BlockRegistry.has_block(RUBY_ID):
		return

	# Grupo MINERALS para pegar sinergia com iron/bronze/diamond do core.
	# min/max 3..5, price 0, unlock 0 -> elegivel desde o primeiro roll.
	var ruby := BaseBlock.new(RUBY_ID, [GameData.BlockGroups.MINERALS], 3, 5)

	# Textura propria do mod, resolvida pela pasta descompactada pelo ModLoader.
	# Funciona tanto em dev (mods-unpacked) quanto a partir de um mod empacotado.
	ruby.texture_path = ModLoaderMod.get_unpacked_dir() + MOD_ID + "/textures/ruby.png"

	# Efeito proprio ao ser destruido por line clear: da pontos.
	ruby.set_destroy_effect(func(ctx: DestroyEffectContext) -> void:
		GameManager.add_points(50)
		PointNotification.create_and_slide(ctx.block.get_center_position(), PointNotification.BLUE, 50)
		ModLoaderLog.info("Ruby destruido -> +50 pontos", MOD_ID)
	)

	ModLoaderLog.success("TestBlock: bloco '%s' registrado. Total de blocos: %s" % [RUBY_ID, BlockRegistry.all_ids().size()], MOD_ID)


## Hook de PlacedBlock.execute_destroy_effect. Recebe o chain como primeiro argumento;
## precisa chamar chain.execute_next() para o efeito vanilla rodar.
func _on_execute_destroy_effect(chain: ModLoaderHookChain) -> void:
	var block := chain.reference_object as PlacedBlock
	if block and block.type == String(RUBY_ID):
		ModLoaderLog.info("Hook: Ruby prestes a executar efeito de destruicao", MOD_ID)
	chain.execute_next()
