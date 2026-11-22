extends Particles2D

func start():
	Tools.timer(2.0,"queue_free",self)
	FxMode.emit(self, true)
	FxMode.emit(get_node("remains_particles"), true)
