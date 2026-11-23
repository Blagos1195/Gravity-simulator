extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const ContentCatalog = preload("res://scripts/content_catalog.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	assert(RocketDesign.validation_errors(design).is_empty())
	assert(is_equal_approx(RocketDesign.total_initial_mass(design), 364500.0))
	assert(RocketDesign.total_delta_v(design) > 0.0)
	assert(is_equal_approx(RocketDesign.total_delta_v(design), FlightComputer.available_delta_v(design)), "Full staged delta-v calculations disagree")
	var multi_engine := design.duplicate(true)
	multi_engine["stages"][0]["engine_count"] = 3
	multi_engine["stages"][0]["thrust"] = float(multi_engine["stages"][0]["thrust"]) / 3.0
	multi_engine["stages"][0]["vacuum_thrust"] = float(multi_engine["stages"][0]["vacuum_thrust"]) / 3.0
	multi_engine["stages"][0]["flow"] = float(multi_engine["stages"][0]["flow"]) / 3.0
	assert(RocketDesign.validation_errors(multi_engine).is_empty())
	assert(is_equal_approx(RocketDesign.total_delta_v(multi_engine), RocketDesign.total_delta_v(design)))
	var configured_first_stage := RocketDesign.configure_stage("explorer_first_stage", 1, 1.25)
	assert(not configured_first_stage.is_empty())
	assert(int(configured_first_stage.engine_count) == 1)
	assert(is_equal_approx(float(configured_first_stage.fuel_capacity), 375000.0))
	assert(is_equal_approx(float(configured_first_stage.dry_mass), 37500.0))
	var configured_upper_stage := RocketDesign.configure_stage("explorer_upper_stage", 2, 1.0)
	assert(not configured_upper_stage.is_empty())
	var configured_design := design.duplicate(true)
	configured_design["stages"][0] = configured_first_stage
	configured_design["stages"][1] = configured_upper_stage
	assert(RocketDesign.validation_errors(configured_design).is_empty())
	var engine_variant := design.duplicate(true)
	engine_variant["stages"][1] = RocketDesign.configure_stage("explorer_upper_stage", 2, 1.0)
	assert(is_equal_approx(RocketDesign.total_delta_v(engine_variant), RocketDesign.total_delta_v(design)))
	assert(RocketDesign.total_initial_mass(configured_design) > RocketDesign.total_initial_mass(design))
	assert(RocketDesign.configure_stage("explorer_first_stage", 5, 1.0).is_empty())
	assert(RocketDesign.configure_stage("explorer_first_stage", 2, 1.1).is_empty())
	assert(RocketDesign.validation_errors(engine_variant).is_empty())
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
	assert(RocketDesign.engine_count_options().has(5) == false)
	assert(RocketDesign.payload_options().size() >= 5)
	assert(RocketDesign.tank_scale_options().size() >= 3)
	var mod_overlay := {
		"schema_version": 1,
		"rocket": {
			"stage_parts_add": [{
				"id": "test_mod_stage",
				"label": "Test Mod Stage",
				"name": "MOD STAGE",
				"dry_mass": 4000.0,
				"fuel_capacity": 30000.0,
				"thrust": 200000.0,
				"vacuum_thrust": 250000.0,
				"flow": 63.3,
				"engine_count": 1
			}],
			"presets_add": {
				"TEST_MOD_PRESET": {
					"name": "Test Mod Vehicle",
					"payload_mass": 500.0,
					"stages": ["explorer_first_stage", "test_mod_stage"]
				}
			},
			"builder_options": {
				"engine_counts_add": [5],
				"payloads_add": [{"id": "test_payload", "label": "Test payload · 2 t", "mass": 2000.0}],
				"tank_scales_add": [{"label": "Test tank", "scale": 1.5}]
			}
		}
	}
	var merged_catalog := ContentCatalog._merge_overlay(ContentCatalog.get_catalog(), mod_overlay)
	var merged_rocket: Dictionary = merged_catalog.rocket
	assert(merged_rocket.stage_parts.size() == ContentCatalog.get_catalog().rocket.stage_parts.size() + 1)
	assert(merged_rocket.presets.has("TEST_MOD_PRESET"))
	assert(merged_rocket.builder_options.engine_counts.has(5))
	assert(merged_rocket.builder_options.payloads.any(func(option: Dictionary): return str(option.id) == "test_payload"))
	assert(merged_rocket.builder_options.tank_scales.any(func(option: Dictionary): return is_equal_approx(float(option.scale), 1.5)))
	var modded_stage := RocketDesign.configure_stage("explorer_first_stage", 5, 1.5)
	assert(not modded_stage.is_empty())
	assert(int(modded_stage.engine_count) == 5)
	assert(is_equal_approx(float(modded_stage.fuel_capacity), 450000.0))
	print("Rocket design tests passed.")
	quit()
