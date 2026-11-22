extends Node
# 이펙트 모드 (옵션 "파티클 효과"): 0 = GPU 파티클(원본), 1 = CPU 파티클
# 일부 기기(GLES2 로 떨어지거나 GPU 드라이버 문제)에서는 GPU 파티클(Particles2D)이 안 보이므로,
# 같은 설정의 CPUParticles2D 를 대신 그려 준다.
# - 적/보스 폭파(EnemyDeath, BossDeath, Remains), X 차지(Charge.gd)는 스크립트에서 직접 FxMode.emit 을 부른다.
# - 그 밖의 모든 Particles2D(부서지는 상자, 문 폭파, 총알 맞는 효과 등)는 아래 '브리지'가 자동 처리한다:
#   CPU 모드일 때 Particles2D.emitting 이 켜지는 순간 같은 설정의 CPU 파티클(자식 노드)을 같이 켜 준다.
#   (GLES2 에서는 Particles2D.emitting 을 읽을 수 없어서 브리지는 꺼진다)
# - 기본값: 옵션을 아직 안 바꿨으면 GLES2 에서는 CPU, 그 외에는 GPU

var tracked: Dictionary = {}   # 인스턴스 id -> [노드, 직전 emitting]
var reliable: bool = true      # Particles2D.emitting 을 믿고 읽을 수 있는 드라이버인지
var _was_cpu: bool = false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	var probe = Particles2D.new()
	probe.emitting = false
	reliable = not probe.emitting
	probe.free()
	get_tree().connect("node_added", self, "_on_node_added")


func _on_node_added(n) -> void:
	# CPU 모드이고 emitting 을 읽을 수 있을 때만 추적한다 (그 외에는 목록이 쌓이기만 하므로)
	if reliable and n is Particles2D and use_cpu():
		tracked[n.get_instance_id()] = [n, false]


func _process(_delta: float) -> void:
	var cpu = use_cpu()
	if cpu != _was_cpu:
		_was_cpu = cpu
		if not cpu:
			_restore_all()
			tracked.clear()
	if not cpu or not reliable:
		return
	var dead = []
	for id in tracked:
		var rec = tracked[id]
		var n = rec[0]
		if not is_instance_valid(n) or not n.is_inside_tree():
			dead.append(id)
			continue
		var e: bool = n.emitting
		if e == rec[1]:
			continue
		rec[1] = e
		if e:
			_bridge_start(n)
		else:
			var t = _existing_twin(n)
			if t != null:
				t.emitting = false
	for id in dead:
		tracked.erase(id)


func _bridge_start(n) -> void:
	if n.one_shot and n.amount <= 1 and n.lifetime <= 0.25:
		return  # ParticleCache 가 셰이더 미리 컴파일용으로 만든 더미
	var t = get_twin(n, true)
	if t == null:
		return
	if not n.has_meta("fx_old_sm"):
		n.set_meta("fx_old_sm", n.self_modulate)
		n.self_modulate = Color(1, 1, 1, 0)  # GPU 쪽은 투명하게 (겹쳐 그려지지 않게)
	t.restart()


# CPU 모드를 끄면 숨겨 둔 GPU 파티클을 되돌리고 CPU 파티클은 멈춘다
func _restore_all() -> void:
	for id in tracked:
		var n = tracked[id][0]
		if is_instance_valid(n):
			if n.has_meta("fx_old_sm"):
				n.self_modulate = n.get_meta("fx_old_sm")
				n.remove_meta("fx_old_sm")
			var t = _existing_twin(n)
			if t != null:
				t.emitting = false


func get_mode() -> int:
	if Configurations.exists("EffectMode"):
		return int(Configurations.get("EffectMode"))
	if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES2:
		return 1
	return 0


func use_cpu() -> bool:
	return get_mode() == 1


# gpu(Particles2D) 와 같은 설정의 CPU 파티클을 gpu 의 자식으로 만들어 돌려준다. 변환 못 하면 null.
func get_twin(gpu, refresh: bool = false):
	if gpu == null or not is_instance_valid(gpu):
		return null
	if gpu.has_meta("cpu_twin"):
		var old = gpu.get_meta("cpu_twin")
		if is_instance_valid(old):
			if refresh:
				old.convert_from_particles(gpu)  # 스크립트가 바꾼 amount/lifetime 등을 다시 반영
				old.material = gpu.material
				old.use_parent_material = gpu.use_parent_material
				old.emitting = false
			return old
	if not (gpu is Particles2D) or not (gpu.process_material is ParticlesMaterial):
		return null
	var cpu = CPUParticles2D.new()
	cpu.convert_from_particles(gpu)
	cpu.name = "CPUTwin"
	cpu.position = Vector2.ZERO
	cpu.material = gpu.material
	cpu.use_parent_material = gpu.use_parent_material
	cpu.light_mask = gpu.light_mask
	cpu.emitting = false
	gpu.add_child(cpu)
	gpu.set_meta("cpu_twin", cpu)
	return cpu


func _existing_twin(gpu):
	if gpu != null and is_instance_valid(gpu) and gpu.has_meta("cpu_twin"):
		var t = gpu.get_meta("cpu_twin")
		if is_instance_valid(t):
			return t
	return null


# gpu.emitting = on 대신 사용. CPU 모드면 CPU 파티클을 켜고/끈다.
func emit(gpu, on: bool) -> void:
	if gpu == null or not is_instance_valid(gpu):
		return
	if use_cpu():
		var t = get_twin(gpu)
		if t != null:
			if on:
				t.restart()
			else:
				t.emitting = false
			gpu.emitting = false
			return
	gpu.emitting = on
	if not on:
		var t2 = _existing_twin(gpu)
		if t2 != null:
			t2.emitting = false


# gpu.emitting 을 읽는 대신 사용.
func is_emitting(gpu) -> bool:
	var t = _existing_twin(gpu)
	if t != null and use_cpu():
		return t.emitting
	return gpu.emitting
