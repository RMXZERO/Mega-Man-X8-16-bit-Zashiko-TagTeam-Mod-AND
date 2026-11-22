extends X8OptionButton
# 옵션 "파티클 효과": 터치(선택)할 때마다 GPU 파티클 <-> CPU 파티클 전환. FxMode.get_mode() 참고.

func setup() -> void :
	set_mode(FxMode.get_mode())

func increase_value() -> void :
	set_mode(1 - FxMode.get_mode())

func decrease_value() -> void :
	set_mode(1 - FxMode.get_mode())

func set_mode(value: int) -> void :
	Configurations.set("EffectMode", value)
	display_mode()

func display_mode() -> void :
	if FxMode.get_mode() == 1:
		display_value("CPU Particles")
	else:
		display_value("GPU Particles")
