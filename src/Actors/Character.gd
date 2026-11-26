extends AbilityUser
class_name Character

var listening_to_inputs := true
var emitted_land := false
var last_time_dashed := 0.0
var last_wall_at_position: Vector2
var full_alpha := true
var set_alert := false

onready var wallcheck_left := $_raycasts.get_node("Wallcheck Left")
onready var wallcheck_left2 := $_raycasts.get_node("Wallcheck Left2")
onready var wallcheck_left3 := $_raycasts.get_node("Wallcheck Left3")
onready var wallcheck_right := $_raycasts.get_node("Wallcheck Right")
onready var wallcheck_right2 := $_raycasts.get_node("Wallcheck Right2")
onready var wallcheck_right3 := $_raycasts.get_node("Wallcheck Right3")
onready var cast_left = [wallcheck_left, wallcheck_left2, wallcheck_left3]
onready var cast_right = [wallcheck_right, wallcheck_right2, wallcheck_right3]

onready var walljumpcast_left := $_raycasts.get_node("WallJumpCast Left")
onready var walljumpcast_left2 := $_raycasts.get_node("WallJumpCast Left2")
onready var walljumpcast_left3 := $_raycasts.get_node("WallJumpCast Left3")
onready var walljumpcast_right := $_raycasts.get_node("WallJumpCast Right")
onready var walljumpcast_right2 := $_raycasts.get_node("WallJumpCast Right2")
onready var walljumpcast_right3 := $_raycasts.get_node("WallJumpCast Right3")
onready var jumpcast_left = [walljumpcast_left, walljumpcast_left2, walljumpcast_left3]
onready var jumpcast_right = [walljumpcast_right, walljumpcast_right2, walljumpcast_right3]
onready var low_jumpcasts = [walljumpcast_left3,walljumpcast_right3]

onready var collisor := $"Enemy Collision Detector".get_node("CollisionShape2D")

onready var shot_position := get_node("Shot Position")

var colors = []

var debug_position_y := 0.0

signal headbump
signal land
signal cutscene_deactivate
signal ride(prop)
signal eject(prop)
signal force_movement
signal stop_forced_movement(forcer)
signal melee_hit (enemy)
 
signal jump

func _ready() -> void:
	connect_cutscene_events() 

func connect_cutscene_events() -> void:
	Event.listen("end_cutscene_start",self,"deactivate")
	Event.listen("cutscene_start",self,"stop_listening_to_inputs")
	Event.listen("stage_rotate",self,"stop_listening_to_inputs")
	Event.listen("cutscene_over",self,"cutscene_activate")

func cutscene_activate() -> void:
	if not is_executing("Ride"):
		activate()

func spike_touch():
	if not is_invulnerable():
		Log("Death by Spikes")
		emit_signal("zero_health")

func ride(ride : Node):
	emit_signal("ride", ride)

func eject(ride : Node):
	emit_signal("eject", ride)

func force_movement(_forcer = null):
	emit_signal("force_movement")
	
func stop_forced_movement(forcer = null):
	emit_signal("stop_forced_movement", forcer)

func activate():
	start_listening_to_inputs()
	Log("Active")

func deactivate():
	stop_listening_to_inputs()
	stop_shot()
	Log ("not active")

func stop_shot():
	for ability in executing_moves:
		if ability.name == "Shot":
			ability.EndAbility()

func make_invisible():
	Log ("invisible")
	animatedSprite.visible = false

func make_visible():
	Log ("visible")
	animatedSprite.visible = true

func stop_listening_to_inputs():
	Log ("not listening to inputs")
	listening_to_inputs = false

func cutscene_deactivate() -> void:
	stop_listening_to_inputs()
	emit_signal("cutscene_deactivate")
	if GameManager.player.ride:
		GameManager.player.ride.stop_listening_to_inputs()

func start_listening_to_inputs():
	if GameManager.get_state() != "Cutscene":
		Log ("listening to inputs")
		listening_to_inputs = true

func get_executing_moves() -> void:
	for move in moveset:
		if move.CheckForPressed():
			try_execution(move)

func _process(_delta: float) -> void:
	update_facing_direction()

func _physics_process(delta: float) -> void:
	check_if_should_set_alpha_to_1()
	check_for_headbump()
	check_for_land(delta)
	check_for_low_health()
	check_for_dash()

