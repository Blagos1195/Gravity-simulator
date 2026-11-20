extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	assert(RocketDesign.validation_errors(design).is_empty())
	assert(is_equal_approx(RocketDesign.total_initial_mass(design), 395500.0))
	assert(RocketDesign.total_delta_v(design) > 0.0)
	var heavier := design.duplicate(true)
	heavier["payload_mass"] = 5000.0
	assert(RocketDesign.total_delta_v(heavier) < RocketDesign.total_delta_v(design))
	var incomplete := design.duplicate(true)
	incomplete["stages"].pop_back()
	assert(not RocketDesign.validation_errors(incomplete).is_empty())
	print("Rocket design tests passed.")
	quit()
