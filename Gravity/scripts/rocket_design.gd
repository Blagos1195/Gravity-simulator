extends RefCounted
class_name RocketDesign

const ContentCatalog = preload("res://scripts/content_catalog.gd")

const G0 := 9.80665
const MIN_STAGES := 1
const MIN_TOTAL_DELTA_V := 8500.0

static func _rocket_catalog() -> Dictionary:
	var catalog: Dictionary = ContentCatalog.get_catalog()
	return catalog.get("rocket", {})

static func payload_options() -> Array:
	var options: Array = _rocket_catalog().get("builder_options", {}).get("payloads", [])
	return options.duplicate(true)

static func payload_visual_data(payload_id: String) -> Dictionary:
	for option in payload_options():
		if str(option.get("id", "")) != payload_id:
			continue
		var visual := {}
		for key in ["visual_type", "visual_width_factor", "visual_height_factor", "visual_color_rgb", "telescope_range_au", "satellite_role", "revenue_per_day", "operating_cost_per_day", "operational_lifetime_days"]:
			if option.has(key):
				visual[key] = option[key]
		return visual
	return {}

static func payload_mass_limits() -> Dictionary:
	var limits: Dictionary = _rocket_catalog().get("builder_options", {}).get("payload_mass_limits", {
		"minimum": 0.001,
		"maximum": 1.0e300,
		"step": 1.0
	})
	return limits.duplicate(true)

static func engine_count_options() -> Array:
	var options: Array = _rocket_catalog().get("builder_options", {}).get("engine_counts", [1, 2, 3, 4, 6, 8])
	return options.duplicate()

static func tank_scale_options() -> Array:
	var options: Array = _rocket_catalog().get("builder_options", {}).get("tank_scales", [
		{"label": "Compact tank", "scale": 0.75},
		{"label": "Standard tank", "scale": 1.0},
		{"label": "Extended tank", "scale": 1.25}
	])
	return options.duplicate(true)

static func preset_options() -> Array:
	var presets: Dictionary = _rocket_catalog().get("presets", {})
	var options: Array = []
	for preset_id in presets:
		var preset: Dictionary = presets[preset_id]
		options.append({"id": str(preset_id), "label": str(preset.get("label", preset_id))})
	return options

static func create_preset(preset_id: String) -> Dictionary:
	var presets: Dictionary = _rocket_catalog().get("presets", {})
	if not presets.has(preset_id):
		push_error("Unknown rocket preset: %s" % preset_id)
		return create_default()
	return _design_from_catalog(presets[preset_id])

static func preset_description(preset_id: String) -> String:
	var presets: Dictionary = _rocket_catalog().get("presets", {})
	var preset: Dictionary = presets.get(preset_id, {})
	return str(preset.get("description", "Select a mission profile to load its vehicle."))

static func create_default() -> Dictionary:
	return _design_from_catalog(_rocket_catalog().get("default_design", {}))

static func stage_part_options() -> Array:
	var options: Array = []
	for part in _rocket_catalog().get("stage_parts", []):
		options.append({"id": str(part.get("id", "")), "label": str(part.get("label", part.get("name", "Stage part")))})
	return options

static func create_stage_part(part_id: String) -> Dictionary:
	for part in _rocket_catalog().get("stage_parts", []):
		if str(part.get("id", "")) == part_id:
			var stage: Dictionary = part.duplicate(true)
			stage["part_id"] = part_id
			stage.erase("id")
			stage.erase("label")
			return stage
	push_error("Unknown rocket stage part: %s" % part_id)
	return {}

static func configure_stage(part_id: String, engine_count: int, tank_scale: float) -> Dictionary:
	var stage := create_stage_part(part_id)
	if stage.is_empty():
		return {}
	stage["engine_count"] = 1
	stage["tank_scale"] = 1.0
	return reconfigure_stage(stage, engine_count, tank_scale)

