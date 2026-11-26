extends RefCounted
class_name RocketAssembly

const ContentCatalog = preload("res://scripts/content_catalog.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const ResourceNetwork = preload("res://scripts/resource_network.gd")

static func _catalog() -> Dictionary:
	return ContentCatalog.get_catalog().get("rocket", {}).get("components", {})

static func component_options() -> Array:
	var options: Array = []
	for category in ["tanks", "engines", "decouplers", "structures", "rcs", "docking_ports", "power", "payloads"]:
		var component_kind: String = str({"rcs": "rcs", "docking_ports": "docking_port", "power": "power", "payloads": "payload"}.get(category, category.trim_suffix("s")))
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

static func physical_payload_profile(stages: Array) -> Dictionary:
	var profile_keys := ["visual_type", "visual_width_factor", "visual_height_factor", "visual_color_rgb", "telescope_range_au", "satellite_role", "revenue_per_day", "operating_cost_per_day", "operational_lifetime_days"]
	for stage in stages:
		for component in stage.get("components", []):
			if str(component.get("kind", "")) != "payload":
				continue
			var profile := {"part_id": str(component.get("id", "")), "physical_payload_component": true}
			for key in profile_keys:
				if component.has(key):
					profile[key] = component[key].duplicate(true) if component[key] is Array or component[key] is Dictionary else component[key]
			return profile
	return {}

static func ensure_stage_components(stage: Dictionary) -> Dictionary:
	var configured := stage.duplicate(true)
	var existing: Variant = configured.get("components", [])
	if bool(configured.get("component_assembly", false)):
		return compile_stage(configured, existing if existing is Array else [])
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
	if definition.is_empty() or not ["stack", "side", "radial", "free"].has(attachment):
		return {}
	var configured := ensure_stage_components(stage)
	var components: Array = configured.get("components", []).duplicate(true)
	definition["attachment"] = attachment
	definition["rotation_deg"] = float(definition.get("rotation_deg", 0.0))
	definition["part_uid"] = "part_%d_%d" % [Time.get_ticks_usec(), randi()]
	if str(definition.get("kind", "")) in ["engine", "radial"]:
		definition["engine_enabled"] = true
	if str(definition.get("kind", "")) == "tank":
		definition["fuel_supply_enabled"] = true
	if attachment in ["radial", "side"]:
		definition["mirror"] = mirrored
		definition["side"] = -1 if side < 0 else 1
		definition["mount_index"] = mount_index
	elif attachment == "free":
		definition["position_m"] = [0.0, 0.0]
	components.append(definition)
	configured["components"] = components
	return compile_stage(configured, components)


static func add_preset_hardware(source_design: Dictionary) -> Dictionary:
	var design := source_design.duplicate(true)
	var stages: Array = design.get("stages", []).duplicate(true)
	for stage_index in range(stages.size()):
		var stage := ensure_stage_components(stages[stage_index])
		var components: Array = stage.get("components", []).duplicate(true)
		components = components.filter(func(component: Dictionary) -> bool:
			return not ["connector", "payload_interface_lower", "payload_interface_upper"].has(str(component.get("preset_hardware_role", "")))
		)
		stage = compile_stage(stage, components)
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			component["staging_stage"] = stage_index * 2
			components[component_index] = component
		stage = compile_stage(stage, components)
		components = stage.get("components", []).duplicate(true)
		var has_rcs := false
		for component in components:
			if str(component.get("preset_hardware_role", "")) == "rcs":
				has_rcs = true
				break
		if not has_rcs:
			stage = add_component(stage, "rcs_thruster_block", "side", true, 1, 0)
			components = stage.get("components", []).duplicate(true)
			var rcs: Dictionary = components.back()
			rcs["preset_hardware_role"] = "rcs"
			rcs["staging_action"] = "activate_rcs"
			rcs["staging_stage"] = stage_index * 2
			components[components.size() - 1] = rcs
			stage = compile_stage(stage, components)
		if stage_index < stages.size() - 1:
			var has_separator := false
			for component in stage.get("components", []):
				if str(component.get("preset_hardware_role", "")) == "separator":
					has_separator = true
					break
			if not has_separator:
				stage = add_component(stage, "stack_decoupler")
				components = stage.get("components", []).duplicate(true)
				var separator: Dictionary = components.back()
				separator["preset_hardware_role"] = "separator"
				separator["staging_action"] = "separate"
				separator["staging_stage"] = stage_index * 2 + 1
				separator["staging_action_disabled"] = false
				components.pop_back()
				components.insert(0, separator)
				stage = compile_stage(stage, components)
		if stage_index == stages.size() - 1:
			var has_top_ports := 0
			for component in stage.get("components", []):
				if str(component.get("preset_hardware_role", "")).begins_with("top_docking_port_"):
					has_top_ports += 1
			if has_top_ports == 0:
				var stack_length := 0.0
				var parent_uid := ""
				for component in stage.get("components", []):
					if str(component.get("attachment", "stack")) != "stack":
						continue
					stack_length += maxf(0.1, float(component.get("length_m", 1.0)))
					if parent_uid.is_empty():
						parent_uid = str(component.get("part_uid", ""))
				var port_definition := component_definition("standard_docking_port")
				var port_length := float(port_definition.get("length_m", 1.4))
				var port_radius := float(port_definition.get("collision_radius_m", 0.85))
				var port_y := stack_length * 0.5 + port_radius
				for port_index in range(2):
					var port := port_definition.duplicate(true)
					port["attachment"] = "free"
					port["part_uid"] = "preset_top_port_%d_%d" % [stage_index, port_index]
					port["position_m"] = [-port_length * 0.5 if port_index == 0 else port_length * 0.5, port_y]
					port["rotation_deg"] = 90.0 if port_index == 0 else -90.0
					port["structural_parent_uid"] = parent_uid
					port["structural_parent_node_id"] = "top"
					port["preset_hardware_role"] = "top_docking_port_left" if port_index == 0 else "top_docking_port_right"
					port["port_facing"] = 1
					port["staging_stage"] = (stages.size() - 1) * 2
					components = stage.get("components", []).duplicate(true)
					components.append(port)
					stage = compile_stage(stage, components)
		components = stage.get("components", []).duplicate(true)
		var tank_mount_index := 0
		for component_index in range(components.size()):
			if str(components[component_index].get("kind", "")) == "tank":
				tank_mount_index = component_index
				break
		var updated_mounts := false
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			if str(component.get("preset_hardware_role", "")) != "rcs":
				continue
			component["mount_index"] = tank_mount_index
			components[component_index] = component
			updated_mounts = true
		if updated_mounts:
			stage = compile_stage(stage, components)
		stages[stage_index] = stage
	design["stages"] = stages
	var action_stage_labels: Array = []
	for stage_index in range(stages.size()):
		action_stage_labels.append("Stage %d: Ignite" % (stage_index + 1))
		if stage_index < stages.size() - 1:
			var boundary_label := "Separate"
			action_stage_labels.append("Stage %d: %s" % [stage_index + 1, boundary_label])
	design["staging_stage_labels"] = action_stage_labels
	design["staging_stage_count"] = action_stage_labels.size()
	return design

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
	components = components.duplicate(true)
	for component_index in range(components.size()):
		var component: Dictionary = components[component_index]
		if str(component.get("part_uid", "")).is_empty():
			component["part_uid"] = "part_%d_%d" % [Time.get_ticks_usec(), component_index]
		components[component_index] = component
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
	var resource_capacities: Dictionary = {}
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
		var component_kind := str(component.get("kind", ""))
		if component_kind in ["engine", "radial"] and bool(component.get("engine_enabled", true)):
			if str(component.get("fuel_type", "liquid_propellant")) == "liquid_propellant":
				flow += maxf(0.0, float(component.get("flow", 0.0))) * copies
			thrust += maxf(0.0, float(component.get("thrust", 0.0))) * copies
			vacuum_thrust += maxf(0.0, float(component.get("vacuum_thrust", 0.0))) * copies
			if bool(component.get("solid_motor", false)):
				configured["has_solid_motor"] = true
		configured["electric_draw_w"] = float(configured.get("electric_draw_w", 0.0)) + maxf(0.0, float(component.get("electric_draw_w", 0.0))) * copies
		configured["electric_generation_w"] = float(configured.get("electric_generation_w", 0.0)) + maxf(0.0, float(component.get("power_generation_w", 0.0))) * copies
		rcs_propellant_capacity += maxf(0.0, float(component.get("rcs_propellant_capacity", 0.0))) * copies
		if component_kind == "rcs" and bool(component.get("rcs_enabled", true)):
			rcs_thrust += maxf(0.0, float(component.get("rcs_thrust", 0.0))) * copies
			rcs_flow += maxf(0.0, float(component.get("rcs_flow", 0.0))) * copies
			rcs_torque += maxf(0.0, float(component.get("rcs_torque", 0.0))) * copies
		var component_resources := ResourceNetwork.component_capacities(component)
		for resource in component_resources:
			resource_capacities[resource] = float(resource_capacities.get(resource, 0.0)) + float(component_resources[resource]) * copies
		if str(component.get("kind", "")) == "docking_port":
			docking_port_count += int(copies)
		if attachment == "stack":
			total_length += maxf(0.0, float(component.get("length_m", 0.0)))
			maximum_radius = maxf(maximum_radius, float(component.get("collision_radius_m", 0.1)))
		elif attachment == "side":
			var mount_index := int(component.get("mount_index", -1))
			side_mount_radii[mount_index] = float(side_mount_radii.get(mount_index, 0.0)) + float(component.get("collision_radius_m", 0.1)) * 1.75
		elif attachment == "free":
			var free_position: Variant = component.get("position_m", [0.0, 0.0])
			if free_position is Array and free_position.size() >= 2:
				total_length = maxf(total_length, absf(float(free_position[1])) * 2.0 + float(component.get("length_m", 1.0)))
				maximum_radius = maxf(maximum_radius, absf(float(free_position[0])) + float(component.get("collision_radius_m", 0.1)))
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
	configured["resource_capacities"] = resource_capacities
	configured["tank_states"] = ResourceNetwork.create_tank_states(components)
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
	var stack_length := 0.0
	var core_radius := 0.5
	for component_variant in components:
		if not component_variant is Dictionary:
			continue
		var component: Dictionary = component_variant
		var radius := maxf(0.1, float(component.get("collision_radius_m", 0.5)))
		var attachment := str(component.get("attachment", "stack"))
		if attachment == "stack":
			stack_length += maxf(0.1, float(component.get("length_m", 1.0)))
			core_radius = maxf(core_radius, radius)
		elif attachment == "free":
			var position_data: Variant = component.get("position_m", [0.0, 0.0])
			if position_data is Array and position_data.size() >= 2:
				stage_length = maxf(stage_length, absf(float(position_data[1])) * 2.0 + maxf(0.1, float(component.get("length_m", 1.0))))
	stage_length = maxf(stage_length, stack_length)
	if stage_length <= 0.0:
		stage_length = maxf(1.0, float(configured.get("physical_length_m", 1.0)))
	var mount_positions: Dictionary = {}
	var cursor := stack_length * 0.5
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
		elif attachment == "free":
			var position_data: Variant = component.get("position_m", [0.0, 0.0])
			if position_data is Array and position_data.size() >= 2:
				positions.append(Vector2(float(position_data[0]), float(position_data[1])))
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
		if thrust <= 0.0 or not bool(component.get("engine_enabled", true)):
			continue
		var direction := Vector2.UP.rotated(deg_to_rad(float(component.get("rotation_deg", 0.0))))
		var fuel_type := str(component.get("fuel_type", "liquid_propellant"))
		if bool(component.get("solid_motor", false)) and not bool(component.get("ignited", false)):
			continue
		for position_variant in positions:
			var position: Vector2 = position_variant
			elements.append({
				"position": position + Vector2(0.0, stage_center_y),
				"direction": direction,
				"thrust": thrust,
				"flow": maxf(0.0, float(component.get("flow", 0.0))),
				"fuel_type": fuel_type,
				"electric_draw_w": maxf(0.0, float(component.get("electric_draw_w", 0.0))),
				"solid_motor": bool(component.get("solid_motor", false)),
				"gimballed": kind == "engine" and not bool(component.get("solid_motor", false)),
				"part_uid": str(component.get("part_uid", component.get("id", "")))
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
	var jet_layout := [
		[Vector2(0.0, -1.0), Vector2.RIGHT],
		[Vector2(0.0, 1.0), Vector2.RIGHT],
		[Vector2(0.0, -1.0), Vector2.LEFT],
		[Vector2(0.0, 1.0), Vector2.LEFT],
		[Vector2(-1.0, 0.0), Vector2.UP],
		[Vector2(1.0, 0.0), Vector2.UP],
		[Vector2(-1.0, 0.0), Vector2.DOWN],
		[Vector2(1.0, 0.0), Vector2.DOWN]
	]
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("kind", "")) != "rcs" or not bool(component.get("rcs_enabled", true)):
			continue
		var angle := deg_to_rad(float(component.get("rotation_deg", 0.0)))
		var radius := maxf(0.1, float(component.get("collision_radius_m", 0.65)) * 0.5)
		var total_thrust := maxf(0.0, float(component.get("rcs_thrust", 0.0)))
		var total_flow := maxf(0.0, float(component.get("rcs_flow", 0.0)))
		for position_variant in positions.get(index, []):
			var component_position: Vector2 = position_variant
			for jet_index in range(jet_layout.size()):
				var spec: Array = jet_layout[jet_index]
				var offset: Vector2 = Vector2(spec[0]) * radius
				var direction: Vector2 = Vector2(spec[1]).rotated(angle).normalized()
				elements.append({
					"position": component_position + offset.rotated(angle) + Vector2(0.0, stage_center_y),
					"direction": direction,
					"thrust": total_thrust / 2.0,
					"flow": total_flow / 2.0,
					"part_uid": str(component.get("part_uid", component.get("id", ""))),
					"jet_index": jet_index
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
			var normal := Vector2.UP.rotated(deg_to_rad(float(component.get("rotation_deg", 0.0)))) * float(component.get("port_facing", 1))
			var position: Vector2 = position_variant + normal * maxf(0.0, float(component.get("length_m", 0.0))) * 0.5 + Vector2(0.0, stage_center_y)
			ports.append({
				"position": position,
				"normal": normal,
				"component_index": index,
				"part_uid": str(component.get("part_uid", component.get("id", "")))
			})
	return ports

static func docking_module_boundaries(stages: Array) -> Dictionary:
	var geometries: Array[Dictionary] = []
	var total_length := 0.0
	for stage in stages:
		var geometry := stage_geometry(stage)
		geometries.append(geometry)
		total_length += float(geometry.get("length", 1.0))
	var centers: Array[float] = []
	var cursor := -total_length * 0.5
	for geometry in geometries:
		var stage_length := float(geometry.get("length", 1.0))
		centers.append(cursor + stage_length * 0.5)
		cursor += stage_length
	var boundaries: Dictionary = {}
	for upper_index in range(1, stages.size()):
		var lower_ports := stage_docking_ports(stages[upper_index - 1], centers[upper_index - 1])
		var upper_ports := stage_docking_ports(stages[upper_index], centers[upper_index])
		for lower_port in lower_ports:
			for upper_port in upper_ports:
				var lower_normal: Vector2 = lower_port.normal
				var upper_normal: Vector2 = upper_port.normal
				if lower_normal.dot(upper_normal) > -0.94:
					continue
				var lower_position: Vector2 = lower_port.position
				var upper_position: Vector2 = upper_port.position
				if lower_position.distance_to(upper_position) > 3.0:
					continue
				boundaries[upper_index] = {
					"lower_part_uid": str(lower_port.get("part_uid", "")),
					"upper_part_uid": str(upper_port.get("part_uid", "")),
					"offset": lower_position - upper_position,
					"separation_direction": -upper_normal.normalized()
				}
				break
			if boundaries.has(upper_index):
				break
	return boundaries

static func component_group_id(component: Dictionary) -> String:
	return str(component.get("subassembly_id", "main")).strip_edges() if not str(component.get("subassembly_id", "main")).strip_edges().is_empty() else "main"

static func docking_component_group_boundaries(stage: Dictionary) -> Dictionary:
	var ports := stage_docking_ports(stage)
	var components: Array = stage.get("components", [])
	var boundaries: Dictionary = {}
	for first_index in range(ports.size()):
		var first: Dictionary = ports[first_index]
		var first_component: Dictionary = components[int(first.get("component_index", -1))]
		for second_index in range(first_index + 1, ports.size()):
			var second: Dictionary = ports[second_index]
			var second_component: Dictionary = components[int(second.get("component_index", -1))]
			var first_group := component_group_id(first_component)
			var second_group := component_group_id(second_component)
			if first_group == second_group:
				continue
			if Vector2(first.normal).dot(Vector2(second.normal)) > -0.94:
				continue
			if Vector2(first.position).distance_to(Vector2(second.position)) > 3.0:
				continue
			var upper_port: Dictionary = first if float(first.position.y) > float(second.position.y) else second
			var upper_component: Dictionary = first_component if upper_port == first else second_component
			boundaries[str(upper_port.get("part_uid", ""))] = {
				"part_uid": str(upper_port.get("part_uid", "")),
				"subassembly_id": component_group_id(upper_component),
				"offset": Vector2(upper_port.position),
				"separation_direction": -Vector2(upper_port.normal).normalized()
			}
	return boundaries

static func split_stage_by_group(stage: Dictionary, group_id: String) -> Dictionary:
	var configured := ensure_stage_components(stage)
	var selected: Array = []
	var retained: Array = []
	for component in configured.get("components", []):
		if component_group_id(component) == group_id:
			selected.append(component.duplicate(true))
		else:
			retained.append(component.duplicate(true))
	if selected.is_empty():
		return {}
	var result := {"released": compile_stage(configured, selected)}
	if not retained.is_empty():
		result["retained"] = compile_stage(configured, retained)
	return result

static func component_summary(stage: Dictionary) -> Dictionary:
	var components: Array = stage.get("components", [])
	var counts := {"tank": 0, "engine": 0, "decoupler": 0, "structure": 0, "rcs": 0, "docking_port": 0}
	for component in components:
		var kind := str(component.get("kind", ""))
		if counts.has(kind):
			counts[kind] += 1
	return counts
