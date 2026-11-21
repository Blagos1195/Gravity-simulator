extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	print("Default vehicle validation: ", RocketDesign.validation_errors(design))
	assert(RocketDesign.validation_errors(design).is_empty())
	assert(is_equal_approx(RocketDesign.total_initial_mass(design), 364500.0))
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
	var weak_upper_stage := design.duplicate(true)
	weak_upper_stage["stages"][1]["vacuum_thrust"] = 100000.0
	weak_upper_stage["stages"][1]["thrust"] = 80000.0
	weak_upper_stage["stages"][1]["flow"] = 25.3
	var weak_stage_errors := RocketDesign.validation_errors(weak_upper_stage)
	assert(not weak_stage_errors.is_empty())
	assert(str(weak_stage_errors).contains("ignition TWR"))
	var incomplete := design.duplicate(true)
	incomplete["stages"].pop_back()
	assert(not RocketDesign.validation_errors(incomplete).is_empty())
	for preset in RocketDesign.preset_options():
		var preset_id := str(preset.get("id", ""))
		var preset_design := RocketDesign.create_preset(preset_id)
		var preset_errors := RocketDesign.validation_errors(preset_design)
		assert(preset_errors.is_empty(), "%s: %s" % [preset_id, str(preset_errors)])
	var odyssey := RocketDesign.create_preset("DEEP_SPACE")
	assert(is_equal_approx(RocketDesign.total_initial_mass(odyssey), 448500.0))
	assert(RocketDesign.total_delta_v(odyssey) < RocketDesign.MAX_TOTAL_DELTA_V)
	assert(RocketDesign.total_delta_v(odyssey) > RocketDesign.MIN_TOTAL_DELTA_V)
	print("Rocket design tests passed.")
	quit()
