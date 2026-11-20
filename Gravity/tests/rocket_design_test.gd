extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	assert(RocketDesign.validation_errors(design).is_empty())
	assert(is_equal_approx(RocketDesign.total_initial_mass(design), 395500.0))
	assert(RocketDesign.total_delta_v(design) > 0.0)
	var multi_engine := design.duplicate(true)
	multi_engine["stages"][0]["engine_count"] = 3
	assert(RocketDesign.validation_errors(multi_engine).is_empty())
	assert(is_equal_approx(RocketDesign.total_delta_v(multi_engine), RocketDesign.total_delta_v(design)))
	var heavier := design.duplicate(true)
	heavier["payload_mass"] = 5000.0
	assert(RocketDesign.total_delta_v(heavier) < RocketDesign.total_delta_v(design))
	var invalid_engine_count := design.duplicate(true)
	invalid_engine_count["stages"][1]["engine_count"] = 9
	assert(not RocketDesign.validation_errors(invalid_engine_count).is_empty())
	var incomplete := design.duplicate(true)
	incomplete["stages"].pop_back()
	assert(not RocketDesign.validation_errors(incomplete).is_empty())
	print("Rocket design tests passed.")
	quit()
