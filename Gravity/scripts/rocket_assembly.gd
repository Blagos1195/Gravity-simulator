extends RefCounted
class_name RocketAssembly

const ContentCatalog = preload("res://scripts/content_catalog.gd")

static func _catalog() -> Dictionary:
	return ContentCatalog.get_catalog().get("rocket", {}).get("components", {})

static func component_options() -> Array:
	var options: Array = []
	for category in ["tanks", "engines", "decouplers", "structures"]:
		for definition in _catalog().get(category, []):
			var option: Dictionary = definition.duplicate(true)
			option["kind"] = category.trim_suffix("s")
			options.append(option)
	return options

static func component_definition(component_id: String) -> Dictionary:
	for option in component_options():
		if str(option.get("id", "")) == component_id:
			return option
	return {}

static func ensure_stage_components(stage: Dictionary) -> Dictionary:
	var configured := stage.duplicate(true)
	var existing: Variant = configured.get("components", [])
	if existing is Array and not existing.is_empty():
		return compile_stage(configured, existing)
	var length := maxf(6.0, float(configured.get("physical_length_m", 18.0)))
	var radius := maxf(0.5, float(configured.get("collision_radius_m", 1.5)))
	var dry_mass := maxf(1.0, float(configured.get("dry_mass", 1.0)))
	configured["components"] = [
		{
			"id": "legacy_tank",
			"label": "Existing tank",
			"kind": "tank",
			"dry_mass": dry_mass * 0.72,
			"fuel_capacity": maxf(0.0, float(configured.get("fuel_capacity", 0.0))),
			"length_m": length * 0.78,
			"collision_radius_m": radius,
			"color_rgb": configured.get("visual_color_rgb", [0.43, 0.63, 0.75]).duplicate(true)
		},
		{
			"id": "legacy_engine",
			"label": "Existing engine",
			"kind": "engine",
			"dry_mass": dry_mass * 0.28,
			"thrust": maxf(0.0, float(configured.get("thrust", 0.0))) * float(configured.get("engine_count", 1)),
			"vacuum_thrust": maxf(0.0, float(configured.get("vacuum_thrust", 0.0))) * float(configured.get("engine_count", 1)),
			"flow": maxf(0.0, float(configured.get("flow", 0.0))) * float(configured.get("engine_count", 1)),
			"length_m": length * 0.22,
			"collision_radius_m": radius * 0.82,
			"color_rgb": [0.58, 0.62, 0.68]
		}
	]
	return compile_stage(configured, configured["components"])

static func add_component(stage: Dictionary, component_id: String) -> Dictionary:
	var definition := component_definition(component_id)
	if definition.is_empty():
		return {}
	var configured := ensure_stage_components(stage)
	var components: Array = configured.get("components", []).duplicate(true)
	definition.erase("kind")
	components.append(definition)
	configured["components"] = components
	return compile_stage(configured, components)

static func remove_component(stage: Dictionary, component_index: int) -> Dictionary:
	var configured := ensure_stage_components(stage)
	var components: Array = configured.get("components", []).duplicate(true)
	if component_index < 0 or component_index >= components.size():
		return {}
	components.remove_at(component_index)
	configured["components"] = components
	return compile_stage(configured, components)

static func compile_stage(stage: Dictionary, components: Array) -> Dictionary:
	var configured := stage.duplicate(true)
	var dry_mass := 0.0
	var fuel_capacity := 0.0
	var thrust := 0.0
	var vacuum_thrust := 0.0
	var flow := 0.0
	var total_length := 0.0
	var maximum_radius := 0.1
	var tank_color: Variant = configured.get("visual_color_rgb", [0.43, 0.63, 0.75])
	for component in components:
		if not component is Dictionary:
			continue
		dry_mass += maxf(0.0, float(component.get("dry_mass", 0.0)))
		fuel_capacity += maxf(0.0, float(component.get("fuel_capacity", 0.0)))
		thrust += maxf(0.0, float(component.get("thrust", 0.0)))
		vacuum_thrust += maxf(0.0, float(component.get("vacuum_thrust", 0.0)))
		flow += maxf(0.0, float(component.get("flow", 0.0)))
		total_length += maxf(0.0, float(component.get("length_m", 0.0)))
		maximum_radius = maxf(maximum_radius, float(component.get("collision_radius_m", 0.1)))
		if str(component.get("kind", "")) == "tank":
			tank_color = component.get("color_rgb", tank_color)
	configured["components"] = components.duplicate(true)
	configured["component_assembly"] = true
	configured["dry_mass"] = dry_mass
	configured["fuel_capacity"] = fuel_capacity
	configured["thrust"] = thrust
	configured["vacuum_thrust"] = vacuum_thrust
	configured["flow"] = flow
	configured["engine_count"] = 1
	configured["physical_length_m"] = maxf(1.0, total_length)
	configured["collision_radius_m"] = maximum_radius
	var original_length := maxf(1.0, float(stage.get("physical_length_m", total_length)))
	var original_radius := maxf(0.1, float(stage.get("collision_radius_m", maximum_radius)))
	configured["visual_length_factor"] = clampf(float(stage.get("visual_length_factor", 1.0)) * total_length / original_length, 0.35, 4.0)
	configured["visual_diameter_factor"] = clampf(float(stage.get("visual_diameter_factor", 1.0)) * maximum_radius / original_radius, 0.35, 4.0)
	if tank_color is Array and tank_color.size() == 3:
		configured["visual_color_rgb"] = tank_color.duplicate(true)
	return configured

static func component_summary(stage: Dictionary) -> Dictionary:
	var components: Array = stage.get("components", [])
	var counts := {"tank": 0, "engine": 0, "decoupler": 0, "structure": 0}
	for component in components:
		var kind := str(component.get("kind", ""))
		if counts.has(kind):
			counts[kind] += 1
	return counts
