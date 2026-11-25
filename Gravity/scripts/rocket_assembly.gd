extends RefCounted
class_name RocketAssembly

const ContentCatalog = preload("res://scripts/content_catalog.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

static func _catalog() -> Dictionary:
	return ContentCatalog.get_catalog().get("rocket", {}).get("components", {})

static func component_options() -> Array:
	var options: Array = []
	for category in ["tanks", "engines", "decouplers", "structures"]:
		for definition in _catalog().get(category, []):
			var option: Dictionary = definition.duplicate(true)
			option["kind"] = category.trim_suffix("s")
			options.append(option)
	for definition in RocketDesign.booster_options():
		var option: Dictionary = definition.duplicate(true)
		option["kind"] = "radial"
		option["length_m"] = 12.0 * float(option.get("visual_length_factor", 1.0))
		option["collision_radius_m"] = float(option.get("collision_radius_m", 1.0))
		option["color_rgb"] = option.get("visual_color_rgb", [0.72, 0.74, 0.78]).duplicate(true)
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

static func add_component(stage: Dictionary, component_id: String, attachment: String = "stack", mirrored: bool = true, side: int = 1, mount_index: int = -1) -> Dictionary:
	var definition := component_definition(component_id)
	if definition.is_empty() or not ["stack", "side", "radial"].has(attachment):
		return {}
	var configured := ensure_stage_components(stage)
	var components: Array = configured.get("components", []).duplicate(true)
	definition["attachment"] = attachment
	if attachment in ["radial", "side"]:
		definition["mirror"] = mirrored
		definition["side"] = -1 if side < 0 else 1
		definition["mount_index"] = mount_index
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

static func move_component(stage: Dictionary, component_index: int, direction: int) -> Dictionary:
	var configured := ensure_stage_components(stage)
	var components: Array = configured.get("components", []).duplicate(true)
	var destination := component_index + signi(direction)
	if component_index < 0 or component_index >= components.size() or destination < 0 or destination >= components.size():
		return {}
	var component: Variant = components[component_index]
	components.remove_at(component_index)
	components.insert(destination, component)
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
	var side_mount_radii: Dictionary = {}
	var tank_color: Variant = configured.get("visual_color_rgb", [0.43, 0.63, 0.75])
	var radial_boosters: Array = []
	for component in components:
		if not component is Dictionary:
			continue
		if str(component.get("attachment", "stack")) == "radial":
			var radial_definition: Dictionary = component.duplicate(true)
			radial_definition["pair_count"] = 2 if bool(component.get("mirror", true)) else 1
			radial_definition["visual_color_rgb"] = component.get("color_rgb", component.get("visual_color_rgb", [0.72, 0.74, 0.78])).duplicate(true)
			radial_definition["visual_width_factor"] = float(component.get("visual_width_factor", 0.5))
			radial_definition["visual_length_factor"] = float(component.get("visual_length_factor", 1.0))
			radial_definition["source_component_id"] = str(component.get("id", ""))
			radial_boosters.append({"id": str(component.get("id", "")), "definition": radial_definition, "source_component_id": str(component.get("id", "")), "side": int(component.get("side", 1)), "mount_index": int(component.get("mount_index", -1))})
			continue
		var attachment := str(component.get("attachment", "stack"))
		var copies := 2.0 if attachment == "side" and bool(component.get("mirror", true)) else 1.0
		dry_mass += maxf(0.0, float(component.get("dry_mass", 0.0))) * copies
		fuel_capacity += maxf(0.0, float(component.get("fuel_capacity", 0.0))) * copies
		thrust += maxf(0.0, float(component.get("thrust", 0.0))) * copies
		vacuum_thrust += maxf(0.0, float(component.get("vacuum_thrust", 0.0))) * copies
		flow += maxf(0.0, float(component.get("flow", 0.0))) * copies
		if attachment == "stack":
			total_length += maxf(0.0, float(component.get("length_m", 0.0)))
			maximum_radius = maxf(maximum_radius, float(component.get("collision_radius_m", 0.1)))
		elif attachment == "side":
			var mount_index := int(component.get("mount_index", -1))
			side_mount_radii[mount_index] = float(side_mount_radii.get(mount_index, 0.0)) + float(component.get("collision_radius_m", 0.1)) * 0.9
		if str(component.get("kind", "")) == "tank":
			tank_color = component.get("color_rgb", tank_color)
	for mount_radius in side_mount_radii.values():
		maximum_radius = maxf(maximum_radius, maximum_radius + float(mount_radius))
	var boosters: Array = []
	for existing in configured.get("boosters", []):
		if not (existing is Dictionary and existing.has("source_component_id")):
			boosters.append(existing.duplicate(true) if existing is Dictionary else existing)
	boosters.append_array(radial_boosters)
	configured["boosters"] = boosters
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
	configured["visual_length_factor"] = clampf(float(stage.get("visual_length_factor", 1.0)) * maxf(1.0, total_length) / original_length, 0.35, 4.0)
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