static func reconfigure_stage(stage: Dictionary, engine_count: int, tank_scale: float) -> Dictionary:
	var valid_engine_count := false
	for option in engine_count_options():
		if int(option) == engine_count and is_equal_approx(float(option), float(engine_count)):
			valid_engine_count = true
			break
	if not valid_engine_count:
		return {}
	var valid_tank_scale := false
	for tank_option in tank_scale_options():
		if is_equal_approx(float(tank_option.get("scale", 0.0)), tank_scale):
			valid_tank_scale = true
			break
	if not valid_tank_scale:
		return {}
	var previous_engine_count := int(stage.get("engine_count", 1))
	var previous_tank_scale := float(stage.get("tank_scale", 1.0))
	if previous_engine_count < 1 or previous_tank_scale <= 0.0:
		return {}
	var configured := stage.duplicate(true)
	var tank_ratio := tank_scale / previous_tank_scale
	configured["engine_count"] = engine_count
	configured["tank_scale"] = tank_scale
	configured["dry_mass"] = float(stage.get("dry_mass", 0.0)) * tank_ratio
	configured["fuel_capacity"] = float(stage.get("fuel_capacity", 0.0)) * tank_ratio
	configured["thrust"] = float(stage.get("thrust", 0.0)) * float(previous_engine_count) / float(engine_count)
	configured["vacuum_thrust"] = float(stage.get("vacuum_thrust", 0.0)) * float(previous_engine_count) / float(engine_count)
	configured["flow"] = float(stage.get("flow", 0.0)) * float(previous_engine_count) / float(engine_count)
	return configured

static func default_stage_part() -> Dictionary:
	var parts: Array = stage_part_options()
	if parts.is_empty():
		push_error("Rocket catalog does not define any stage parts.")
		return {}
	var part_id := str(parts[mini(1, parts.size() - 1)].get("id", ""))
	return create_stage_part(part_id)

static func _design_from_catalog(definition: Dictionary) -> Dictionary:
	var design := {
		"name": str(definition.get("name", "Custom Vehicle")),
		"payload_mass": float(definition.get("payload_mass", 500.0)),
		"payload_components": definition.get("payload_components", []).duplicate(true),
		"stages": []
	}
	var selected_payload_id := str(definition.get("payload_id", ""))
	if selected_payload_id.is_empty():
		for payload_option in payload_options():
			if is_equal_approx(float(payload_option.get("mass", -1.0)), float(design["payload_mass"])):
				selected_payload_id = str(payload_option.get("id", "probe"))
				break
	if not selected_payload_id.is_empty():
		design["payload_type"] = selected_payload_id
		design["payload_visual"] = payload_visual_data(selected_payload_id)
	var stage_parts: Dictionary = {}
	for part in _rocket_catalog().get("stage_parts", []):
		stage_parts[str(part.get("id", ""))] = part
	for part_id_variant in definition.get("stages", []):
		var part_id := str(part_id_variant)
		if not stage_parts.has(part_id):
			push_error("Rocket design references missing stage part: %s" % part_id)
			return create_default() if definition.has("stages") else design
		var part: Dictionary = stage_parts[part_id]
		var stage: Dictionary = part.duplicate(true)
		stage["part_id"] = part_id
		stage.erase("id")
		stage.erase("label")
		design["stages"].append(stage)
	return design

static func payload_component_options() -> Array:
	var options: Array = _rocket_catalog().get("builder_options", {}).get("payload_components", [])
	return options.duplicate(true)

static func payload_component_definition(component_id: String) -> Dictionary:
	for option in payload_component_options():
		if str(option.get("id", "")) == component_id:
			return option
	return {}

static func payload_component_definition_for_entry(entry: Dictionary) -> Dictionary:
	var definition := payload_component_definition(str(entry.get("id", "")))
	if definition.is_empty():
		var saved_definition: Variant = entry.get("definition", {})
		if saved_definition is Dictionary:
			return saved_definition.duplicate(true)
	return definition

