extends RefCounted
class_name RocketDesign

const ContentCatalog = preload("res://scripts/content_catalog.gd")

const G0 := 9.80665
const MIN_STAGES := 2
const MAX_STAGES := 8
const MAX_TOTAL_MASS := 5000000.0
const MIN_TOTAL_DELTA_V := 8500.0
const MAX_TOTAL_DELTA_V := 16500.0

static func _rocket_catalog() -> Dictionary:
	var catalog: Dictionary = ContentCatalog.get_catalog()
	return catalog.get("rocket", {})

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
	if stages.size() < MIN_STAGES or stages.size() > MAX_STAGES:
		errors.append("A vehicle must have between 2 and 8 stages.")
	if payload < 10.0 or payload > 100000.0:
		errors.append("Payload must be between 10 kg and 100,000 kg.")
	if stages.is_empty():
		return errors
	var total_mass := total_initial_mass(design)
	if total_mass > MAX_TOTAL_MASS:
		errors.append("Total launch mass cannot exceed 5,000 tonnes.")
	if total_mass <= 0.0:
		errors.append("Total vehicle mass must be positive.")
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var dry := float(stage.get("dry_mass", 0.0))
		var fuel := float(stage.get("fuel_capacity", 0.0))
		var sea_thrust := float(stage.get("thrust", 0.0))
		var vacuum_thrust := float(stage.get("vacuum_thrust", 0.0))
		var flow := float(stage.get("flow", 0.0))
		var engines := int(stage.get("engine_count", 0))
		if dry < 500.0 or dry > 200000.0:
			errors.append("Stage %d dry mass must be 500–200,000 kg." % (i + 1))
		if fuel < 500.0 or fuel > 1000000.0:
			errors.append("Stage %d propellant must be 500–1,000,000 kg." % (i + 1))
		if sea_thrust < 100000.0 or sea_thrust > 20000000.0:
			errors.append("Stage %d sea-level thrust per engine must be 0.1–20 MN." % (i + 1))
		if vacuum_thrust < 100000.0 or vacuum_thrust > 22000000.0:
			errors.append("Stage %d vacuum thrust per engine must be 0.1–22 MN." % (i + 1))
		if flow < 20.0 or flow > 8000.0:
			errors.append("Stage %d fuel flow per engine must be 20–8,000 kg/s." % (i + 1))
		if engines < 1 or engines > 8:
			errors.append("Stage %d must have between 1 and 8 engines." % (i + 1))
		if dry <= 0.0 or fuel <= 0.0 or flow <= 0.0 or sea_thrust <= 0.0 or vacuum_thrust <= 0.0:
			continue
		var dry_fraction := dry / (dry + fuel)
		if dry_fraction < 0.05 or dry_fraction > 0.35:
			errors.append("Stage %d has an unrealistic dry-mass-to-propellant ratio." % (i + 1))
		if vacuum_thrust < sea_thrust:
			errors.append("Stage %d vacuum thrust cannot be lower than sea-level thrust." % (i + 1))
		var sea_isp := stage_specific_impulse(stage, false)
		var vacuum_isp := stage_specific_impulse(stage, true)
		if sea_isp < 220.0 or sea_isp > 380.0:
			errors.append("Stage %d sea-level engine efficiency must be 220–380 seconds Isp." % (i + 1))
		if vacuum_isp < 250.0 or vacuum_isp > 465.0:
			errors.append("Stage %d vacuum engine efficiency must be 250–465 seconds Isp." % (i + 1))
		if vacuum_isp < sea_isp or vacuum_isp - sea_isp > 120.0:
			errors.append("Stage %d has an unrealistic sea-level/vacuum efficiency difference." % (i + 1))
		var ignition_mass := stage_ignition_mass(design, i)
		var ignition_thrust := sea_thrust if i == 0 else vacuum_thrust
		var thrust_to_weight := ignition_thrust * engines / maxf(1.0, ignition_mass * G0)
		var burnout_mass := ignition_mass - fuel
		var burnout_twr := ignition_thrust * engines / maxf(1.0, burnout_mass * G0)
		if i == 0 and (thrust_to_weight < 1.1 or thrust_to_weight > 2.5):
			errors.append("First-stage pad TWR must be between 1.10 and 2.50.")
		elif i > 0 and (thrust_to_weight < 0.65 or thrust_to_weight > 3.5):
			errors.append("Stage %d ignition TWR must be between 0.65 and 3.50 to sustain a practical ascent or orbital burn." % (i + 1))
		if burnout_twr > 8.0:
			errors.append("Stage %d burnout acceleration is too high; reduce thrust or increase dry mass." % (i + 1))
	if total_mass > 0.0 and stages.size() >= MIN_STAGES:
		var delta_v := total_delta_v(design)
		if delta_v < MIN_TOTAL_DELTA_V:
			errors.append("Vehicle ideal delta-v is too low for a credible Earth launch (minimum 8.5 km/s).")
		if delta_v > MAX_TOTAL_DELTA_V:
			errors.append("Vehicle ideal delta-v exceeds the 16.5 km/s design limit.")
	return errors