func check_for_dash():
	if get_action_just_pressed("dash"):
		Event.emit_signal("input_dash")

func check_if_should_set_alpha_to_1():
	if invulnerability < 0 and not has_invulnerability_from_skills() and not full_alpha:
		remove_invulnerability_shader()
		full_alpha = true

func has_invulnerability_from_skills() -> bool:
	return toggleable_invulnerabilities.size() > 0

func check_for_low_health():
	if has_health():
		if is_low_health() and not set_alert:
			animatedSprite.material.set_shader_param("Alert", 1)
			set_alert = true
		elif not is_low_health() and set_alert:
			animatedSprite.material.set_shader_param("Alert", 0)
			set_alert = false

func is_invulnerable() -> bool:
	if not active:
		return true
	else:
		return .is_invulnerable() 

func add_invulnerability(ability_name):
	if not ability_name in toggleable_invulnerabilities:
		toggleable_invulnerabilities.append(ability_name) 
		apply_invulnerability_shader()
		print(">>>>>>>> SHADER " + str(ability_name))

func remove_invulnerability(ability_name):
	toggleable_invulnerabilities.erase(ability_name) 
	if not is_invulnerable():
		remove_invulnerability_shader()

func apply_invulnerability_shader():
		animatedSprite.material.set_shader_param("Alpha", 0.5)
		full_alpha = false

func remove_invulnerability_shader():
		animatedSprite.material.set_shader_param("Alpha", 1)
		full_alpha = true

func check_for_headbump():
	if is_on_ceiling():
		emit_signal("headbump")

func check_for_land(delta: float):
	if is_on_floor():
		if not emitted_land:
			emitted_land = true
			time_since_on_floor = 0
			emit_signal("land")
	else:
		time_since_on_floor = time_since_on_floor + delta
		if emitted_land:
			emitted_land = false

func is_colliding_with_wall() -> int:
	for cast in cast_right:
		if check_for_normal(cast,-1):
			return 1
	for cast in cast_left:
		if check_for_normal(cast,1):
			return -1
	return 0

func is_colliding_with_wall_except_feet() -> int:
	var right = [wallcheck_right,wallcheck_right2]
	var left = [wallcheck_left,wallcheck_left2]
	for cast in right:
		if check_for_normal(cast,-1):
			return 1
	for cast in left:
		if check_for_normal(cast,1):
			return -1
	return 0

func is_colliding_with_both_walls() -> bool:
	var collision = 0
	for cast in cast_right:
		if check_for_normal(cast,-1):
			collision += 1
	for cast in cast_left:
		if check_for_normal(cast,1):
			collision +=1
	return collision == 2

func is_in_reach_for_walljump() -> int:
	for cast in jumpcast_right:
		if check_for_normal(cast,-1):
			return 1
	for cast in jumpcast_left:
		if check_for_normal(cast,1):
			return -1
	return 0

func check_for_normal(cast, normal: int, angle_range := 0.25) -> bool:
	return cast.is_colliding() and \
	cast.get_collision_normal().x > normal - angle_range and \
	cast.get_collision_normal().x < normal + angle_range

func get_pressed_axis() -> int:
	var axis = 0
	if get_action_pressed("move_left"):
		axis = axis -1
	if get_action_pressed("move_right"):
		axis = axis +1
	return axis

func get_just_pressed_axis() -> int:
	var axis = 0
	if has_just_pressed_left():
		axis = axis -1
	if has_just_pressed_right():
		axis = axis +1
	return axis

func has_just_pressed_left() -> bool:
	return get_action_just_pressed("move_left")
	
func has_just_pressed_right() -> bool:
	return get_action_just_pressed("move_right")

func set_animation_layer (layer):
	if animatedSprite.frames != layer:
		animatedSprite.frames = layer
		
func get_animation_layer () -> String:
	return animatedSprite.frames

func send_debug_info() -> String:
	var text := ""
	#text += print_hp()
	text += print_position()
	text += print_speed()
	text += print_states()
	
	return text

func print_hp() -> String:
	var text := "HP:"
	for unit in current_health:
		text += "l"
	return text
	
func print_position() -> String:
	var x_pos = stepify(position.x, 0.01)
	var y_pos = stepify(position.y, 0.01)
	return "X:" + str(x_pos) + "\nY:" + str(y_pos)
	