static func add_payload_component(design: Dictionary, component_id: String) -> bool:
	var definition := payload_component_definition(component_id)
	if definition.is_empty():
		return false
	var components: Array = design.get("payload_components", []).duplicate(true)
	components.append({"id": component_id, "definition": definition.duplicate(true)})
	design["payload_components"] = components
	return true

static func remove_payload_component(design: Dictionary, component_index: int) -> bool:
	var components: Array = design.get("payload_components", []).duplicate(true)
	if component_index < 0 or component_index >= components.size():
		return false
	components.remove_at(component_index)
	design["payload_components"] = components
	return true

static func payload_component_mass(design: Dictionary, include_fairings: bool = true) -> float:
	var total := 0.0
	for entry_variant in design.get("payload_components", []):
		if not entry_variant is Dictionary:
			continue
		var definition := payload_component_definition_for_entry(entry_variant)
		if definition.is_empty():
			continue
		if not include_fairings and str(definition.get("component_type", "")) == "fairing":
			continue
		total += float(definition.get("dry_mass", 0.0))
	return total

static func total_payload_mass(design: Dictionary, fairing_jettisoned: bool = false) -> float:
	return float(design.get("payload_mass", 0.0)) + payload_component_mass(design, not fairing_jettisoned)

static func payload_component_value(design: Dictionary, component_type: String, key: String, default_value: Variant = null) -> Variant:
	for entry_variant in design.get("payload_components", []):
		if not entry_variant is Dictionary:
			continue
		var definition := payload_component_definition_for_entry(entry_variant)
		if str(definition.get("component_type", "")) == component_type and definition.has(key):
			return definition[key]
	return default_value

static func has_payload_component(design: Dictionary, component_type: String) -> bool:
	for entry_variant in design.get("payload_components", []):
		if not entry_variant is Dictionary:
			continue
		var definition := payload_component_definition_for_entry(entry_variant)
		if str(definition.get("component_type", "")) == component_type:
			return true
	return false

static func _payload_component_definition_is_valid(definition: Dictionary) -> bool:
	var component_type := str(definition.get("component_type", ""))
	if not ["fairing", "solar_panels", "antenna", "docking_port", "instrument"].has(component_type):
		return false
	var dry_mass: Variant = definition.get("dry_mass")
	return (dry_mass is int or dry_mass is float) and is_finite(float(dry_mass)) and float(dry_mass) > 0.0

static func booster_options() -> Array:
	var options: Array = _rocket_catalog().get("builder_options", {}).get("booster_options", [])
	return options.duplicate(true)

static func booster_definition(booster_id: String) -> Dictionary:
	for option in booster_options():
		if str(option.get("id", "")) == booster_id:
			return option
	return {}

static func booster_definition_for_entry(booster_entry: Dictionary) -> Dictionary:
	var definition := booster_definition(str(booster_entry.get("id", "")))
	if definition.is_empty():
		var saved_definition: Variant = booster_entry.get("definition", {})
		if saved_definition is Dictionary:
			return saved_definition.duplicate(true)
	return definition

static func add_booster_pair(design: Dictionary, stage_index: int, booster_id: String) -> bool:
	var stages: Array = design.get("stages", [])
	if stage_index < 0 or stage_index >= stages.size() or booster_definition(booster_id).is_empty():
		return false
	var stage: Dictionary = stages[stage_index].duplicate(true)
	var boosters: Array = stage.get("boosters", []).duplicate(true)
	boosters.append({"id": booster_id, "definition": booster_definition(booster_id).duplicate(true)})
	stage["boosters"] = boosters
	stages[stage_index] = stage
	design["stages"] = stages
	return true

