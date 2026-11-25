extends RefCounted
class_name RocketAssembly

const ContentCatalog = preload("res://scripts/content_catalog.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

static func _catalog() -> Dictionary:
	return ContentCatalog.get_catalog().get("rocket", {}).get("components", {})

static func component_options() -> Array:
	var options: Array = []
	for category in ["tanks", "engines", "decouplers", "structures", "rcs", "docking_ports"]:
		var component_kind: String = str({"rcs": "rcs", "docking_ports": "docking_port"}.get(category, category.trim_suffix("s")))
		for definition in _catalog().get(category, []):
			var option: Dictionary = definition.duplicate(true)
			option["kind"] = component_kind
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
	var rcs_propellant_capacity := 0.0
	var rcs_thrust := 0.0
	var rcs_flow := 0.0
	var rcs_torque := 0.0
	var docking_port_count := 0
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
		rcs_propellant_capacity += maxf(0.0, float(component.get("rcs_propellant_capacity", 0.0))) * copies
		rcs_thrust += maxf(0.0, float(component.get("rcs_thrust", 0.0))) * copies
		rcs_flow += maxf(0.0, float(component.get("rcs_flow", 0.0))) * copies
		rcs_torque += maxf(0.0, float(component.get("rcs_torque", 0.0))) * copies
		if str(component.get("kind", "")) == "docking_port":
			docking_port_count += int(copies)
		if attachment == "stack":
			total_length += maxf(0.0, float(component.get("length_m", 0.0)))
			maximum_radius = maxf(maximum_radius, float(component.get("collision_radius_m", 0.1)))
		elif attachment == "side":
			var mount_index := int(component.get("mount_index", -1))
			side_mount_radii[mount_index] = float(side_mount_radii.get(mount_index, 0.0)) + float(component.get("collision_radius_m", 0.1)) * 1.75
		if str(component.get("kind", "")) == "tank":
			tank_color = component.get("color_rgb", tank_color)
	var widest_side_mount := 0.0
	for mount_radius in side_mount_radii.values():
		widest_side_mount = maxf(widest_side_mount, float(mount_radius))
	maximum_radius += widest_side_mount
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
	configured["rcs_propellant_capacity"] = rcs_propellant_capacity
	configured["rcs_thrust"] = rcs_thrust
	configured["rcs_flow"] = rcs_flow
	configured["rcs_torque"] = rcs_torque
	configured["docking_port_count"] = docking_port_count
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

static func stage_geometry(stage: Dictionary) -> Dictionary:
	var configured := ensure_stage_components(stage)
	var components: Array = configured.get("components", [])
	var stage_length := 0.0
	var core_radius := 0.5
	for component_variant in components:
		if not component_variant is Dictionary:
			continue
		var component: Dictionary = component_variant
		var radius := maxf(0.1, float(component.get("collision_radius_m", 0.5)))
		if str(component.get("attachment", "stack")) == "stack":
			stage_length += maxf(0.1, float(component.get("length_m", 1.0)))
			core_radius = maxf(core_radius, radius)
	if stage_length <= 0.0:
		stage_length = maxf(1.0, float(configured.get("physical_length_m", 1.0)))
	var mount_positions: Dictionary = {}
	var cursor := stage_length * 0.5
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("attachment", "stack")) != "stack":
			continue
		var component_length := maxf(0.1, float(component.get("length_m", 1.0)))
		mount_positions[index] = cursor - component_length * 0.5
		cursor -= component_length
	var component_positions: Dictionary = {}
	var side_mount_offsets: Dictionary = {}
	for index in range(components.size()):
		var component: Dictionary = components[index]
		var attachment := str(component.get("attachment", "stack"))
		var positions: Array[Vector2] = []
		if attachment == "stack":
			positions.append(Vector2(0.0, float(mount_positions.get(index, 0.0))))
		elif attachment in ["side", "radial"]:
			var mount_index := int(component.get("mount_index", -1))
			var component_radius := maxf(0.1, float(component.get("collision_radius_m", 1.0)))
			var offset := float(side_mount_offsets.get(mount_index, core_radius)) + component_radius * 0.9
			side_mount_offsets[mount_index] = offset + component_radius * 0.85
			var y := float(mount_positions.get(mount_index, 0.0))
			var sides: Array = [-1.0, 1.0] if bool(component.get("mirror", true)) else [float(component.get("side", 1))]
			for direction in sides:
				positions.append(Vector2(float(direction) * offset, y))
		component_positions[index] = positions
	var booster_positions: Dictionary = {}
	var booster_lanes: Dictionary = {}
	var boosters: Array = configured.get("boosters", [])
	for index in range(boosters.size()):
		var booster_entry: Variant = boosters[index]
		if not booster_entry is Dictionary or booster_entry.has("source_component_id"):
			continue
		var definition := RocketDesign.booster_definition_for_entry(booster_entry)
		if definition.is_empty():
			continue
		var mount_index := int(booster_entry.get("mount_index", -1))
		var radius := maxf(0.1, float(definition.get("collision_radius_m", 0.8)))
		var offset := float(booster_lanes.get(mount_index, core_radius)) + radius * 1.75
		booster_lanes[mount_index] = offset + radius * 1.7
		var y := float(mount_positions.get(mount_index, 0.0))
		var pair_count := maxi(1, int(definition.get("pair_count", 2)))
		var sides: Array = [-1.0, 1.0] if pair_count == 2 else [float(booster_entry.get("side", 1))]
		var positions: Array[Vector2] = []
		for direction in sides:
			positions.append(Vector2(float(direction) * offset, y))
		booster_positions[index] = positions
	return {
		"stage": configured,
		"length": stage_length,
		"component_positions": component_positions,
		"booster_positions": booster_positions
	}

