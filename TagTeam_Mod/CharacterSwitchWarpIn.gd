extends EventAbility
class_name CharacterSwitchWarpIn


export  var beam_speed: = 420.0
export  var enable_movement: = true
var descending: = false

# 태그로 들어올 때(교대 투입) 재생되는 캐릭터별 보이스, 2개 중 랜덤 (캐릭터 루트 노드 이름 기준)
const TAG_VOICES := {
	"X": ["res://TagTeam_Mod/Voices/x_tag1.wav", "res://TagTeam_Mod/Voices/x_tag2.wav"],
	"Zero": ["res://TagTeam_Mod/Voices/tag_zero1.wav", "res://TagTeam_Mod/Voices/tag_zero2.wav"],
	"Axl": ["res://TagTeam_Mod/Voices/axl_tag1.wav", "res://TagTeam_Mod/Voices/axl_tag2.wav"]
}
const TAG_VOICE_VOLUME_DB := -4.0
var _tag_voice_streams: Array = []
var _tag_rng := RandomNumberGenerator.new()
onready var animatedSprite = get_parent().get_node("animatedSprite")
onready var beam_sound = get_node("audioStreamPlayer")


func _ready() -> void :
	animatedSprite.connect("animation_finished", self, "on_animation_finished")
	Event.listen("character_switch_end", self, "on_character_switch_end")
	_tag_rng.randomize()
	for path in TAG_VOICES.get(character.name, []):
		var stream = load(path)
		if stream != null:
			_tag_voice_streams.append(stream)

func on_character_switch_end() -> void:
	EndAbility()
	character.interrupt_all_moves()
	
func _Setup():
	character.deactivate()
	descending = true
	animatedSprite.position.y = position.y - 160
	beam_sound.play()
	play_tag_voice()

func play_tag_voice() -> void:
	if _tag_voice_streams.empty():
		return
	var player := AudioStreamPlayer.new()
	player.pause_mode = Node.PAUSE_MODE_PROCESS   # 교대 중 정지 상태에서도 재생
	player.stream = _tag_voice_streams[_tag_rng.randi() % _tag_voice_streams.size()]
	player.bus = "SFX"
	player.volume_db = TAG_VOICE_VOLUME_DB
	add_child(player)
	player.connect("finished", player, "queue_free")
	player.play()

func _Update(_delta):
	if descending:
		if animatedSprite.global_position.y < character.global_position.y - 8:
			animatedSprite.global_position.y += beam_speed * _delta
		elif animatedSprite.global_position.y >= character.global_position.y:
			play_animation_once("beam_in")
			descending = false
		else:
			animatedSprite.position.y = - 4
			play_animation_once("beam_in")
			descending = false

func on_animation_finished():
	if executing:
		if character.get_animation() == "beam_in":
			CharacterManager.try_character_switch_end()

func _Interrupt():
	if enable_movement:
		character.activate()
		character.check_if_should_set_alpha_to_1()

func _EndCondition() -> bool:
	return false

func is_high_priority() -> bool:
	return true

func is_colliding_with_wall(wallcheck_distance: = 8, vertical_correction: = 8) -> int:
	if raycast(Vector2(global_position.x + wallcheck_distance, global_position.y + vertical_correction)):
		return 1
	elif raycast(Vector2(global_position.x - wallcheck_distance, global_position.y + vertical_correction)):
		return - 1
	
	return 0
	
func at_correct_height() -> bool:
	var ground_y = get_ground_height()
	if global_position.y + 16 <= ground_y:
		return false
	else:
		character.set_y(ground_y - 15)
		return true

func get_ground_height() -> float:
	var intersection = (raycast(Vector2(global_position.x, global_position.y + 1000)).position.y)
	return intersection

func raycast(target_position: Vector2) -> Dictionary:
	var space_state = get_world_2d().direct_space_state
	return space_state.intersect_ray(global_position, target_position, [self], character.collision_mask)
