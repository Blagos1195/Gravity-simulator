extends RefCounted
class_name RocketDesign

const G0 := 9.80665
const MIN_STAGES := 2
const MAX_STAGES := 8
const MAX_TOTAL_MASS := 5000000.0
const MIN_TOTAL_DELTA_V := 8500.0
const MAX_TOTAL_DELTA_V := 16500.0

const DEFAULT_DESIGN := {
	"name": "Explorer I",
	"payload_mass": 500.0,
	"stages": [
		{
			"name": "FIRST STAGE",
			"dry_mass": 30000.0,
			"fuel_capacity": 300000.0,
			"thrust": 5000000.0,
			"vacuum_thrust": 6000000.0,
			"flow": 1500.0,
			"engine_count": 1
		},
		{
			"name": "UPPER STAGE",
			"dry_mass": 4000.0,
			"fuel_capacity": 30000.0,
			"thrust": 200000.0,
			"vacuum_thrust": 250000.0,
			"flow": 63.3,
			"engine_count": 1
		}
	]
}


const PRESET_DESIGNS := {
	"SMALL_SAT": {
		"name": "Scout · Small Satellite",
		"payload_mass": 150.0,
		"stages": [
			{"name": "BOOSTER", "dry_mass": 3500.0, "fuel_capacity": 35000.0, "thrust": 750000.0, "vacuum_thrust": 850000.0, "flow": 250.0, "engine_count": 1},
			{"name": "UPPER STAGE", "dry_mass": 1200.0, "fuel_capacity": 9000.0, "thrust": 180000.0, "vacuum_thrust": 220000.0, "flow": 65.0, "engine_count": 1},
			{"name": "ORBITAL KICK STAGE", "dry_mass": 1300.0, "fuel_capacity": 3500.0, "thrust": 100000.0, "vacuum_thrust": 110000.0, "flow": 30.0, "engine_count": 1}
		]
	},
	"LEO_CARGO": {
		"name": "Freighter · LEO Cargo",
		"payload_mass": 8000.0,
		"stages": [
			{"name": "CORE BOOSTER", "dry_mass": 22000.0, "fuel_capacity": 240000.0, "thrust": 5000000.0, "vacuum_thrust": 5700000.0, "flow": 1650.0, "engine_count": 1},
			{"name": "UPPER STAGE", "dry_mass": 5500.0, "fuel_capacity": 65000.0, "thrust": 900000.0, "vacuum_thrust": 1100000.0, "flow": 320.0, "engine_count": 1},
			{"name": "ORBITAL INSERTION STAGE", "dry_mass": 1800.0, "fuel_capacity": 15000.0, "thrust": 220000.0, "vacuum_thrust": 260000.0, "flow": 75.0, "engine_count": 1}
		]
	},
	"CREW_ORBIT": {
		"name": "Pioneer · Crewed Orbital",
		"payload_mass": 6500.0,
		"stages": [
			{"name": "CORE BOOSTER", "dry_mass": 24000.0, "fuel_capacity": 250000.0, "thrust": 5600000.0, "vacuum_thrust": 6400000.0, "flow": 1800.0, "engine_count": 1},
			{"name": "UPPER STAGE", "dry_mass": 6000.0, "fuel_capacity": 75000.0, "thrust": 1100000.0, "vacuum_thrust": 1300000.0, "flow": 370.0, "engine_count": 1},
			{"name": "ORBITAL INSERTION STAGE", "dry_mass": 2200.0, "fuel_capacity": 18000.0, "thrust": 240000.0, "vacuum_thrust": 290000.0, "flow": 82.0, "engine_count": 1}
		]
	},
	"LUNAR_CARGO": {
		"name": "Pathfinder · Lunar Cargo",
		"payload_mass": 12000.0,
		"stages": [
			{"name": "HEAVY CORE", "dry_mass": 30000.0, "fuel_capacity": 540000.0, "thrust": 10080000.0, "vacuum_thrust": 10800000.0, "flow": 3000.0, "engine_count": 1},
			{"name": "TRANSFER STAGE", "dry_mass": 6000.0, "fuel_capacity": 108000.0, "thrust": 1230000.0, "vacuum_thrust": 1500000.0, "flow": 390.0, "engine_count": 1},
			{"name": "INJECTION STAGE", "dry_mass": 2000.0, "fuel_capacity": 36000.0, "thrust": 400000.0, "vacuum_thrust": 460000.0, "flow": 110.0, "engine_count": 1}
		]
	},
	"DEEP_SPACE": {
		"name": "Odyssey · Deep-Space Probe",
		"payload_mass": 1800.0,
		"stages": [
			{"name": "CORE BOOSTER", "dry_mass": 28000.0, "fuel_capacity": 300000.0, "thrust": 6200000.0, "vacuum_thrust": 7000000.0, "flow": 1950.0, "engine_count": 1},
			{"name": "UPPER STAGE", "dry_mass": 7000.0, "fuel_capacity": 80000.0, "thrust": 1200000.0, "vacuum_thrust": 1450000.0, "flow": 410.0, "engine_count": 1},
			{"name": "TRANSFER STAGE", "dry_mass": 2500.0, "fuel_capacity": 24000.0, "thrust": 250000.0, "vacuum_thrust": 310000.0, "flow": 87.0, "engine_count": 1},
			{"name": "DEEP-SPACE KICK STAGE", "dry_mass": 700.0, "fuel_capacity": 4500.0, "thrust": 100000.0, "vacuum_thrust": 120000.0, "flow": 34.0, "engine_count": 1}
		]
	}
}

const PRESET_DESCRIPTIONS := {
	"SMALL_SAT": "Light payloads and small scientific satellites. Optimised for low Earth orbit.",
	"LEO_CARGO": "Heavy uncrewed cargo and station logistics. A practical general-purpose orbital launcher.",
	"CREW_ORBIT": "Crew capsule and crew-support payloads. Balanced for reliable low Earth orbit insertion.",
	"LUNAR_CARGO": "Large robotic payloads and lunar transfer missions. Includes a dedicated injection stage.",
	"DEEP_SPACE": "Smaller probes with extra departure energy for interplanetary missions. Payload capacity is deliberately lower."
}

static func preset_options() -> Array:
	return [
		{"id": "SMALL_SAT", "label": "Scout · Small satellite / LEO"},
		{"id": "LEO_CARGO", "label": "Freighter · LEO cargo"},
		{"id": "CREW_ORBIT", "label": "Pioneer · Crewed orbital"},
		{"id": "LUNAR_CARGO", "label": "Pathfinder · Lunar cargo"},
		{"id": "DEEP_SPACE", "label": "Odyssey · Deep-space probe"}
	]

static func create_preset(preset_id: String) -> Dictionary:
	if not PRESET_DESIGNS.has(preset_id):
		return create_default()
	return PRESET_DESIGNS[preset_id].duplicate(true)

static func preset_description(preset_id: String) -> String:
	return str(PRESET_DESCRIPTIONS.get(preset_id, "Select a mission profile to load its vehicle."))

static func create_default() -> Dictionary:
	return DEFAULT_DESIGN.duplicate(true)

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
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var fuel := float(stage.get("fuel_capacity", 0.0))
		var flow := float(stage.get("flow", 0.0))
		var thrust := float(stage.get("vacuum_thrust", 0.0))
		var initial_mass := stage_ignition_mass(design, i)
		var final_mass := initial_mass - fuel
		if fuel > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > 0.0:
			delta_v += thrust / flow * log(initial_mass / final_mass)
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