func print_speed() -> String:
	var x_speed = stepify(final_velocity.x, 0.1)
	var y_speed = stepify(final_velocity.y, 0.1)
	return "\nH Spd:" + str(x_speed) + "\nV Spd:" + str(y_speed)
	
func print_states() -> String:
	var text := ""
	var total_states := ""
	for state in moveset:
		if state.executing:
			text += state.name.left(1)
			if total_states.length() > 0:
				total_states += ", "
			total_states += state.name
		else:
			text += "."
	var final_text := "\nState: " + str(total_states) \
		+ "\n" + text
	return final_text

func get_action_just_pressed(action) -> bool:
	if listening_to_inputs:
		return Input.is_action_just_pressed(action)
	return false

func get_action_pressed(action) -> bool:
	if listening_to_inputs:
		return Input.is_action_pressed(action)
	return false

func get_action_strength(action) -> float:
	if listening_to_inputs:
		return Input.get_action_strength(action)
	return 0.0

func get_action_just_released(action) -> bool:
	if listening_to_inputs:
		return Input.is_action_just_released(action)
	return false

func hit(_body : Node) -> void:
	emit_signal("melee_hit", _body)


# ---- 자동 입력 보조 (제로 AUTO ATTACK / X AUTO CHARGE) ----
# 아래 두 함수는 CharacterManager._physics_process 에서 호출된다.
# (autoload 가 플레이어보다 먼저 처리되므로, 넣어 준 입력을 같은 프레임의 능력들이 확실히 인식한다)
const AUTO_ATTACK_RANGE_X: float = 75.0
const AUTO_ATTACK_RANGE_UP: float = 45.0
const AUTO_ATTACK_RANGE_DOWN: float = 25.0
const AUTO_ATTACK_INTERVAL: float = 0.12
var _auto_attack_pressed: bool = false
var _auto_attack_cd: float = 0.0
var auto_charge_block_basic: float = 0.0

func is_zero_player() -> bool:
	return get_node_or_null("SaberCharge") != null

func check_zero_auto_attack(delta: float) -> void:
	if _auto_attack_pressed:
		Input.action_release("fire")
		_auto_attack_pressed = false
	if not is_zero_player():
		return
	if not CharacterManager.zero_auto_attack:
		return
	if not listening_to_inputs or not has_health():
		return
	if Input.is_action_pressed("fire"):
		return
	_auto_attack_cd -= delta
	if _auto_attack_cd > 0.0:
		return
	if has_enemy_in_attack_range():
		Input.action_press("fire")
		_auto_attack_pressed = true
		_auto_attack_cd = AUTO_ATTACK_INTERVAL

func has_enemy_in_attack_range() -> bool:
	var dir = get_facing_direction()
	for node in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(node):
			continue
		var body = node
		if node is EnemyDamage:
			if not node.active:
				continue
			body = node.character
		if not is_instance_valid(body) or not (body is Node2D):
			continue
		if body.has_method("has_health") and not body.has_health():
			continue
		var diff = body.global_position - global_position
		if diff.x * dir < -8.0 or abs(diff.x) > AUTO_ATTACK_RANGE_X:
			continue
		if diff.y < -AUTO_ATTACK_RANGE_UP or diff.y > AUTO_ATTACK_RANGE_DOWN:
			continue
		return true
	return false

func check_x_auto_charge(delta: float) -> void:
	if auto_charge_block_basic > 0.0:
		auto_charge_block_basic -= delta
	if not CharacterManager.auto_charge or CharacterManager.ultimate_buster or CharacterManager.weaponget:
		return
	if is_zero_player() or not has_node("Charge"):
		return
	if not listening_to_inputs or is_executing("Ride"):
		return
	if Input.is_action_pressed("fire"):
		# 공격 버튼을 누르는 동안은 자동 차지를 풀어서 모아 둔 차지샷이 나가게 한다
		if Input.is_action_just_pressed("fire"):
			var charge = get_node("Charge")
			if charge.has_method("get_charge_level") and charge.get_charge_level() >= 1:
				auto_charge_block_basic = 0.2
		if Input.is_action_pressed("auto_charge"):
			Input.action_release("auto_charge")
	elif not Input.is_action_pressed("auto_charge"):
		Input.action_press("auto_charge")
