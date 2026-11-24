extends SceneTree

const RocketVisual = preload("res://scripts/rocket_visual.gd")

func _initialize() -> void:
	var planetary_scale := RocketVisual.camera_scale(0.000045, 1.0)
	var close_scale := RocketVisual.camera_scale(0.02, 1.0)
	assert(planetary_scale < 0.01, "Spacecraft are still exaggerated at planetary zoom")
	assert(close_scale > planetary_scale * 10.0, "Spacecraft do not grow naturally when the camera zooms in")
	assert(is_equal_approx(RocketVisual.camera_scale(0.000045, 0.55), 0.002))
	assert(is_equal_approx(RocketVisual.camera_scale(0.02, 1.0), 0.2))
	assert(is_equal_approx(RocketVisual.camera_scale(0.1, 1.0), 1.0))
	assert(RocketVisual.camera_scale(1.0, 1.0) <= 5.0)
	print("Rocket visual scale tests passed.")
	quit()