static func stage_mass_elements(stage: Dictionary, fuel_remaining: float, stage_center_y: float = 0.0, rcs_fuel_fraction: float = 1.0) -> Array[Dictionary]:
	var geometry := stage_geometry(stage)
	var configured: Dictionary = geometry.stage
	var fuel_capacity := RocketDesign.stage_total_fuel_capacity(configured)
	var fuel_fraction := clampf(fuel_remaining / fuel_capacity, 0.0, 1.0) if fuel_capacity > 0.0 else 0.0
	var elements: Array[Dictionary] = []
	var components: Array = configured.get("components", [])
	var component_positions: Dictionary = geometry.component_positions
	for index in range(components.size()):
		var component: Dictionary = components[index]
		var positions: Array = component_positions.get(index, [])
		var mass := maxf(0.0, float(component.get("dry_mass", 0.0))) + maxf(0.0, float(component.get("fuel_capacity", 0.0))) * fuel_fraction + maxf(0.0, float(component.get("rcs_propellant_capacity", 0.0))) * clampf(rcs_fuel_fraction, 0.0, 1.0)
		var length := maxf(0.1, float(component.get("length_m", 1.0)))
		var radius := maxf(0.1, float(component.get("collision_radius_m", 0.5)))
		for position_variant in positions:
			var position: Vector2 = position_variant
			elements.append({
				"mass": mass,
				"position": position + Vector2(0.0, stage_center_y),
				"intrinsic_inertia": mass * (length * length / 12.0 + radius * radius / 4.0)
			})
	var boosters: Array = configured.get("boosters", [])
	var booster_positions: Dictionary = geometry.booster_positions
	for index in range(boosters.size()):
		var booster_entry: Variant = boosters[index]
		if not booster_entry is Dictionary or booster_entry.has("source_component_id"):
			continue
		var definition := RocketDesign.booster_definition_for_entry(booster_entry)
		if definition.is_empty():
			continue
		var positions: Array = booster_positions.get(index, [])
		var mass := maxf(0.0, float(definition.get("dry_mass", 0.0))) + maxf(0.0, float(definition.get("fuel_capacity", 0.0))) * fuel_fraction
		var length := maxf(0.1, float(definition.get("length_m", 12.0)))
		var radius := maxf(0.1, float(definition.get("collision_radius_m", 0.8)))
		for position_variant in positions:
			var position: Vector2 = position_variant
			elements.append({
				"mass": mass,
				"position": position + Vector2(0.0, stage_center_y),
				"intrinsic_inertia": mass * (length * length / 12.0 + radius * radius / 4.0)
			})
	return elements