static func remove_booster_pair(design: Dictionary, stage_index: int, booster_index: int) -> bool:
	var stages: Array = design.get("stages", [])
	if stage_index < 0 or stage_index >= stages.size():
		return false
	var stage: Dictionary = stages[stage_index].duplicate(true)
	var boosters: Array = stage.get("boosters", []).duplicate(true)
	if booster_index < 0 or booster_index >= boosters.size():
		return false
	boosters.remove_at(booster_index)
	stage["boosters"] = boosters
	stages[stage_index] = stage
	design["stages"] = stages
	return true

static func _booster_definition_is_valid(booster: Dictionary) -> bool:
	for key in ["dry_mass", "fuel_capacity", "thrust", "vacuum_thrust", "flow"]:
		var value: Variant = booster.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0:
			return false
	var pair_count: Variant = booster.get("pair_count", 0)
	return (pair_count is int or pair_count is float) and int(pair_count) == 2 and float(pair_count) == 2.0 and float(booster.vacuum_thrust) >= float(booster.thrust)

static func stage_booster_stats(stage: Dictionary) -> Dictionary:
	var totals := {"dry_mass": 0.0, "fuel_capacity": 0.0, "thrust": 0.0, "vacuum_thrust": 0.0, "flow": 0.0}
	for booster_variant in stage.get("boosters", []):
		if not booster_variant is Dictionary:
			continue
		var booster := booster_definition_for_entry(booster_variant)
		if booster.is_empty():
			continue
		var pair_count := maxi(1, int(booster.get("pair_count", 2)))
		for key in totals:
			totals[key] += float(booster.get(key, 0.0)) * pair_count
	return totals

static func stage_total_dry_mass(stage: Dictionary) -> float:
	return float(stage.get("dry_mass", 0.0)) + float(stage_booster_stats(stage).dry_mass)

static func stage_total_fuel_capacity(stage: Dictionary) -> float:
	return float(stage.get("fuel_capacity", 0.0)) + float(stage_booster_stats(stage).fuel_capacity)

static func stage_total_thrust(stage: Dictionary, vacuum: bool = false) -> float:
	var key := "vacuum_thrust" if vacuum else "thrust"
	return float(stage.get(key, 0.0)) * float(stage.get("engine_count", 1)) + float(stage_booster_stats(stage).get(key, 0.0))

static func stage_total_flow(stage: Dictionary) -> float:
	return float(stage.get("flow", 0.0)) * float(stage.get("engine_count", 1)) + float(stage_booster_stats(stage).flow)

static func total_initial_mass(design: Dictionary) -> float:
	var stages: Array = design.get("stages", [])
	var mass := total_payload_mass(design)
	for stage in stages:
		mass += stage_total_dry_mass(stage) + stage_total_fuel_capacity(stage)
	return mass

static func stage_ignition_mass(design: Dictionary, stage_index: int) -> float:
	var stages: Array = design.get("stages", [])
	var mass := total_payload_mass(design)
	for i in range(stage_index, stages.size()):
		var stage: Dictionary = stages[i]
		mass += stage_total_dry_mass(stage) + stage_total_fuel_capacity(stage)
	return mass

static func stage_specific_impulse(stage: Dictionary, vacuum: bool) -> float:
	var thrust := stage_total_thrust(stage, vacuum)
	var flow := stage_total_flow(stage)
	if flow <= 0.0:
		return 0.0
	return thrust / (flow * G0)

static func total_delta_v(design: Dictionary) -> float:
	var stages: Array = design.get("stages", [])
	var delta_v := 0.0
	var mass := total_initial_mass(design)
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var fuel := stage_total_fuel_capacity(stage)
		var flow := stage_total_flow(stage)
		var thrust := stage_total_thrust(stage, true)
		var final_mass := mass - fuel
		if fuel > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > 0.0:
			delta_v += thrust / flow * log(mass / final_mass)
		mass = final_mass - stage_total_dry_mass(stage)
	return delta_v

