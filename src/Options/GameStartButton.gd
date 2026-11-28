extends X8TextureButton

export  var pick_sound: NodePath
onready var label: Label = $text

var all_modes: PoolIntArray = [ - 1, 0, 1, 2, 3]
var modes: PoolIntArray = []
var labels: Dictionary = {
	- 1: "GAME_START_ROOKIE", 
		0: "GAME_START", 
		1: "GAME_START_HARD", 
		2: "GAME_START_INSANITY", 
		3: "GAME_START_NINJA"
}

func _ready() -> void :
	build_mode_list()
	update_game_mode(CharacterManager.game_mode)
	_android_make_arrows()
	Event.connect("translation_updated",self,"update_display")

func update_display():
	label.text = tr(labels.get(CharacterManager.game_mode, "GAME_START"))

func _process(_delta: float) -> void :
	_android_update_arrows()
	if not has_focus() or CharacterManager.game_mode_set:
		return
	
	var current_index: int = modes.find(CharacterManager.game_mode)
	if Input.is_action_just_pressed("move_left") and current_index > 0:
		update_game_mode(modes[current_index - 1])
		_on_focus_entered()
	elif Input.is_action_just_pressed("move_right") and current_index < modes.size() - 1:
		update_game_mode(modes[current_index + 1])
		_on_focus_entered()

func build_mode_list() -> void :
	modes = [ - 1, 0, 1]
	if CharacterManager.beaten_hard:
		modes.append(2)
	if CharacterManager.beaten_insanity:
		modes.append(3)

func update_game_mode(mode: int) -> void :
	CharacterManager.game_mode = mode
	if CharacterManager.game_mode == - 1:
		idle_color = Color("#329632")
		focus_color = Color("#8cff8c")
	elif CharacterManager.game_mode == 0:
		idle_color = Color("#68caff")
		focus_color = Color("#fbffaf")
	elif CharacterManager.game_mode == 1:
		idle_color = Color("#960000")
		focus_color = Color("#ff4b4b")
	elif CharacterManager.game_mode == 2:
		idle_color = Color("#771313")
		focus_color = Color("#ff7200")
	elif CharacterManager.game_mode == 3:
		idle_color = Color("#832b7f")
		focus_color = Color("#e090f2")
		
	label.text = tr(labels.get(CharacterManager.game_mode, "GAME_START"))
	CharacterManager.update_game_mode()
	_on_focus_exited()

func on_press() -> void :
	CharacterManager.game_mode_set = true
	get_node(pick_sound).play()
	Event.emit_signal("fadeout_startmenu")
	strong_flash()
	menu.lock_buttons()
	menu.fader.SoftFadeOut()
	yield(menu.fader, "finished")
	
	go_to_next_scene()

func go_to_next_scene() -> void :
	if already_finished_noahs_park():
		GameManager.call_deferred("go_to_stage_select")
	else:
		get_tree().change_scene("res://System/Screens/CharacterSelection/Character_Selection.tscn")

func already_finished_noahs_park() -> bool:
	return "finished_intro" in GameManager.collectibles


# Android-PORT: 터치 난이도 선택 (iOS 판의 < > 화살표와 같은 동작)
# 이 버튼은 왼쪽/오른쪽 키로 난이도를 고르는데 터치로는 방법이 없어서, 글자 양옆에 < > 를 붙이고 탭하면 난이도를 바꾼다.
var android_arrows: Array = []
var _android_last_step: int = 0
# 화살표를 누르는 영역 폭과, 글자 끝에서 화살표 중심까지의 거리
const ANDROID_ARROW_W := 28.0
const ANDROID_ARROW_PAD := 10.0


func _android_make_arrows() -> void:
	if OS.get_name() != "Android":
		return
	for i in range(2):
		var a = Label.new()
		a.text = ""
		a.mouse_filter = Control.MOUSE_FILTER_STOP
		a.rect_size = Vector2(ANDROID_ARROW_W, max(rect_size.y, 16.0))
		a.set_meta("dir", -1 if i == 0 else 1)
		a.connect("draw", self, "_android_draw_arrow", [a])
		a.connect("gui_input", self, "_android_arrow_input", [a])
		add_child(a)
		android_arrows.append(a)
	_android_place_arrows()


# 지금 표시 중인 난이도 글자의 폭에 맞춰 화살표를 글자 양옆에 붙인다
func _android_place_arrows() -> void:
	var half = 24.0
	var font = label.get_font("font")
	if font != null:
		half = font.get_string_size(label.text).x * 0.5
	var cx = rect_size.x * 0.5
	for a in android_arrows:
		var d = int(a.get_meta("dir"))
		a.rect_size = Vector2(ANDROID_ARROW_W, max(rect_size.y, 16.0))
		a.rect_position = Vector2(cx + d * (half + ANDROID_ARROW_PAD) - ANDROID_ARROW_W * 0.5, 0.0)


# 글자 대신 직접 삼각형으로 그림 (폰트에 < > 가 없어도 항상 보이게)
func _android_draw_arrow(a: Control) -> void:
	var d = int(a.get_meta("dir"))
	var c = a.rect_size * 0.5
	var h = 5.0
	var w = 4.0
	var pts = PoolVector2Array([
		c + Vector2(d * w, 0.0),
		c + Vector2(-d * w, -h),
		c + Vector2(-d * w, h)])
	a.draw_colored_polygon(pts, Color(1, 1, 1, 1))


func _android_update_arrows() -> void:
	if android_arrows.empty():
		return
	_android_place_arrows()
	var show = modes.size() > 1
	var can = show and not CharacterManager.game_mode_set
	var idx = modes.find(CharacterManager.game_mode)
	for a in android_arrows:
		a.visible = show
		if show:
			var d = int(a.get_meta("dir"))
			var ok = can and ((d < 0 and idx > 0) or (d > 0 and idx < modes.size() - 1))
			a.update()
			a.modulate = Color(1, 1, 1, 1.0 if ok else 0.25)


# 탭(에뮬레이트된 마우스 클릭 또는 터치) 처리. 같은 탭이 두 이벤트로 들어와도 한 번만 반응하도록 짧게 막아 둔다
func _android_arrow_input(event: InputEvent, a: Control) -> void:
	var pressed = false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if not pressed:
		return
	a.accept_event()
	var now = OS.get_ticks_msec()
	if now - _android_last_step < 200:
		return
	_android_last_step = now
	android_step_mode(int(a.get_meta("dir")))


func android_step_mode(d: int) -> void:
	if CharacterManager.game_mode_set:
		return
	var ni = modes.find(CharacterManager.game_mode) + d
	if ni < 0 or ni >= modes.size():
		return
	update_game_mode(modes[ni])
	_on_focus_entered()
