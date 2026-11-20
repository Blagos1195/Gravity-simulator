extends RefCounted
class_name RocketDesign

const DEFAULT_DESIGN := {
	"name": "Explorer I",
	"payload_mass": 500.0,
	"stages": [
		{
			"name": "FIRST STAGE",
			"dry_mass": 12000.0,
			"fuel_capacity": 300000.0,
			"thrust": 7500000.0,
			"vacuum_thrust": 9000000.0,
			"flow": 2058.0,
			"engine_count": 1
		},
		{
			"name": "UPPER STAGE",
			"dry_mass": 3000.0,
			"fuel_capacity": 80000.0,
			"thrust": 1200000.0,
			"vacuum_thrust": 1500000.0,
			"flow": 300.0,
			"engine_count": 1
		}
	]
}

static func create_default() -> Dictionary:
	return DEFAULT_DESIGN.duplicate(true)

static func total_initial_mass(design: Dictionary) -> float:
	var stages: Array = design.get("stages", [])
	var mass := float(design.get("payload_mass", 0.0))
	for stage in stages:
		mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
	return mass

static func total_delta_v(design: Dictionary) -> float:
	var stages: Array = design.get("stages", [])
	var delta_v := 0.0
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var dry_mass := float(stage.get("dry_mass", 0.0))
		var fuel := float(stage.get("fuel_capacity", 0.0))
		var thrust := float(stage.get("vacuum_thrust", 0.0))
		var engine_count := float(stage.get("engine_count", 1))
		var flow := float(stage.get("flow", 0.0)) * engine_count
		thrust *= engine_count
		var upper_mass := float(design.get("payload_mass", 0.0))
		for j in range(i + 1, stages.size()):
			upper_mass += float(stages[j].get("dry_mass", 0.0)) + float(stages[j].get("fuel_capacity", 0.0))
		var initial_mass := dry_mass + fuel + upper_mass
		var final_mass := dry_mass + upper_mass
		if dry_mass > 0.0 and fuel > 0.0 and flow > 0.0 and thrust > 0.0:
			delta_v += thrust / flow * log(initial_mass / final_mass)
	return delta_v

static func validation_errors(design: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var stages: Array = design.get("stages", [])
	if stages.size() != 2:
		errors.append("The current flight model requires exactly two stages.")
	if float(design.get("payload_mass", 0.0)) <= 0.0:
		errors.append("Payload mass must be greater than zero.")
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		if float(stage.get("dry_mass", 0.0)) <= 0.0:
			errors.append("Stage %d needs positive dry mass." % (i + 1))
		if float(stage.get("fuel_capacity", 0.0)) <= 0.0:
			errors.append("Stage %d needs positive fuel capacity." % (i + 1))
		if float(stage.get("thrust", 0.0)) <= 0.0 or float(stage.get("vacuum_thrust", 0.0)) <= 0.0:
			errors.append("Stage %d needs positive engine thrust." % (i + 1))
		if float(stage.get("flow", 0.0)) <= 0.0:
			errors.append("Stage %d needs positive fuel flow." % (i + 1))
		if int(stage.get("engine_count", 1)) < 1 or int(stage.get("engine_count", 1)) > 8:
			errors.append("Stage %d must have between 1 and 8 engines." % (i + 1))
	return errors