static func validation_errors(design: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var stages: Array = design.get("stages", [])
	var payload := float(design.get("payload_mass", 0.0))
	var payload_limits := payload_mass_limits()
	var minimum_payload := float(payload_limits.get("minimum", 10.0))
	var maximum_payload := float(payload_limits.get("maximum", 100000.0))
	if stages.size() < MIN_STAGES:
		errors.append("A vehicle must have at least one stage.")
	if payload <= 0.0:
		errors.append("Payload mass must be positive.")
	elif _rocket_catalog().get("builder_options", {}).has("payload_mass_limits") and (payload < minimum_payload or payload > maximum_payload):
		errors.append("Payload must be between %.3f kg and %.0f kg." % [minimum_payload, maximum_payload])
	var payload_components: Variant = design.get("payload_components", [])
	if not payload_components is Array:
		errors.append("Payload components must be an array.")
	else:
		for component_variant in payload_components:
			if not component_variant is Dictionary:
				errors.append("Payload components must contain objects.")
			else:
				var component_definition := payload_component_definition_for_entry(component_variant)
				if component_definition.is_empty() or not _payload_component_definition_is_valid(component_definition):
					errors.append("A payload component references an invalid module.")
				else:
					for visual_key in ["visual_width_factor", "visual_height_factor"]:
						if component_definition.has(visual_key) and (not (component_definition[visual_key] is int or component_definition[visual_key] is float) or not is_finite(float(component_definition[visual_key])) or float(component_definition[visual_key]) <= 0.0):
							errors.append("Payload component %s has an invalid %s." % [str(component_variant.get("id", "")), visual_key])
	var payload_visual: Variant = design.get("payload_visual", {})
	if not payload_visual is Dictionary:
		errors.append("Payload appearance settings must be an object.")
	else:
		if payload_visual.has("visual_type") and not ["probe", "crew", "satellite", "cargo"].has(str(payload_visual.visual_type)):
			errors.append("Payload appearance uses an unsupported visual type.")
		for visual_key in ["visual_width_factor", "visual_height_factor"]:
			if payload_visual.has(visual_key):
				var visual_value: Variant = payload_visual[visual_key]
				if not (visual_value is int or visual_value is float) or not is_finite(float(visual_value)) or float(visual_value) <= 0.0:
					errors.append("Payload %s must be a positive finite number." % visual_key)
		if payload_visual.has("telescope_range_au"):
			var telescope_range: Variant = payload_visual.telescope_range_au
			if not (telescope_range is int or telescope_range is float) or not is_finite(float(telescope_range)) or float(telescope_range) < 0.0:
				errors.append("Payload telescope_range_au must be a finite non-negative number.")
		if payload_visual.has("satellite_role") and not str(payload_visual.satellite_role).is_empty() and str(payload_visual.get("visual_type", "satellite")) != "satellite":
			errors.append("Satellite roles require a satellite payload visual.")
		for economy_key in ["revenue_per_day", "operating_cost_per_day", "operational_lifetime_days"]:
			if payload_visual.has(economy_key):
				var economy_value: Variant = payload_visual[economy_key]
				var minimum_value := 0.0 if economy_key != "operational_lifetime_days" else 0.000001
				if not (economy_value is int or economy_value is float) or not is_finite(float(economy_value)) or float(economy_value) < minimum_value:
					errors.append("Payload %s must be a positive finite number." % economy_key)
		if payload_visual.has("visual_color_rgb"):
			var payload_color: Variant = payload_visual.visual_color_rgb
			var valid_payload_color: bool = payload_color is Array and payload_color.size() == 3
			if valid_payload_color:
				for component in payload_color:
					if not (component is int or component is float) or not is_finite(float(component)) or float(component) < 0.0 or float(component) > 1.0:
						valid_payload_color = false
						break
			if not valid_payload_color:
				errors.append("Payload body colour must contain three finite RGB values between zero and one.")
	if stages.is_empty():
		return errors
	var total_mass := total_initial_mass(design)
	if total_mass <= 0.0:
		errors.append("Total vehicle mass must be positive.")
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var dry := stage_total_dry_mass(stage)
		var fuel := stage_total_fuel_capacity(stage)
		var sea_thrust := float(stage.get("thrust", 0.0))
		var vacuum_thrust := float(stage.get("vacuum_thrust", 0.0))
		var flow := float(stage.get("flow", 0.0))
		var engine_value: Variant = stage.get("engine_count", 0)
		var engines := int(engine_value) if engine_value is int or engine_value is float else 0
		for visual_key in ["visual_length_factor", "visual_diameter_factor"]:
			if stage.has(visual_key):
				var visual_value: Variant = stage[visual_key]
				if not (visual_value is int or visual_value is float) or not is_finite(float(visual_value)) or float(visual_value) <= 0.0:
					errors.append("Stage %d %s must be a positive finite number." % [i + 1, visual_key])
		if stage.has("visual_color_rgb"):
			var visual_color: Variant = stage["visual_color_rgb"]
			var valid_color: bool = visual_color is Array and visual_color.size() == 3
			if valid_color:
				for component in visual_color:
					if not (component is int or component is float) or not is_finite(float(component)) or float(component) < 0.0 or float(component) > 1.0:
						valid_color = false
						break
			if not valid_color:
				errors.append("Stage %d body colour must contain three finite RGB values between zero and one." % (i + 1))
		if dry <= 0.0 or fuel <= 0.0 or flow <= 0.0 or sea_thrust <= 0.0 or vacuum_thrust <= 0.0:
			errors.append("Stage %d mass, propellant, thrust and flow values must all be positive." % (i + 1))
		if not (engine_value is int or engine_value is float) or float(engine_value) != float(engines) or engines < 1:
			errors.append("Stage %d must have a positive whole-number engine count." % (i + 1))
		if stage.has("engine_layout") and not ["linear", "cluster", "radial"].has(str(stage.engine_layout)):
			errors.append("Stage %d has an unsupported engine layout." % (i + 1))
		var boosters: Variant = stage.get("boosters", [])
		if not boosters is Array:
			errors.append("Stage %d booster modules must be an array." % (i + 1))
		else:
			for booster_variant in boosters:
				if not booster_variant is Dictionary:
					errors.append("Stage %d contains an invalid booster module." % (i + 1))
				else:
					var booster_definition_data := booster_definition_for_entry(booster_variant)
					if booster_definition_data.is_empty() or not _booster_definition_is_valid(booster_definition_data):
						errors.append("Stage %d references an invalid booster module." % (i + 1))
		if dry <= 0.0 or fuel <= 0.0 or flow <= 0.0 or sea_thrust <= 0.0 or vacuum_thrust <= 0.0 or not (engine_value is int or engine_value is float) or float(engine_value) != float(engines) or engines < 1:
			continue
		if vacuum_thrust < sea_thrust:
			errors.append("Stage %d vacuum thrust cannot be lower than sea-level thrust." % (i + 1))
		var sea_isp := stage_specific_impulse(stage, false)
		var vacuum_isp := stage_specific_impulse(stage, true)
		if sea_isp <= 0.0 or vacuum_isp <= 0.0:
			errors.append("Stage %d must have positive engine efficiency." % (i + 1))
		var ignition_mass := stage_ignition_mass(design, i)
		var ignition_thrust := stage_total_thrust(stage, i != 0)
		var thrust_to_weight := ignition_thrust / maxf(1.0, ignition_mass * G0)
		if i == 0 and thrust_to_weight < 1.0:
			errors.append("First-stage pad TWR must be at least 1.00 to lift off from Earth.")
	if total_mass > 0.0 and stages.size() >= MIN_STAGES:
		var delta_v := total_delta_v(design)
		if delta_v < MIN_TOTAL_DELTA_V:
			errors.append("Vehicle ideal delta-v is too low for a credible Earth launch (minimum 8.5 km/s).")
		
	return errors
