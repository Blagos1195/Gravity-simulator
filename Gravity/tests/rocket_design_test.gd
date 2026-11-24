extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const ContentCatalog = preload("res://scripts/content_catalog.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	assert(is_equal_approx(float(RocketDesign.payload_visual_data("satellite").get("telescope_range_au", 0.0)), 1.2))
	assert(is_equal_approx(float(RocketDesign.payload_visual_data("survey_satellite").get("telescope_range_au", 0.0)), 3.5))
	assert(is_equal_approx(float(RocketDesign.payload_visual_data("deep_space_telescope").get("telescope_range_au", 0.0)), 10.5))
	var invalid_telescope_range := design.duplicate(true)
	invalid_telescope_range["payload_visual"] = {"telescope_range_au": -1.0}
	assert(not RocketDesign.validation_errors(invalid_telescope_range).is_empty())
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
	var reconfigured_stage := RocketDesign.reconfigure_stage(configured_first_stage, 3, 2.0)
	assert(not reconfigured_stage.is_empty())
	assert(int(reconfigured_stage.engine_count) == 3)
	assert(is_equal_approx(float(reconfigured_stage.dry_mass), 60000.0))
	assert(is_equal_approx(float(reconfigured_stage.thrust) * 3.0, float(configured_first_stage.thrust)))
	assert(is_equal_approx(float(reconfigured_stage.flow) * 3.0, float(configured_first_stage.flow)))
	var configured_upper_stage := RocketDesign.configure_stage("explorer_upper_stage", 2, 1.0)
	assert(not configured_upper_stage.is_empty())
	var configured_design := design.duplicate(true)
	configured_design["stages"][0] = configured_first_stage
	configured_design["stages"][0]["engine_layout"] = "cluster"
	assert(RocketDesign.validation_errors(configured_design).is_empty())
	var invalid_engine_layout := design.duplicate(true)
	invalid_engine_layout["stages"][0]["engine_layout"] = "spiral"
	assert(not RocketDesign.validation_errors(invalid_engine_layout).is_empty())
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
	invalid_engine_count["stages"][1]["engine_count"] = 1.5
	assert(not RocketDesign.validation_errors(invalid_engine_count).is_empty())
	var low_thrust_upper_stage := design.duplicate(true)
	low_thrust_upper_stage["stages"][1]["vacuum_thrust"] = 100000.0
	low_thrust_upper_stage["stages"][1]["thrust"] = 80000.0
	low_thrust_upper_stage["stages"][1]["flow"] = 25.3
	assert(RocketDesign.validation_errors(low_thrust_upper_stage).is_empty())
	var single_stage_design := {
		"name": "Single Stage",
		"payload_mass": 500.0,
		"payload_type": "cargo",
		"payload_visual": {"visual_type": "cargo", "visual_width_factor": 1.3, "visual_height_factor": 1.1, "visual_color_rgb": [0.2, 0.4, 0.6]},
		"stages": [{
			"dry_mass": 5000.0,
			"fuel_capacity": 100000.0,
			"thrust": 3000000.0,
			"vacuum_thrust": 3500000.0,
			"flow": 1000.0,
			"engine_count": 1
		}]
	}
	assert(RocketDesign.validation_errors(single_stage_design).is_empty())
	var custom_visual_design := design.duplicate(true)
	custom_visual_design["stages"][0]["visual_length_factor"] = 1.4
	custom_visual_design["stages"][0]["visual_diameter_factor"] = 0.8
	custom_visual_design["stages"][0]["visual_color_rgb"] = [0.2, 0.4, 0.6]
	assert(RocketDesign.validation_errors(custom_visual_design).is_empty())
	var invalid_visual_scale := custom_visual_design.duplicate(true)
	invalid_visual_scale["stages"][0]["visual_length_factor"] = -1.0
	assert(not RocketDesign.validation_errors(invalid_visual_scale).is_empty())
	var invalid_visual_color := custom_visual_design.duplicate(true)
	invalid_visual_color["stages"][0]["visual_color_rgb"] = [0.2, 1.4, 0.6]
	assert(not RocketDesign.validation_errors(invalid_visual_color).is_empty())
	var malformed_visual_color := custom_visual_design.duplicate(true)
	malformed_visual_color["stages"][0]["visual_color_rgb"] = [0.2, "blue", 0.6]
	assert(not RocketDesign.validation_errors(malformed_visual_color).is_empty())
	var single_stage_sim := SimulationView.new()
	single_stage_sim.set_rocket_design(single_stage_design)
	assert(single_stage_sim.rocket_stages.size() == 1)
	assert(is_equal_approx(float(single_stage_sim.rocket_stages[0].dry_mass), 5000.0))
	assert(single_stage_sim.payload_visual.visual_type == "cargo")
	var single_stage_save: Dictionary = single_stage_sim.get_save_data()
	assert(single_stage_save.rocket_design.payload_visual.visual_color_rgb == [0.2, 0.4, 0.6])
	single_stage_sim.free()
	var incomplete := design.duplicate(true)
	incomplete["stages"].clear()
	assert(not RocketDesign.validation_errors(incomplete).is_empty())
	for preset in RocketDesign.preset_options():
		var preset_id := str(preset.get("id", ""))
		var preset_design := RocketDesign.create_preset(preset_id)
		var preset_errors := RocketDesign.validation_errors(preset_design)
		assert(preset_errors.is_empty(), "%s: %s" % [preset_id, str(preset_errors)])
	var odyssey := RocketDesign.create_preset("DEEP_SPACE")
	assert(odyssey.payload_type == "probe")
	assert(odyssey.payload_visual.visual_type == "probe")
	var cargo_preset := RocketDesign.create_preset("LEO_CARGO")
	assert(cargo_preset.payload_type == "cargo")
	assert(cargo_preset.payload_visual.visual_type == "cargo")
	var satellite_preset := RocketDesign.create_preset("SMALL_SAT")
	assert(satellite_preset.payload_type == "satellite")
	assert(satellite_preset.payload_visual.visual_type == "satellite")
	assert(is_equal_approx(RocketDesign.total_initial_mass(odyssey), 448500.0))
	assert(RocketDesign.total_delta_v(odyssey) > RocketDesign.MIN_TOTAL_DELTA_V)
	var extended_design := design.duplicate(true)
	var light_stage: Dictionary = design["stages"][1].duplicate(true)
	light_stage["dry_mass"] = 500.0
	light_stage["fuel_capacity"] = 500.0
	light_stage["thrust"] = 1000000.0
	light_stage["vacuum_thrust"] = 1100000.0
	light_stage["flow"] = 300.0
	for i in range(7):
		extended_design["stages"].append(light_stage.duplicate(true))
	assert(extended_design["stages"].size() == 9)
	assert(RocketDesign.validation_errors(extended_design).is_empty())
	var high_engine_stage := RocketDesign.configure_stage("explorer_first_stage", 12, 10.0)
	assert(not high_engine_stage.is_empty())
	assert(int(high_engine_stage.engine_count) == 12)
	assert(is_equal_approx(float(high_engine_stage.fuel_capacity), 3000000.0))
	assert(RocketDesign.engine_count_options().has(5) == false)
	assert(RocketDesign.payload_options().size() >= 5)
	assert(RocketDesign.tank_scale_options().size() >= 3)
	var mod_overlay := {
		"schema_version": 1,
		"planets_add": [{
			"name": "Test Planet",
			"mass": 1.0e23,
			"radius": 2000000.0,
			"a": 2.2,
			"adot": 0.0,
			"e": 0.01,
			"edot": 0.0,
			"i": 0.0,
			"idot": 0.0,
			"L": 0.0,
			"Ldot": 100.0,
			"peri": 0.0,
			"peridot": 0.0,
			"node": 0.0,
			"nodedot": 0.0,
			"orbital_period": 1000.0,
			"rotation_rate_rad_s": 0.00001,
			"solid": true,
			"color_rgb": [0.4, 0.4, 0.7],
			"atmosphere": {
				"model": "none",
				"height_m": 0.0,
				"visual_height_m": 0.0,
				"surface_density_kg_m3": 0.0,
				"scale_height_m": 1.0,
				"temperature_k": 250.0,
				"gas_constant_j_kg_k": 287.05287,
				"gamma": 1.4,
				"color_rgb": [0.0, 0.0, 0.0]
			},
			"satellites_add": [{
				"name": "Test Moon",
				"mass_kg": 1.0e15,
				"radius_m": 10000.0,
				"semi_major_axis_m": 10000000.0,
				"orbital_period_s": 86400.0,
				"phase_rad": 0.0,
				"rotation_rate_rad_s": 0.0001,
				"solid": true,
				"color_rgb": [0.7, 0.7, 0.7]
			}]
		}],
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
				"engine_count": 1,
				"engine_layout": "cluster",
				"visual_length_factor": 1.4,
				"visual_diameter_factor": 1.2,
				"visual_color_rgb": [0.2, 0.4, 0.6]
			}],
			"presets_add": {
				"TEST_MOD_PRESET": {
					"name": "Test Mod Vehicle",
					"payload_mass": 2000.0,
					"payload_id": "test_payload",
					"stages": ["explorer_first_stage", "test_mod_stage"]
				}
			},
			"builder_options": {
				"engine_counts_add": [5],
				"payloads_add": [{"id": "test_payload", "label": "Test payload · 2 t", "mass": 2000.0, "visual_type": "cargo", "visual_width_factor": 1.4, "visual_height_factor": 1.1, "visual_color_rgb": [0.2, 0.4, 0.6]}],
				"tank_scales_add": [{"label": "Test tank", "scale": 2.5}]
			}
		}
	}
	var invalid_payload_overlay: Dictionary = mod_overlay.duplicate(true)
	invalid_payload_overlay["rocket"]["builder_options"]["payloads_add"][0]["visual_type"] = "spaceship"
	var invalid_payload_catalog := ContentCatalog._merge_overlay(ContentCatalog.get_catalog(), invalid_payload_overlay)
	assert(not ContentCatalog._catalog_error(invalid_payload_catalog).is_empty())
	var invalid_preset_overlay: Dictionary = mod_overlay.duplicate(true)
	invalid_preset_overlay["rocket"]["presets_add"]["TEST_MOD_PRESET"]["payload_id"] = "missing_payload"
	var invalid_preset_catalog := ContentCatalog._merge_overlay(ContentCatalog.get_catalog(), invalid_preset_overlay)
	assert(not ContentCatalog._catalog_error(invalid_preset_catalog).is_empty())
	var merged_catalog := ContentCatalog._merge_overlay(ContentCatalog.get_catalog(), mod_overlay)
	assert(ContentCatalog._catalog_error(merged_catalog).is_empty())
	assert(merged_catalog.planets.size() == ContentCatalog.get_catalog().planets.size() + 1)
	assert(merged_catalog.planets[-1].satellites[0].name == "Test Moon")
	var merged_rocket: Dictionary = merged_catalog.rocket
	assert(merged_rocket.stage_parts.size() == ContentCatalog.get_catalog().rocket.stage_parts.size() + 1)
	assert(merged_rocket.stage_parts[-1].engine_layout == "cluster")
	assert(is_equal_approx(float(merged_rocket.stage_parts[-1].visual_length_factor), 1.4))
	assert(merged_rocket.stage_parts[-1].visual_color_rgb == [0.2, 0.4, 0.6])
	assert(merged_rocket.presets.has("TEST_MOD_PRESET"))
	var original_catalog: Dictionary = ContentCatalog._catalog
	ContentCatalog._catalog = merged_catalog
	var modded_payload_preset := RocketDesign.create_preset("TEST_MOD_PRESET")
	assert(modded_payload_preset.payload_type == "test_payload")
	assert(modded_payload_preset.payload_visual.visual_type == "cargo")
	assert(RocketDesign.engine_count_options().has(5))
	var has_test_payload := false
	for payload_option in RocketDesign.payload_options():
		if str(payload_option.id) == "test_payload":
			has_test_payload = true
	assert(has_test_payload)
	var test_payload_visual := RocketDesign.payload_visual_data("test_payload")
	assert(test_payload_visual.visual_type == "cargo")
	assert(is_equal_approx(float(test_payload_visual.visual_width_factor), 1.4))
	assert(test_payload_visual.visual_color_rgb == [0.2, 0.4, 0.6])
	var invalid_payload_visual := design.duplicate(true)
	invalid_payload_visual["payload_visual"] = {"visual_type": "spaceship"}
	assert(not RocketDesign.validation_errors(invalid_payload_visual).is_empty())
	var has_test_tank_scale := false
	for tank_option in RocketDesign.tank_scale_options():
		if is_equal_approx(float(tank_option.scale), 2.5):
			has_test_tank_scale = true
	assert(has_test_tank_scale)
	var modded_stage := RocketDesign.configure_stage("explorer_first_stage", 5, 1.5)
	assert(not modded_stage.is_empty())
	assert(int(modded_stage.engine_count) == 5)
	assert(is_equal_approx(float(modded_stage.fuel_capacity), 450000.0))
	ContentCatalog._catalog = original_catalog
	print("Rocket design tests passed.")
	quit()