static func stage_engine_elements(stage: Dictionary, pressure_ratio: float, stage_center_y: float = 0.0) -> Array[Dictionary]:
	var geometry := stage_geometry(stage)
	var configured: Dictionary = geometry.stage
	var elements: Array[Dictionary] = []
	var components: Array = configured.get("components", [])
	var component_positions: Dictionary = geometry.component_positions
	for index in range(components.size()):
		var component: Dictionary = components[index]
		var kind := str(component.get("kind", ""))
		if kind not in ["engine", "radial"]:
			continue
		var positions: Array = component_positions.get(index, [])
		var thrust := lerpf(float(component.get("vacuum_thrust", 0.0)), float(component.get("thrust", 0.0)), clampf(pressure_ratio, 0.0, 1.0))
		if thrust <= 0.0:
			continue
		for position_variant in positions:
			var position: Vector2 = position_variant
			elements.append({
				"position": position + Vector2(0.0, stage_center_y),
				"thrust": thrust,
				"gimballed": kind == "engine"
			})
	var boosters: Array = configured.get("boosters", [])
	var booster_positions: Dictionary = geometry.booster_positions
	for index in range(boosters.size()):
		var booster_entry: Variant = boosters[index]
		if not booster_entry is Dictionary or booster_entry.has("source_component_id"):
			continue
		var definition := RocketDesign.booster_definition_for_entry(booster_entry)
		if definition.is_empty():
			continue
		var thrust := lerpf(float(definition.get("vacuum_thrust", 0.0)), float(definition.get("thrust", 0.0)), clampf(pressure_ratio, 0.0, 1.0))
		if thrust <= 0.0:
			continue
		for position_variant in booster_positions.get(index, []):
			var position: Vector2 = position_variant
			elements.append({
				"position": position + Vector2(0.0, stage_center_y),
				"thrust": thrust,
				"gimballed": false
			})
	return elements

static func stage_rcs_propellant_capacity(stage: Dictionary) -> float:
	return float(ensure_stage_components(stage).get("rcs_propellant_capacity", 0.0))

static func stage_rcs_elements(stage: Dictionary, stage_center_y: float = 0.0) -> Array[Dictionary]:
	var geometry := stage_geometry(stage)
	var configured: Dictionary = geometry.stage
	var components: Array = configured.get("components", [])
	var positions: Dictionary = geometry.component_positions
	var elements: Array[Dictionary] = []
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("kind", "")) != "rcs":
			continue
		for position_variant in positions.get(index, []):
			var position: Vector2 = position_variant
			elements.append({
				"position": position + Vector2(0.0, stage_center_y),
				"thrust": float(component.get("rcs_thrust", 0.0)),
				"flow": float(component.get("rcs_flow", 0.0)),
				"torque": float(component.get("rcs_torque", 0.0))
			})
	return elements

static func stage_docking_ports(stage: Dictionary, stage_center_y: float = 0.0) -> Array[Dictionary]:
	var geometry := stage_geometry(stage)
	var components: Array = geometry.stage.get("components", [])
	var positions: Dictionary = geometry.component_positions
	var ports: Array[Dictionary] = []
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("kind", "")) != "docking_port":
			continue
		for position_variant in positions.get(index, []):
			var position: Vector2 = position_variant + Vector2(0.0, stage_center_y)
			ports.append({
				"position": position,
				"normal": Vector2.UP * float(component.get("port_facing", 1)),
				"component_index": index
			})
	return ports

static func component_summary(stage: Dictionary) -> Dictionary:
	var components: Array = stage.get("components", [])
	var counts := {"tank": 0, "engine": 0, "decoupler": 0, "structure": 0, "rcs": 0, "docking_port": 0}
	for component in components:
		var kind := str(component.get("kind", ""))
		if counts.has(kind):
			counts[kind] += 1
	return counts
