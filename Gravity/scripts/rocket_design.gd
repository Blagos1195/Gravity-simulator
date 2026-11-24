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
		for key in ["visual_type", "visual_width_factor", "visual_height_factor", "visual_color_rgb"]:
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
		"stages": []
	}
	for payload_option in payload_options():
		if is_equal_approx(float(payload_option.get("mass", -1.0)), float(design["payload_mass"])):
			var payload_id := str(payload_option.get("id", "probe"))
			design["payload_type"] = payload_id
			design["payload_visual"] = payload_visual_data(payload_id)
			break
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

static func total_initial_mass(design: Dictionary) -> float:
	var stages: Array = design.get("stages", [])
	var mass := float(design.get("payload_mass", 0.0))
	for stage in stages:
		mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
	return mass

static func stage_ignition_mass(design: Dictionary, stage_index: int) -> float:
	var stages: Array = design.get("stages", [])
	var mass := float(design.get("payload_mass", 0.0))
	for i in range(stage_index, stages.size()):
		var stage: Dictionary = stages[i]
		mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
	return mass

static func stage_specific_impulse(stage: Dictionary, vacuum: bool) -> float:
	var thrust := float(stage.get("vacuum_thrust" if vacuum else "thrust", 0.0))
	var flow := float(stage.get("flow", 0.0))
	if flow <= 0.0:
		return 0.0
	return thrust / (flow * G0)

static func total_delta_v(design: Dictionary) -> float:
	var stages: Array = design.get("stages", [])
	var delta_v := 0.0
	var mass := total_initial_mass(design)
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var fuel := float(stage.get("fuel_capacity", 0.0))
		var flow := float(stage.get("flow", 0.0))
		var thrust := float(stage.get("vacuum_thrust", 0.0))
		var final_mass := mass - fuel
		if fuel > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > 0.0:
			delta_v += thrust / flow * log(mass / final_mass)
		mass = final_mass - float(stage.get("dry_mass", 0.0))
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
		var dry := float(stage.get("dry_mass", 0.0))
		var fuel := float(stage.get("fuel_capacity", 0.0))
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
		if dry <= 0.0 or fuel <= 0.0 or flow <= 0.0 or sea_thrust <= 0.0 or vacuum_thrust <= 0.0 or not (engine_value is int or engine_value is float) or float(engine_value) != float(engines) or engines < 1:
			continue
		if vacuum_thrust < sea_thrust:
			errors.append("Stage %d vacuum thrust cannot be lower than sea-level thrust." % (i + 1))
		var sea_isp := stage_specific_impulse(stage, false)
		var vacuum_isp := stage_specific_impulse(stage, true)
		if sea_isp <= 0.0 or vacuum_isp <= 0.0:
			errors.append("Stage %d must have positive engine efficiency." % (i + 1))
		var ignition_mass := stage_ignition_mass(design, i)
		var ignition_thrust := sea_thrust if i == 0 else vacuum_thrust
		var thrust_to_weight := ignition_thrust * engines / maxf(1.0, ignition_mass * G0)
		if i == 0 and thrust_to_weight < 1.0:
			errors.append("First-stage pad TWR must be at least 1.00 to lift off from Earth.")
	if total_mass > 0.0 and stages.size() >= MIN_STAGES:
		var delta_v := total_delta_v(design)
		if delta_v < MIN_TOTAL_DELTA_V:
			errors.append("Vehicle ideal delta-v is too low for a credible Earth launch (minimum 8.5 km/s).")
		
	return errors
