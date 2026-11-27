extends Control

signal stage_separated(stage_data: Dictionary)
signal staging_changed
signal staging_stage_requested
signal part_selected(part_uid: String)

const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")
const StagingSystem = preload("res://scripts/staging_system.gd")
const ResourceNetwork = preload("res://scripts/resource_network.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
static var G := PlanetarySystem.G
static var EARTH_MASS := PlanetarySystem.EARTH_MASS
static var EARTH_RADIUS := PlanetarySystem.EARTH_RADIUS
const DRAG_AREA := 0.45
const LIFT_AREA := 1.8
static var EARTH_ROTATION_RATE := PlanetarySystem.EARTH_ROTATION_RATE
const MAX_PHYSICS_BUDGET_USEC := 6000
const MAX_PHYSICS_STEPS_PER_FRAME := 4000

var rocket_stages: Array = []
var stage_fuel_remaining: Array[float] = []
var payload_mass := 500.0
var payload_type := "probe"
var payload_visual: Dictionary = {}
var payload_subassembly_id := "main"
var vehicle_name := "Vehicle 1"
var is_debris := false
var input_enabled := true
var docked_mass := 0.0
var docked_visuals: Array[Dictionary] = []

var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var infinite_weightless_fuel := false
var simulate_belt_collisions := false
var paused := false
var launch_design: Dictionary = {}
var sim_time := 0.0
var launch_time := 0.0
var time_warp := 1.0
var simulation_time_backlog := 0.0
var ephemeris_cache_time := -INF
var ephemeris_cache: Dictionary = {}
var ephemeris_output_cache_time := -INF
var ephemeris_output_cache: Dictionary = {}
var rocket_position_precise := PackedFloat64Array([0.0, -EARTH_RADIUS - 0.5])
var _rocket_position_display := Vector2(0.0, -EARTH_RADIUS - 0.5)
var rocket_position: Vector2:
	get:
		return _rocket_position_display
	set(value):
		_rocket_position_display = value
		rocket_position_precise = PackedFloat64Array([value.x, value.y])
var velocity := Vector2(EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0)
var rotation_angle := 0.0
var angular_velocity := 0.0
var fuel := 300000.0
var rcs_propellant_remaining := 0.0
var rcs_rotation_input := 0.0
var rcs_rotation_scale := 1.0
var infinite_fuel_stage_remaining := 300000.0
var stage_index := 0
var staging_plan: Array = []
var action_stage_index := 0
var staging_part_states: Dictionary = {}
var resource_tanks: Array = []
var resource_inventory_external := false
var docked_rcs_propellant: Dictionary = {}
var discarded_stage_mass := 0.0
var discarded_propellant_mass := 0.0
var throttle := 0.0
var gimbal_angle := 0.0
var gimbal_trim_center_of_mass := Vector2(INF, INF)
var gimbal_trim_stage_index := -1
var gimbal_trim_last_time := -INF
var guidance_enabled := false
var autopilot_enabled := false
var autopilot_target_altitude := 200000.0
var autopilot_target_mode := "ORBIT"
var autopilot_planet_index := -1
var autopilot_burn_remaining := 0.0
var autopilot_apsis_correction_armed := true
var autopilot_apsis_correction_angle := 0.0
var autopilot_throttle := 0.0
var autopilot_transfer_start_time := -1.0
var autopilot_transfer_duration := 0.0
var autopilot_precomputed_transfer_plan: Dictionary = {}
var autopilot_transfer_corrections := 0
var autopilot_speed_priority := 0.35
var autopilot_safety_margin := 0.10
var autopilot_transfer_direction := 1.0
var autopilot_arrival_burn_vector := Vector2.ZERO
var autopilot_burn_direction := Vector2.ZERO
var autopilot_route_nodes: Array[Dictionary] = []
var autopilot_route_node_index := 0
var manual_burn_tracking_enabled := false
var manual_burn_target_vector := Vector2.ZERO
var manual_burn_accumulated_vector := Vector2.ZERO
var manual_flight_plan: Dictionary = {}
var autopilot_complete := false
var autopilot_phase := "IDLE"
var heat_flux_mw := 0.0
var heat_shield_temperature := 290.0
var peak_heat_flux_mw := 0.0
var mach_number := 0.0
var dynamic_pressure_pa := 0.0
var max_dynamic_pressure_pa := 0.0
var camera_zoom := 0.000045
var solar_map_zoom := 1.0
var camera_offset := Vector2.ZERO
var trail: Array[Vector2] = []
var trail_timer := 0.0
var star_points: Array[Vector2] = []
var solar_belt_particles: Array[Dictionary] = []
var status_message := "PAD READY  •  PRESS W TO IGNITE"
var orbit_path: Array[Vector2] = []
var show_orbit := true
var show_grid := true
var show_vectors := true
var show_solar_system := false
var show_predicted_trajectory := false
var predicted_path: Array[Vector2] = []
var prediction_timer := 0.0
var thrust_key_down := false
var throttle_cutoff_key_down := false
var landed := true
var crashed := false
var landed_body_name := "Earth"
var landed_surface_normal := Vector2.UP
var launch_pad_normal := Vector2.UP
var launch_pad_reference_time := 0.0
var discovered_body_names: Dictionary = {"Earth": true, "Moon": true}
var telescope_active := false
var telescope_direction_angle := 0.0
var telescope_field_of_view := PI / 6.0
var visited_body_names: Dictionary = {"Earth": true}
var passive_orbit_active := false
var separation_parent_name := ""
var separation_grace_until := 0.0
var passive_orbit_forced := false
var passive_orbit_data: Dictionary = {}
var fleet_visuals: Array[Dictionary] = []
var collision_effects: Array[Dictionary] = []

func spawn_collision_effect(world_position: Vector2, intensity: float = 1.0) -> void:
	collision_effects.append({
		"position": world_position,
		"age": 0.0,
		"duration": 2.4,
		"intensity": clampf(intensity, 0.5, 2.5)
	})
	queue_redraw()

func _update_collision_effects(delta: float) -> void:
	for index in range(collision_effects.size() - 1, -1, -1):
		var effect: Dictionary = collision_effects[index]
		effect["age"] = float(effect.get("age", 0.0)) + delta
		if float(effect.age) >= float(effect.get("duration", 2.4)):
			collision_effects.remove_at(index)
		else:
			collision_effects[index] = effect

func _set_rocket_position_components(position_x: float, position_y: float) -> void:
	rocket_position_precise = PackedFloat64Array([position_x, position_y])
	_rocket_position_display = Vector2(position_x, position_y)

func set_rocket_design(design: Dictionary) -> void:
	launch_design = design.duplicate(true)
	rocket_stages = (design.get("stages", []) as Array).duplicate(true)
	if rocket_stages.is_empty():
		rocket_stages = RocketDesign.create_default()["stages"].duplicate(true)
	for stage_index_value in range(rocket_stages.size()):
		var stage: Dictionary = RocketAssembly.ensure_stage_components(rocket_stages[stage_index_value])
		var components: Array = stage.get("components", []).duplicate(true)
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			var part_uid := str(component.get("part_uid", ""))
			if part_uid.is_empty():
				part_uid = "part_%d_%d_%s" % [stage_index_value, component_index, str(component.get("id", "part"))]
			if not bool(design.get("preserve_part_uids", false)) and not part_uid.begins_with(vehicle_name + "::"):
				part_uid = vehicle_name + "::" + part_uid
			component["part_uid"] = part_uid
			components[component_index] = component
		rocket_stages[stage_index_value] = RocketAssembly.compile_stage(stage, components)
	payload_mass = float(design.get("payload_mass", 500.0))
	payload_type = str(design.get("payload_type", "probe"))
	var visual_data: Variant = design.get("payload_visual", {})
	payload_visual = visual_data.duplicate(true) if visual_data is Dictionary else {}
	payload_subassembly_id = str(design.get("payload_subassembly_id", "main"))
	stage_index = 0
	action_stage_index = 0
	gimbal_angle = 0.0
	gimbal_trim_center_of_mass = Vector2(INF, INF)
	gimbal_trim_stage_index = -1
	gimbal_trim_last_time = -INF
	stage_fuel_remaining.clear()
	for stage in rocket_stages:
		stage_fuel_remaining.append(RocketDesign.stage_total_fuel_capacity(stage))
	fuel = stage_fuel_remaining[0]
	resource_tanks.clear()
	for physical_stage_index in range(rocket_stages.size()):
		var tank_states := ResourceNetwork.create_tank_states(rocket_stages[physical_stage_index].get("components", []))
		for tank_state in tank_states:
			var resources: Dictionary = tank_state.get("resources", {}).duplicate(true)
			resources.erase("rcs_propellant")
			tank_state["resources"] = resources
			var capacities: Dictionary = tank_state.get("resource_capacities", {}).duplicate(true)
			capacities.erase("rcs_propellant")
			tank_state["resource_capacities"] = capacities
			tank_state["stage_index"] = physical_stage_index
			tank_state["module_id"] = vehicle_name
			if not resources.is_empty():
				resource_tanks.append(tank_state)
	rcs_propellant_remaining = _remaining_rcs_propellant_capacity()
	infinite_fuel_stage_remaining = fuel
	staging_part_states.clear()
	staging_plan = StagingSystem.create_plan([{
		"module_id": vehicle_name,
		"stages": rocket_stages,
		"staging_stage_count": int(design.get("staging_stage_count", 0)),
		"staging_stage_labels": design.get("staging_stage_labels", []).duplicate(true)
	}])
	staging_changed.emit()

func _sync_legacy_fuel_from_external_tanks(shared_tanks: Array) -> void:
	for index in range(stage_fuel_remaining.size()):
		var total := 0.0
		for tank in shared_tanks:
			if str(tank.get("module_id", "")) == vehicle_name and int(tank.get("stage_index", -1)) == index:
				total += maxf(0.0, float(tank.get("resources", {}).get("liquid_propellant", 0.0)))
		stage_fuel_remaining[index] = total
	fuel = 0.0
	rcs_propellant_remaining = 0.0

func resource_amount(resource: String, supply_only: bool = true) -> float:
	return ResourceNetwork.resource_total(resource_tanks, resource, supply_only)

func _consume_resource(resource: String, amount: float, physical_stage_index: int = -1) -> float:
	var remaining := maxf(0.0, amount)
	var consumed := 0.0
	for index in range(resource_tanks.size()):
		var tank: Dictionary = resource_tanks[index]
		if physical_stage_index >= 0 and int(tank.get("stage_index", -1)) != physical_stage_index:
			continue
		if not bool(tank.get("fuel_supply_enabled", true)):
			continue
		var resources: Dictionary = tank.get("resources", {}).duplicate(true)
		var available := maxf(0.0, float(resources.get(resource, 0.0)))
		var taken := minf(available, remaining)
		if taken <= 0.0:
			continue
		resources[resource] = available - taken
		tank["resources"] = resources
		resource_tanks[index] = tank
		consumed += taken
		remaining -= taken
		if remaining <= 0.0000001:
			break
	return consumed

func _fill_resource_tanks(resource: String, amount: float, physical_stage_index: int = -1) -> float:
	var remaining := maxf(0.0, amount)
	var added := 0.0
	for index in range(resource_tanks.size()):
		var tank: Dictionary = resource_tanks[index]
		if physical_stage_index >= 0 and int(tank.get("stage_index", -1)) != physical_stage_index:
			continue
		var resources: Dictionary = tank.get("resources", {}).duplicate(true)
		var capacities: Dictionary = tank.get("resource_capacities", {})
		var current := maxf(0.0, float(resources.get(resource, 0.0)))
		var capacity := maxf(0.0, float(capacities.get(resource, 0.0)))
		var transferred := minf(remaining, maxf(0.0, capacity - current))
		if transferred <= 0.0:
			continue
		resources[resource] = current + transferred
		tank["resources"] = resources
		resource_tanks[index] = tank
		added += transferred
		remaining -= transferred
		if remaining <= 0.0000001:
			break
	return added

func transfer_between_tanks(source_part_id: String, destination_part_id: String, resource: String, amount: float, connected: bool = true) -> float:
	if not connected:
		return 0.0
	for source_index in range(resource_tanks.size()):
		if str(resource_tanks[source_index].get("part_uid", "")) != source_part_id:
			continue
		for destination_index in range(resource_tanks.size()):
			if str(resource_tanks[destination_index].get("part_uid", "")) != destination_part_id:
				continue
			var source: Dictionary = resource_tanks[source_index].duplicate(true)
			var destination: Dictionary = resource_tanks[destination_index].duplicate(true)
			var transferred := ResourceNetwork.transfer_between_tanks(source, destination, resource, amount, true)
			resource_tanks[source_index] = source
			resource_tanks[destination_index] = destination
			_sync_legacy_fuel_from_tanks()
			return transferred
	return 0.0

func _sync_legacy_fuel_from_tanks() -> void:
	for index in range(stage_fuel_remaining.size()):
		var total := 0.0
		for tank in resource_tanks:
			if str(tank.get("module_id", vehicle_name)) == vehicle_name and int(tank.get("stage_index", -1)) == index:
				total += maxf(0.0, float(tank.get("resources", {}).get("liquid_propellant", 0.0)))
		stage_fuel_remaining[index] = total
	var external_fuel := 0.0
	for tank in resource_tanks:
		if str(tank.get("module_id", vehicle_name)) != vehicle_name and bool(tank.get("fuel_supply_enabled", true)):
			external_fuel += maxf(0.0, float(tank.get("resources", {}).get("liquid_propellant", 0.0)))
	if stage_index < stage_fuel_remaining.size():
		fuel = stage_fuel_remaining[stage_index]

func _has_ignited_solid_motor() -> bool:
	for index in range(stage_index, rocket_stages.size()):
		for component in rocket_stages[index].get("components", []):
			if bool(component.get("solid_motor", false)) and bool(component.get("ignited", false)):
				return true
	return false

func _solar_generation_rate() -> float:
	var generation := 0.0
	for index in range(stage_index, rocket_stages.size()):
		for component in rocket_stages[index].get("components", []):
			if str(component.get("kind", "")) == "power" and bool(component.get("deployed", false)):
				generation += maxf(0.0, float(component.get("power_generation_w", 0.0)))
	for docked_visual in docked_visuals:
		var design: Dictionary = docked_visual.get("design", {})
		var stages: Array = design.get("stages", [])
		for index in range(int(docked_visual.get("stage_index", 0)), stages.size()):
			for component in stages[index].get("components", []):
				if str(component.get("kind", "")) == "power" and bool(component.get("deployed", false)):
					generation += maxf(0.0, float(component.get("power_generation_w", 0.0)))
	var solar_distance := maxf(0.1 * PlanetarySystem.ASTRONOMICAL_UNIT, rocket_position.length())
	return generation * pow(PlanetarySystem.ASTRONOMICAL_UNIT / solar_distance, 2.0)

func _current_staging_part_states() -> Dictionary:
	var states: Dictionary = {}
	for stage in rocket_stages:
		for component in stage.get("components", []):
			if not component is Dictionary:
				continue
			var part_id := str(component.get("part_uid", ""))
			if part_id.is_empty():
				continue
			states[part_id] = {
				"engine_enabled": bool(component.get("engine_enabled", true)),
				"ignited": bool(component.get("ignited", false)),
				"fuel_supply_enabled": bool(component.get("fuel_supply_enabled", true)),
				"rcs_enabled": bool(component.get("rcs_enabled", true)),
				"deployed": bool(component.get("deployed", false)),
				"attached": bool(component.get("attached", true)),
				"can_repeat": bool(component.get("attached", true))
			}
	return states

func _prune_staging_plan_to_attached_parts() -> void:
	var attached_parts: Dictionary = {}
	for stage_index_value in range(stage_index, rocket_stages.size()):
		for component in rocket_stages[stage_index_value].get("components", []):
			if component is Dictionary:
				attached_parts[str(component.get("part_uid", ""))] = true
	for plan_index in range(staging_plan.size()):
		var stage: Dictionary = staging_plan[plan_index]
		var actions: Array = []
		for action in stage.get("actions", []):
			if action is Dictionary and attached_parts.has(str(action.get("part_id", ""))):
				actions.append(action)
		stage["actions"] = actions
		staging_plan[plan_index] = stage
	while not staging_plan.is_empty() and (staging_plan.back().get("actions", []) as Array).is_empty():
		staging_plan.pop_back()
	action_stage_index = clampi(action_stage_index, 0, maxi(0, staging_plan.size() - 1))

func _apply_staging_part_states() -> void:
	for stage_index_value in range(rocket_stages.size()):
		var stage: Dictionary = rocket_stages[stage_index_value]
		var components: Array = stage.get("components", []).duplicate(true)
		var changed := false
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			var part_id := str(component.get("part_uid", ""))
			if not staging_part_states.has(part_id):
				continue
			var state: Dictionary = staging_part_states[part_id]
			for key in ["engine_enabled", "ignited", "fuel_supply_enabled", "rcs_enabled", "deployed", "attached"]:
				if state.has(key) and component.get(key, null) != state[key]:
					component[key] = state[key]
					changed = true
			components[component_index] = component
		if changed:
			rocket_stages[stage_index_value] = RocketAssembly.compile_stage(stage, components)
	for tank_index in range(resource_tanks.size()):
		var tank: Dictionary = resource_tanks[tank_index]
		var part_state: Dictionary = staging_part_states.get(str(tank.get("part_uid", "")), {})
		if part_state.has("fuel_supply_enabled"):
			tank["fuel_supply_enabled"] = bool(part_state.fuel_supply_enabled)
		resource_tanks[tank_index] = tank

func select_action_stage(requested_index: int) -> void:
	if staging_plan.is_empty():
		action_stage_index = 0
		return
	var selected := clampi(requested_index, 0, staging_plan.size() - 1)
	if selected < action_stage_index:
		staging_part_states = _current_staging_part_states()
		for index in range(selected, staging_plan.size()):
			staging_plan = StagingSystem.rearm_stage(staging_plan, index, staging_part_states)
	action_stage_index = selected
	staging_changed.emit()

func rearm_action_stage() -> void:
	staging_part_states = _current_staging_part_states()
	if action_stage_index >= 0 and action_stage_index < staging_plan.size():
		staging_plan = StagingSystem.rearm_stage(staging_plan, action_stage_index, staging_part_states)
	staging_changed.emit()

func set_component_state(part_uid: String, property: String, value: Variant) -> bool:
	for stage_index_value in range(stage_index, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[stage_index_value]
		var components: Array = stage.get("components", []).duplicate(true)
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			if str(component.get("part_uid", "")) != part_uid:
				continue
			component[property] = value
			components[component_index] = component
			rocket_stages[stage_index_value] = RocketAssembly.compile_stage(stage, components)
			staging_part_states[part_uid] = _current_staging_part_states().get(part_uid, {})
			if property == "fuel_supply_enabled":
				for tank_index in range(resource_tanks.size()):
					if str(resource_tanks[tank_index].get("part_uid", "")) == part_uid:
						var tank: Dictionary = resource_tanks[tank_index]
						tank["fuel_supply_enabled"] = bool(value)
						resource_tanks[tank_index] = tank
			_sync_legacy_fuel_from_tanks()
			staging_changed.emit()
			return true
	return false

func _part_at_screen_position(screen_position: Vector2) -> String:
	if show_solar_system or camera_zoom <= 0.0000000002:
		return ""
	var object_scale := RocketVisual.camera_scale(camera_zoom, _visual_scale())
	if object_scale <= 0.0000001:
		return ""
	var control_position := get_global_transform_with_canvas().affine_inverse() * screen_position
	var local_click := (control_position - size * 0.5).rotated(-rotation_angle) / object_scale
	var best_uid := ""
	var best_score := INF
	var total_length := 0.0
	var geometries: Array[Dictionary] = []
	for index in range(stage_index, rocket_stages.size()):
		var geometry := RocketAssembly.stage_geometry(rocket_stages[index])
		geometries.append(geometry)
		total_length += float(geometry.get("length", 1.0))
	var cursor := -total_length * 0.5
	for geometry in geometries:
		var stage_center_y := cursor + float(geometry.get("length", 1.0)) * 0.5
		var stage: Dictionary = geometry.get("stage", {})
		var components: Array = stage.get("components", [])
		var positions: Dictionary = geometry.get("component_positions", {})
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			var radius := maxf(0.5, float(component.get("collision_radius_m", 0.5)))
			var half_width := maxf(radius * 1.15, 5.0 / object_scale)
			var half_length := maxf(float(component.get("length_m", 1.0)) * 0.58, 5.0 / object_scale)
			var angle := deg_to_rad(float(component.get("rotation_deg", 0.0)))
			for position in positions.get(component_index, []):
				var center: Vector2 = Vector2(position) + Vector2(0.0, stage_center_y)
				var local_offset := (local_click - center).rotated(-angle)
				if absf(local_offset.x) > half_width or absf(local_offset.y) > half_length:
					continue
				var score := local_offset.x * local_offset.x / (half_width * half_width) + local_offset.y * local_offset.y / (half_length * half_length)
				if score < best_score:
					best_score = score
					best_uid = str(component.get("part_uid", ""))
		cursor += float(geometry.get("length", 1.0))
	for docked_visual in docked_visuals:
		var design: Dictionary = docked_visual.get("design", {})
		var stages: Array = design.get("stages", [])
		var attached_stage_index := int(docked_visual.get("stage_index", 0))
		if attached_stage_index < 0 or attached_stage_index >= stages.size():
			continue
		var attached_rotation := float(docked_visual.get("rotation", rotation_angle)) - rotation_angle
		var attached_offset: Vector2 = Vector2(docked_visual.get("offset", Vector2.ZERO))
		var attached_geometries: Array[Dictionary] = []
		var attached_length := 0.0
		for index in range(attached_stage_index, stages.size()):
			var attached_geometry := RocketAssembly.stage_geometry(stages[index])
			attached_geometries.append(attached_geometry)
			attached_length += float(attached_geometry.get("length", 1.0))
		var attached_cursor := -attached_length * 0.5
		for attached_geometry in attached_geometries:
			var attached_stage_center := attached_cursor + float(attached_geometry.get("length", 1.0)) * 0.5
			var attached_stage: Dictionary = attached_geometry.get("stage", {})
			var attached_components: Array = attached_stage.get("components", [])
			var attached_positions: Dictionary = attached_geometry.get("component_positions", {})
			for component_index in range(attached_components.size()):
				var component: Dictionary = attached_components[component_index]
				var radius := maxf(0.5, float(component.get("collision_radius_m", 0.5)))
				var half_width := maxf(radius * 1.15, 5.0 / object_scale)
				var half_length := maxf(float(component.get("length_m", 1.0)) * 0.58, 5.0 / object_scale)
				var component_angle := deg_to_rad(float(component.get("rotation_deg", 0.0))) + attached_rotation
				for position in attached_positions.get(component_index, []):
					var center: Vector2 = (Vector2(position) + Vector2(0.0, attached_stage_center)).rotated(attached_rotation) + attached_offset
					var local_offset := (local_click - center).rotated(-component_angle)
					if absf(local_offset.x) > half_width or absf(local_offset.y) > half_length:
						continue
					var score := local_offset.x * local_offset.x / (half_width * half_width) + local_offset.y * local_offset.y / (half_length * half_length)
					if score < best_score:
						best_score = score
						best_uid = str(component.get("part_uid", ""))
			attached_cursor += float(attached_geometry.get("length", 1.0))
	return best_uid

func execute_staging_actions(actions: Array) -> bool:
	if actions.is_empty():
		return false
	staging_part_states = _current_staging_part_states()
	var result := StagingSystem.execute_stage([{"actions": actions.duplicate(true)}], 0, staging_part_states)
	if not bool(result.get("valid", false)):
		return false
	staging_part_states = result.part_states
	_apply_staging_part_states()
	var should_ignite := false
	var should_cutoff := false
	var should_separate := false
	var module_release_index := -1
	var component_group_release_uid := ""
	for action in actions:
		if not action is Dictionary:
			continue
		match str(action.get("action", "")):
			"activate_engine", "ignite_solid_motor":
				should_ignite = true
			"deactivate_engine":
				should_cutoff = true
			"separate":
				if int(action.get("physical_stage_index", -1)) == stage_index:
					should_separate = true
			"undock_module":
				module_release_index = int(action.get("physical_stage_index", -1))
			"undock_component_group":
				component_group_release_uid = str(action.get("part_id", ""))
	if should_cutoff:
		thrust_key_down = false
	if should_ignite:
		thrust_key_down = true
	if should_separate:
		_separate_stage()
	elif not component_group_release_uid.is_empty():
		_release_component_group(component_group_release_uid)
	elif module_release_index > stage_index:
		_release_upper_module(module_release_index)
	return true

func activate_current_action_stage() -> bool:
	if action_stage_index < 0 or action_stage_index >= staging_plan.size():
		return false
	staging_part_states = _current_staging_part_states()
	var executed_stage: Dictionary = staging_plan[action_stage_index]
	var actions: Array = executed_stage.get("actions", [])
	if actions.is_empty():
		return false
	var result := StagingSystem.execute_stage(staging_plan, action_stage_index, staging_part_states)
	if not bool(result.get("valid", false)):
		return false
	staging_plan = result.plan
	staging_part_states = result.part_states
	var should_ignite := false
	var should_cutoff := false
	var should_separate := false
	var module_release_index := -1
	var component_group_release_uid := ""
	for action in actions:
		if not action is Dictionary or bool(action.get("completed", false)):
			continue
		match str(action.get("action", "")):
			"activate_engine":
				should_ignite = true
			"deactivate_engine":
				should_cutoff = true
			"separate":
				if int(action.get("physical_stage_index", -1)) == stage_index:
					should_separate = true
			"undock_module":
				module_release_index = int(action.get("physical_stage_index", -1))
			"undock_component_group":
				component_group_release_uid = str(action.get("part_id", ""))
	_apply_staging_part_states()
	if should_cutoff:
		thrust_key_down = false
	if should_ignite:
		thrust_key_down = true
	if should_separate and stage_index < rocket_stages.size() - 1:
		_separate_stage()
		_prune_staging_plan_to_attached_parts()
	elif not component_group_release_uid.is_empty() and _release_component_group(component_group_release_uid):
		_prune_staging_plan_to_attached_parts()
	elif module_release_index > stage_index and _release_upper_module(module_release_index):
		_prune_staging_plan_to_attached_parts()
	if action_stage_index + 1 < staging_plan.size():
		action_stage_index += 1
	staging_changed.emit()
	return true

func _active_stage_data() -> Dictionary:
	var stage: Dictionary = rocket_stages[clampi(stage_index, 0, rocket_stages.size() - 1)].duplicate(true)
	stage["dry_mass"] = RocketDesign.stage_total_dry_mass(stage)
	stage["fuel_capacity"] = RocketDesign.stage_total_fuel_capacity(stage)
	stage["thrust"] = RocketDesign.stage_total_thrust(stage)
	stage["vacuum_thrust"] = RocketDesign.stage_total_thrust(stage, true)
	stage["flow"] = RocketDesign.stage_total_flow(stage)
	stage["engine_count"] = 1
	stage.erase("boosters")
	return stage

func _remaining_stack_mass() -> float:
	var mass := payload_mass
	for i in range(stage_index + 1, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[i]
		mass += RocketDesign.stage_total_dry_mass(stage)
		if not resource_inventory_external:
			mass += stage_fuel_remaining[i] if i < stage_fuel_remaining.size() else RocketDesign.stage_total_fuel_capacity(stage)
	return mass

func total_propellant_remaining() -> float:
	var total := 0.0
	for i in range(stage_index, rocket_stages.size()):
		total += fuel if i == stage_index else (stage_fuel_remaining[i] if i < stage_fuel_remaining.size() else RocketDesign.stage_total_fuel_capacity(rocket_stages[i]))
	for tank in resource_tanks:
		if str(tank.get("module_id", vehicle_name)) != vehicle_name:
			total += maxf(0.0, float(tank.get("resources", {}).get("liquid_propellant", 0.0)))
	return total

func total_propellant_capacity() -> float:
	var total := 0.0
	for i in range(stage_index, rocket_stages.size()):
		total += RocketDesign.stage_total_fuel_capacity(rocket_stages[i])
	return total

func _reconcile_legacy_fuel_inventory() -> void:
	for stage_index_value in range(stage_fuel_remaining.size()):
		var stage_tanks: Array[int] = []
		var capacity_total := 0.0
		for tank_index in range(resource_tanks.size()):
			var tank: Dictionary = resource_tanks[tank_index]
			if str(tank.get("module_id", vehicle_name)) != vehicle_name or int(tank.get("stage_index", -1)) != stage_index_value:
				continue
			var capacity := float(tank.get("resource_capacities", {}).get("liquid_propellant", 0.0))
			if capacity > 0.0:
				stage_tanks.append(tank_index)
				capacity_total += capacity
		if capacity_total <= 0.0:
			continue
		var desired := clampf(float(stage_fuel_remaining[stage_index_value]), 0.0, capacity_total)
		var inventory_total := 0.0
		for tank_index in stage_tanks:
			inventory_total += float(resource_tanks[tank_index].get("resources", {}).get("liquid_propellant", 0.0))
		if absf(inventory_total - desired) <= 0.001:
			continue
		for tank_index in stage_tanks:
			var tank: Dictionary = resource_tanks[tank_index]
			var resources: Dictionary = tank.get("resources", {}).duplicate(true)
			var capacity := float(tank.get("resource_capacities", {}).get("liquid_propellant", 0.0))
			resources["liquid_propellant"] = desired * capacity / capacity_total
			tank["resources"] = resources
			resource_tanks[tank_index] = tank

func remove_propellant(amount: float) -> float:
	_reconcile_legacy_fuel_inventory()
	var remaining := maxf(0.0, amount)
	var requested := remaining
	for index in range(stage_index, rocket_stages.size()):
		var taken := _consume_resource("liquid_propellant", remaining)
		remaining -= taken
		if remaining <= 0.000001:
			break
	_sync_legacy_fuel_from_tanks()
	return requested - remaining

func add_propellant(amount: float) -> float:
	_reconcile_legacy_fuel_inventory()
	var remaining := maxf(0.0, amount)
	var requested := remaining
	for index in range(stage_index, rocket_stages.size()):
		var added := _fill_resource_tanks("liquid_propellant", remaining)
		remaining -= added
		if remaining <= 0.000001:
			break
	_sync_legacy_fuel_from_tanks()
	return requested - remaining

func _vehicle_mass_properties(active_fuel_amount: float = -1.0, active_rcs_fuel_amount: float = -1.0) -> Dictionary:
	var stage_lengths: Array[float] = []
	var total_length := 0.0
	for index in range(stage_index, rocket_stages.size()):
		var geometry: Dictionary = RocketAssembly.stage_geometry(rocket_stages[index])
		var stage_length := float(geometry.get("length", 1.0))
		stage_lengths.append(stage_length)
		total_length += stage_length
	var elements: Array[Dictionary] = []
	var total_rcs_capacity := _own_rcs_propellant_capacity()
	var rcs_fuel_amount := active_rcs_fuel_amount if active_rcs_fuel_amount >= 0.0 else maxf(0.0, rcs_propellant_remaining - _external_rcs_propellant_total())
	var rcs_fuel_fraction := clampf(rcs_fuel_amount / total_rcs_capacity, 0.0, 1.0) if total_rcs_capacity > 0.0 else 0.0
	var cursor := -total_length * 0.5
	for offset in range(stage_lengths.size()):
		var index := stage_index + offset
		var stage: Dictionary = rocket_stages[index]
		var stage_length := stage_lengths[offset]
		var stage_center_y := cursor + stage_length * 0.5
		var stage_fuel := 0.0
		if resource_inventory_external:
			stage_fuel = 0.0
		elif offset == 0:
			stage_fuel = active_fuel_amount if active_fuel_amount >= 0.0 else (infinite_fuel_stage_remaining if infinite_weightless_fuel else fuel)
		elif index < stage_fuel_remaining.size():
			stage_fuel = stage_fuel_remaining[index]
		else:
			stage_fuel = RocketDesign.stage_total_fuel_capacity(stage)
		elements.append_array(RocketAssembly.stage_mass_elements(stage, stage_fuel, stage_center_y, rcs_fuel_fraction))
		cursor += stage_length
	var payload_length := maxf(1.0, sqrt(maxf(1.0, payload_mass)) * 0.5)
	var payload_radius := maxf(0.5, sqrt(maxf(1.0, payload_mass)) * 0.12)
	var payload_position := Vector2(0.0, total_length * 0.5 + payload_length * 0.5)
	elements.append({
		"mass": payload_mass,
		"position": payload_position,
		"intrinsic_inertia": payload_mass * (payload_length * payload_length / 12.0 + payload_radius * payload_radius / 4.0)
	})
	var represented_docked_mass := 0.0
	for docked_visual in docked_visuals:
		var attached_mass := maxf(0.0, float(docked_visual.get("mass", 0.0)))
		if attached_mass <= 0.0:
			continue
		var attached_offset: Vector2 = Vector2(docked_visual.get("offset", Vector2.ZERO))
		var attached_center: Vector2 = Vector2(docked_visual.get("center_of_mass", Vector2.ZERO))
		elements.append({
			"mass": attached_mass,
			"position": attached_offset + attached_center,
			"intrinsic_inertia": maxf(0.0, float(docked_visual.get("moment_of_inertia", attached_mass * 25.0)))
		})
		represented_docked_mass += attached_mass
	var unrepresented_docked_mass := maxf(0.0, docked_mass - represented_docked_mass)
	if unrepresented_docked_mass > 0.0:
		elements.append({
			"mass": unrepresented_docked_mass,
			"position": Vector2.ZERO,
			"intrinsic_inertia": unrepresented_docked_mass * 25.0
		})
	var total_mass := 0.0
	var weighted_position := Vector2.ZERO
	for element in elements:
		var mass := maxf(0.0, float(element.get("mass", 0.0)))
		total_mass += mass
		weighted_position += Vector2(element.get("position", Vector2.ZERO)) * mass
	var center_of_mass := weighted_position / total_mass if total_mass > 0.0 else Vector2.ZERO
	var moment_of_inertia := 0.0
	for element in elements:
		var mass := maxf(0.0, float(element.get("mass", 0.0)))
		var offset: Vector2 = Vector2(element.get("position", Vector2.ZERO)) - center_of_mass
		moment_of_inertia += float(element.get("intrinsic_inertia", 0.0)) + mass * offset.length_squared()
	return {
		"mass": total_mass,
		"center_of_mass": center_of_mass,
		"moment_of_inertia": maxf(1.0, moment_of_inertia)
	}

func _remaining_engine_elements(pressure_ratio: float, active_center_y: float) -> Array[Dictionary]:
	var engines: Array[Dictionary] = RocketAssembly.stage_engine_elements(rocket_stages[stage_index], pressure_ratio, active_center_y)
	for docked_visual in docked_visuals:
		var design: Dictionary = docked_visual.get("design", {})
		var stages: Array = design.get("stages", [])
		var attached_stage_index := int(docked_visual.get("stage_index", 0))
		if attached_stage_index < 0 or attached_stage_index >= stages.size():
			continue
		var total_length := 0.0
		var geometries: Array[Dictionary] = []
		for index in range(attached_stage_index, stages.size()):
			var geometry := RocketAssembly.stage_geometry(stages[index])
			geometries.append(geometry)
			total_length += float(geometry.get("length", 1.0))
		var child_active_center := -total_length * 0.5 + float(geometries[0].get("length", 1.0)) * 0.5
		var attached_offset: Vector2 = Vector2(docked_visual.get("offset", Vector2.ZERO))
		var attached_rotation := float(docked_visual.get("rotation", rotation_angle)) - rotation_angle
		for engine in RocketAssembly.stage_engine_elements(stages[attached_stage_index], pressure_ratio, child_active_center):
			var attached_engine: Dictionary = engine.duplicate(true)
			attached_engine["position"] = Vector2(attached_engine.get("position", Vector2.ZERO)).rotated(attached_rotation) + attached_offset
			attached_engine["direction"] = Vector2(attached_engine.get("direction", Vector2.UP)).rotated(attached_rotation)
			engines.append(attached_engine)
	return engines

func _engine_force_profile(center_of_mass: Vector2, pressure_ratio: float, thrust_scale: float = 1.0) -> Dictionary:
	var total_length := 0.0
	var active_geometry := RocketAssembly.stage_geometry(rocket_stages[stage_index])
	for index in range(stage_index, rocket_stages.size()):
		total_length += float(RocketAssembly.stage_geometry(rocket_stages[index]).get("length", 1.0))
	var active_center_y := -total_length * 0.5 + float(active_geometry.get("length", 1.0)) * 0.5
	var force_total := Vector2.ZERO
	var torque_total := 0.0
	var engines := _remaining_engine_elements(pressure_ratio, active_center_y)
	var resource_flows: Dictionary = {}
	var electric_draw := 0.0
	for engine in engines:
		var fuel_type := str(engine.get("fuel_type", "liquid_propellant"))
		if not (fuel_type == "liquid_propellant" and infinite_weightless_fuel) and resource_amount(fuel_type) <= 0.0000001:
			continue
		var engine_power := maxf(0.0, float(engine.get("electric_draw_w", 0.0)))
		if engine_power > 0.0 and resource_amount("electricity") <= 0.0:
			continue
		resource_flows[fuel_type] = float(resource_flows.get(fuel_type, 0.0)) + float(engine.get("flow", 0.0))
		electric_draw += engine_power
		var engine_direction: Vector2 = Vector2(engine.get("direction", Vector2.UP))
		if bool(engine.get("gimballed", false)):
			engine_direction = engine_direction.rotated(gimbal_angle)
		var engine_force := engine_direction.normalized() * float(engine.get("thrust", 0.0)) * thrust_scale
		var engine_position: Vector2 = engine.get("position", Vector2.ZERO)
		force_total += engine_force
		torque_total += (engine_position - center_of_mass).cross(engine_force)
	return {"force": force_total, "torque": torque_total, "resource_flows": resource_flows, "electric_draw_w": electric_draw}

func _external_rcs_propellant_total() -> float:
	var total := 0.0
	for amount in docked_rcs_propellant.values():
		total += maxf(0.0, float(amount))
	return total

func _consume_rcs_propellant(amount: float) -> float:
	var remaining := maxf(0.0, amount)
	var consumed := 0.0
	var own_amount := maxf(0.0, rcs_propellant_remaining - _external_rcs_propellant_total())
	var own_used := minf(own_amount, remaining)
	consumed += own_used
	remaining -= own_used
	for module_id in docked_rcs_propellant.keys():
		if remaining <= 0.0000001:
			break
		var available := maxf(0.0, float(docked_rcs_propellant[module_id]))
		var used := minf(available, remaining)
		docked_rcs_propellant[module_id] = available - used
		consumed += used
		remaining -= used
	rcs_propellant_remaining = maxf(0.0, rcs_propellant_remaining - consumed)
	return consumed

func _own_rcs_propellant_capacity() -> float:
	var capacity := 0.0
	for index in range(stage_index, rocket_stages.size()):
		capacity += RocketDesign.stage_rcs_propellant_capacity(rocket_stages[index])
	return capacity

func _remaining_rcs_propellant_capacity() -> float:
	var capacity := 0.0
	for index in range(stage_index, rocket_stages.size()):
		capacity += RocketDesign.stage_rcs_propellant_capacity(rocket_stages[index])
	for docked_visual in docked_visuals:
		var design: Dictionary = docked_visual.get("design", {})
		var stages: Array = design.get("stages", [])
		for index in range(int(docked_visual.get("stage_index", 0)), stages.size()):
			capacity += RocketDesign.stage_rcs_propellant_capacity(stages[index])
	return capacity

func _remaining_rcs_system() -> Dictionary:
	var system: Dictionary = {"thrust": 0.0, "flow": 0.0, "torque": 0.0}
	for jet in _remaining_rcs_elements():
		var force: Vector2 = Vector2(jet.get("direction", Vector2.UP)) * float(jet.get("thrust", 0.0))
		system.thrust = float(system.thrust) + force.length()
		system.flow = float(system.flow) + float(jet.get("flow", 0.0))
		system.torque = float(system.torque) + Vector2(jet.get("position", Vector2.ZERO)).cross(force)
	return system

func _remaining_rcs_elements() -> Array[Dictionary]:
	var elements: Array[Dictionary] = []
	var total_length := 0.0
	var geometries: Array[Dictionary] = []
	for index in range(stage_index, rocket_stages.size()):
		var geometry := RocketAssembly.stage_geometry(rocket_stages[index])
		geometries.append(geometry)
		total_length += float(geometry.get("length", 1.0))
	var cursor := -total_length * 0.5
	for geometry in geometries:
		var stage: Dictionary = geometry.stage
		var stage_length := float(geometry.get("length", 1.0))
		elements.append_array(RocketAssembly.stage_rcs_elements(stage, cursor + stage_length * 0.5))
		cursor += stage_length
	for docked_visual in docked_visuals:
		var design: Dictionary = docked_visual.get("design", {})
		var stages: Array = design.get("stages", [])
		var attached_stage_index := int(docked_visual.get("stage_index", 0))
		var attached_length := 0.0
		var attached_geometries: Array[Dictionary] = []
		for index in range(attached_stage_index, stages.size()):
			var geometry := RocketAssembly.stage_geometry(stages[index])
			attached_geometries.append(geometry)
			attached_length += float(geometry.get("length", 1.0))
		var attached_cursor := -attached_length * 0.5
		var attached_offset: Vector2 = Vector2(docked_visual.get("offset", Vector2.ZERO))
		var attached_rotation := float(docked_visual.get("rotation", rotation_angle)) - rotation_angle
		for geometry in attached_geometries:
			var stage_length := float(geometry.get("length", 1.0))
			for jet in RocketAssembly.stage_rcs_elements(geometry.stage, attached_cursor + stage_length * 0.5):
				var attached_jet: Dictionary = jet.duplicate(true)
				attached_jet["position"] = Vector2(attached_jet.get("position", Vector2.ZERO)).rotated(attached_rotation) + attached_offset
				attached_jet["direction"] = Vector2(attached_jet.get("direction", Vector2.UP)).rotated(attached_rotation)
				elements.append(attached_jet)
			attached_cursor += stage_length
	return elements

func _rcs_force_profile(translation_input: Vector2, rotation_input: float, center_of_mass: Vector2) -> Dictionary:
	var force_total := Vector2.ZERO
	var torque_total := 0.0
	var flow_total := 0.0
	var selected_jets := 0
	var translation_direction := translation_input.normalized()
	for jet in _remaining_rcs_elements():
		var direction: Vector2 = Vector2(jet.get("direction", Vector2.UP)).normalized()
		var force := direction * float(jet.get("thrust", 0.0))
		var position: Vector2 = Vector2(jet.get("position", Vector2.ZERO))
		var jet_torque := (position - center_of_mass).cross(force)
		var selected_for_translation := translation_input.length_squared() > 0.000001 and direction.dot(translation_direction) > 0.65
		var selected_for_rotation := absf(rotation_input) > 0.001 and jet_torque * rotation_input > 0.0
		if not selected_for_translation and not selected_for_rotation:
			continue
		force_total += force
		torque_total += jet_torque
		flow_total += float(jet.get("flow", 0.0))
		selected_jets += 1
	return {"force": force_total, "torque": torque_total, "flow": flow_total, "jet_count": selected_jets}

func _autopilot_attitude_control(target_rotation: float, dt: float, burn_expected: bool) -> bool:
	if dt <= 0.0:
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0
		return false
	var mass_properties := _vehicle_mass_properties()
	var center_of_mass: Vector2 = Vector2(mass_properties.center_of_mass)
	var inertia := maxf(1.0, float(mass_properties.moment_of_inertia))
	var pressure_ratio := 0.0
	var expected_throttle := autopilot_throttle if autopilot_phase == "LANDING_DESCENT" else 1.0
	var potential_engine_torque := 0.0
	if burn_expected:
		var local_body := _nearest_body_state(rocket_position, rocket_position_precise)
		var altitude := maxf(0.0, float(local_body.get("distance", EARTH_RADIUS)) - float(local_body.get("radius", EARTH_RADIUS)))
		var body_name := str(local_body.get("name", "Earth"))
		var density := PlanetarySystem.planetary_atmosphere_density(body_name, altitude)
		var gas_constant := PlanetarySystem.planetary_atmosphere_gas_constant(body_name)
		var temperature := PlanetarySystem.planetary_atmosphere_temperature(body_name)
		pressure_ratio = density * gas_constant * temperature / 101325.0
		potential_engine_torque = float(_engine_force_profile(center_of_mass, pressure_ratio, expected_throttle).get("torque", 0.0))
		var stage_changed := stage_index != gimbal_trim_stage_index
		var trim_due := stage_changed or center_of_mass.distance_to(gimbal_trim_center_of_mass) >= 0.25 or sim_time - gimbal_trim_last_time >= 1.0
		var trim_needed := absf(potential_engine_torque) > maxf(0.5, inertia * deg_to_rad(0.05))
		if stage_changed or (trim_needed and trim_due):
			var total_length := 0.0
			for index in range(stage_index, rocket_stages.size()):
				total_length += float(RocketAssembly.stage_geometry(rocket_stages[index]).get("length", 1.0))
			var active_geometry := RocketAssembly.stage_geometry(rocket_stages[stage_index])
			var active_center_y := -total_length * 0.5 + float(active_geometry.get("length", 1.0)) * 0.5
			var has_gimballed_engine := false
			for engine in _remaining_engine_elements(pressure_ratio, active_center_y):
				if bool(engine.get("gimballed", false)):
					has_gimballed_engine = true
					break
			if has_gimballed_engine:
				var best_gimbal := gimbal_angle
				var lowest_torque := absf(potential_engine_torque)
				if stage_changed:
					for step in range(-16, 17):
						var candidate_gimbal := deg_to_rad(float(step) * 0.5)
						gimbal_angle = candidate_gimbal
						var candidate_torque := absf(float(_engine_force_profile(center_of_mass, pressure_ratio, expected_throttle).get("torque", 0.0)))
						candidate_torque += absf(candidate_gimbal) * inertia * deg_to_rad(0.02)
						if candidate_torque < lowest_torque:
							lowest_torque = candidate_torque
							best_gimbal = candidate_gimbal
				else:
					for step in [-4, -2, -1, 1, 2, 4]:
						var candidate_gimbal := clampf(gimbal_angle + deg_to_rad(float(step) * 0.5), deg_to_rad(-8.0), deg_to_rad(8.0))
						gimbal_angle = candidate_gimbal
						var candidate_torque := absf(float(_engine_force_profile(center_of_mass, pressure_ratio, expected_throttle).get("torque", 0.0)))
						candidate_torque += absf(candidate_gimbal) * inertia * deg_to_rad(0.02)
						if candidate_torque < lowest_torque:
							lowest_torque = candidate_torque
							best_gimbal = candidate_gimbal
				gimbal_angle = best_gimbal
			else:
				gimbal_angle = 0.0
			gimbal_trim_center_of_mass = center_of_mass
			gimbal_trim_stage_index = stage_index
			gimbal_trim_last_time = sim_time
		potential_engine_torque = float(_engine_force_profile(center_of_mass, pressure_ratio, expected_throttle).get("torque", 0.0))
	else:
		gimbal_angle = 0.0
	var body_target_rotation := target_rotation - gimbal_angle
	var angle_error := angle_difference(rotation_angle, body_target_rotation)
	var aligned := absf(angle_error) <= deg_to_rad(1.0) and absf(angular_velocity) <= deg_to_rad(0.5)
	var ascent_burn_ready := autopilot_phase == "ASCENT" and absf(angle_error) <= deg_to_rad(5.0) and absf(angular_velocity) <= deg_to_rad(1.0)
	var burn_ready := aligned or ascent_burn_ready
	var engine_torque := potential_engine_torque if burn_expected and aligned else 0.0
	var engine_torque_requires_rcs := burn_expected and absf(potential_engine_torque) > maxf(1.0, inertia * deg_to_rad(0.01))
	if autopilot_phase == "ASCENT" and not engine_torque_requires_rcs:
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0
		rotation_angle = lerp_angle(rotation_angle, body_target_rotation, clampf(dt * 1.5, 0.0, 1.0))
		angular_velocity = 0.0
		return true
	if not has_rcs_installed():
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0
		if burn_expected and absf(potential_engine_torque) > maxf(1.0, inertia * deg_to_rad(0.01)):
			status_message = "AUTOPILOT  •  THRUST TORQUE NEEDS RCS"
			return false
		rotation_angle = lerp_angle(rotation_angle, body_target_rotation, clampf(dt * 1.5, 0.0, 1.0))
		angular_velocity = 0.0
		return true
	var protect_ascent_reserve := autopilot_phase in ["ASCENT", "CIRCULARISE_BURN"] and rcs_propellant_remaining <= _remaining_rcs_propellant_capacity() * 0.5
	if rcs_propellant_remaining <= 0.001 or protect_ascent_reserve:
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0
		if aligned and absf(engine_torque) <= maxf(1.0, inertia * deg_to_rad(0.01)):
			return true
		status_message = "AUTOPILOT  •  RCS PROPELLANT REQUIRED"
		return false
	var positive_profile := _rcs_force_profile(Vector2.ZERO, 1.0, center_of_mass)
	var negative_profile := _rcs_force_profile(Vector2.ZERO, -1.0, center_of_mass)
	var positive_authority := maxf(0.0, float(positive_profile.get("torque", 0.0)))
	var negative_authority := maxf(0.0, -float(negative_profile.get("torque", 0.0)))
	if burn_expected and aligned:
		var counter_authority := positive_authority if engine_torque < 0.0 else negative_authority
		if absf(engine_torque) > counter_authority * 0.9:
			rcs_rotation_input = 0.0
			rcs_rotation_scale = 0.0
			status_message = "AUTOPILOT  •  INSUFFICIENT RCS TORQUE"
			return false
	var maximum_angular_acceleration := deg_to_rad(0.5)
	var maximum_angular_rate := deg_to_rad(2.0)
	var desired_rate := signf(angle_error) * minf(maximum_angular_rate, sqrt(2.0 * maximum_angular_acceleration * absf(angle_error)))
	var desired_acceleration := clampf((desired_rate - angular_velocity) / maxf(dt, 0.05), -maximum_angular_acceleration, maximum_angular_acceleration)
	var requested_torque := inertia * desired_acceleration - engine_torque
	if absf(requested_torque) <= 1.0:
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0
	elif requested_torque > 0.0:
		rcs_rotation_input = 1.0 if positive_authority > 0.0 else 0.0
		rcs_rotation_scale = clampf(requested_torque / maxf(1.0, positive_authority), 0.0, 1.0)
	else:
		rcs_rotation_input = -1.0 if negative_authority > 0.0 else 0.0
		rcs_rotation_scale = clampf(absf(requested_torque) / maxf(1.0, negative_authority), 0.0, 1.0)
	return burn_ready

func has_rcs_installed() -> bool:
	var system := _remaining_rcs_system()
	return float(system.thrust) > 0.0 and float(system.flow) > 0.0

func has_rcs() -> bool:
	return has_rcs_installed() and rcs_propellant_remaining > 0.001

func stage_has_rcs(stage: Dictionary) -> bool:
	var configured := RocketAssembly.ensure_stage_components(stage)
	return float(configured.get("rcs_thrust", 0.0)) > 0.0 and float(configured.get("rcs_flow", 0.0)) > 0.0

func stage_separation_is_dockable_module() -> bool:
	if stage_index >= rocket_stages.size() - 1:
		return false
	return not RocketAssembly.stage_docking_ports(rocket_stages[stage_index]).is_empty() and not RocketAssembly.stage_docking_ports(rocket_stages[stage_index + 1]).is_empty() and stage_has_rcs(rocket_stages[stage_index]) and stage_has_rcs(rocket_stages[stage_index + 1])

func has_docking_port() -> bool:
	for index in range(stage_index, rocket_stages.size()):
		if not RocketAssembly.stage_docking_ports(rocket_stages[index]).is_empty():
			return true
	return false

func docking_port_world_states() -> Array:
	var result: Array = []
	var total_length := 0.0
	var geometries: Array[Dictionary] = []
	for index in range(stage_index, rocket_stages.size()):
		var geometry := RocketAssembly.stage_geometry(rocket_stages[index])
		geometries.append(geometry)
		total_length += float(geometry.get("length", 1.0))
	var cursor := -total_length * 0.5
	for geometry in geometries:
		var stage_center_y := cursor + float(geometry.get("length", 1.0)) * 0.5
		var stage: Dictionary = geometry.get("stage", {})
		for port in RocketAssembly.stage_docking_ports(stage, stage_center_y):
			var local_position: Vector2 = port.position
			var local_normal: Vector2 = port.normal
			result.append({
				"position": rocket_position + local_position.rotated(rotation_angle),
				"normal": local_normal.rotated(rotation_angle).normalized(),
				"part_uid": str(port.get("part_uid", ""))
			})
		cursor += float(geometry.get("length", 1.0))
	return result

func docking_port_world_state(part_uid: String = "") -> Dictionary:
	for port in docking_port_world_states():
		if part_uid.is_empty() or str(port.get("part_uid", "")) == part_uid:
			return port
	return {}

func has_docking_engine() -> bool:
	if rocket_stages.is_empty() or stage_index < 0 or stage_index >= rocket_stages.size():
		return false
	var mass_properties := _vehicle_mass_properties()
	var profile := _engine_force_profile(Vector2(mass_properties.center_of_mass), 0.0)
	var flows: Dictionary = profile.get("resource_flows", {})
	return Vector2(profile.get("force", Vector2.ZERO)).length() > 0.0 and float(flows.get("liquid_propellant", 0.0)) > 0.0 and float(flows.get("solid_propellant", 0.0)) <= 0.0 and (infinite_weightless_fuel or resource_amount("liquid_propellant") > 0.001)

func apply_docking_engine_control(world_direction: Vector2, delta: float) -> bool:
	if world_direction.length_squared() <= 0.000001 or delta <= 0.0 or not has_docking_engine():
		thrust_key_down = false
		return false
	var mass_properties := _vehicle_mass_properties()
	var profile := _engine_force_profile(Vector2(mass_properties.center_of_mass), 0.0)
	var local_force: Vector2 = Vector2(profile.get("force", Vector2.ZERO))
	if local_force.length_squared() <= 0.000001:
		thrust_key_down = false
		return false
	var target_rotation := world_direction.angle() - local_force.angle()
	var aligned := _autopilot_attitude_control(target_rotation, delta, true)
	thrust_key_down = aligned
	return true

func apply_rcs_velocity_correction(velocity_correction: Vector2, delta: float) -> bool:
	if not has_rcs() or delta <= 0.0:
		return false
	var mass_properties := _vehicle_mass_properties()
	var mass := maxf(1.0, float(mass_properties.mass))
	var local_request := velocity_correction.rotated(-rotation_angle)
	if local_request.length_squared() <= 0.00000001:
		return true
	var profile := _rcs_force_profile(local_request, 0.0, Vector2(mass_properties.center_of_mass))
	var force: Vector2 = Vector2(profile.force)
	var flow := float(profile.flow)
	if force.length_squared() <= 0.00000001 or flow <= 0.0 or force.normalized().dot(local_request.normalized()) < 0.8:
		return false
	var maximum_delta_v := force.length() / mass * delta
	var requested_delta_v := minf(local_request.length(), maximum_delta_v)
	var requested_fraction := clampf(requested_delta_v / maxf(0.000001, maximum_delta_v), 0.0, 1.0)
	var requested_propellant := flow * delta * requested_fraction
	var used := minf(rcs_propellant_remaining, requested_propellant)
	if used <= 0.0:
		return false
	var applied_delta_v := maximum_delta_v * used / maxf(0.000001, flow * delta)
	var world_impulse_direction := force.normalized().rotated(rotation_angle)
	velocity += world_impulse_direction * applied_delta_v
	_consume_rcs_propellant(used)
	return true

func _current_vehicle_mass(fuel_amount: float = -1.0) -> float:
	var active := _active_stage_data()
	var mass := float(active.get("dry_mass", 0.0)) + _remaining_stack_mass()
	mass += fuel if fuel_amount < 0.0 else fuel_amount
	var attached_liquid_mass := 0.0
	for tank in resource_tanks:
		if str(tank.get("module_id", vehicle_name)) != vehicle_name:
			attached_liquid_mass += maxf(0.0, float(tank.get("resources", {}).get("liquid_propellant", 0.0)))
	var rcs_mass := 0.0 if resource_inventory_external else rcs_propellant_remaining
	mass += docked_mass + rcs_mass + attached_liquid_mass + resource_amount("xenon", false) + resource_amount("solid_propellant", false)
	return mass

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44219
	for i in range(500):
		star_points.append(Vector2(rng.randf_range(-12000, 12000), rng.randf_range(-8000, 8000)))
	_prepare_small_body_belts()
	set_process(true)

func _prepare_small_body_belts() -> void:
	solar_belt_particles.clear()
	for belt in PlanetarySystem.get_small_body_belts():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(belt.get("seed", 0))
		var inner_radius_m := float(belt.get("inner_radius_au", 0.0)) * PlanetarySystem.ASTRONOMICAL_UNIT
		var outer_radius_m := float(belt.get("outer_radius_au", 0.0)) * PlanetarySystem.ASTRONOMICAL_UNIT
		var min_collision_radius_m := float(belt.get("collision_radius_min_m", 500.0))
		var max_collision_radius_m := float(belt.get("collision_radius_max_m", 25000.0))
		var particles: Array[Dictionary] = []
		for i in range(int(belt.get("particle_count", 0))):
			var radius_m := rng.randf_range(inner_radius_m, outer_radius_m)
			particles.append({
				"id": i,
				"radius_m": radius_m,
				"phase_rad": rng.randf_range(0.0, TAU),
				"angular_rate": sqrt(PlanetarySystem.G * PlanetarySystem.SUN_MASS / pow(radius_m, 3.0)),
				"size_px": float(belt.get("particle_size_px", 1.0)) * rng.randf_range(0.65, 1.35),
				"collision_radius_m": lerpf(min_collision_radius_m, max_collision_radius_m, pow(rng.randf(), 4.0))
			})
		solar_belt_particles.append({
			"name": str(belt.get("name", "Small-body belt")),
			"color": PlanetarySystem.color_from_rgb(belt.get("color_rgb", []), Color(0.72, 0.65, 0.52)),
			"opacity": float(belt.get("opacity", 0.35)),
			"inner_radius_m": inner_radius_m,
			"outer_radius_m": outer_radius_m,
			"max_collision_radius_m": max_collision_radius_m,
			"particles": particles
		})

func _process(delta: float) -> void:
	_update_collision_effects(delta)
	if not paused and not crashed:
		var current_body := _nearest_body_state(rocket_position)
		var altitude: float = maxf(0.0, float(current_body.distance) - float(current_body.radius))
		var atmosphere_height: float = PlanetarySystem.planetary_atmosphere_height(str(current_body.get("name", "Earth")))
		var near_atmosphere: bool = float(current_body.distance) < float(current_body.soi) and altitude < atmosphere_height
		var effective_warp: float = minf(time_warp, 100.0) if near_atmosphere else time_warp
		simulation_time_backlog = effective_warp * delta
		var iterations := 0
		var physics_budget_start_usec: int = Time.get_ticks_usec()
		while simulation_time_backlog > 0.000001 and iterations < MAX_PHYSICS_STEPS_PER_FRAME and Time.get_ticks_usec() - physics_budget_start_usec < MAX_PHYSICS_BUDGET_USEC:
			var step_delta: float = minf(simulation_time_backlog, _adaptive_step_size())
			if step_delta <= 0.000001:
				break
			_physics_step(step_delta)
			simulation_time_backlog = maxf(0.0, simulation_time_backlog - step_delta)
			iterations += 1
		simulation_time_backlog = 0.0
	else:
		simulation_time_backlog = 0.0
	if show_predicted_trajectory:
		prediction_timer += delta
		if prediction_timer >= 0.35:
			prediction_timer = 0.0
			_calculate_predicted_trajectory()
	trail_timer += delta
	if trail_timer >= 0.12:
		trail_timer = 0.0
		trail.append(rocket_position)
		if trail.size() > 450:
			trail.pop_front()
	queue_redraw()

func next_autopilot_event_time() -> float:
	if autopilot_enabled:
		match autopilot_phase:
			"WAIT_WINDOW":
				return float(autopilot_precomputed_transfer_plan.get("departure_time_seconds", -1.0))
			"ROUTE_COAST":
				if autopilot_route_node_index < autopilot_route_nodes.size():
					return float(autopilot_route_nodes[autopilot_route_node_index].get("time", -1.0))
			_:
				return -1.0
	var plan: Dictionary = manual_flight_plan
	if not plan.is_empty() and bool(plan.get("active", false)) and str(plan.get("phase", "")) == "WAIT_DEPARTURE":
		return float(plan.get("departure_time", -1.0))
	return -1.0

func _physics_step(dt: float) -> void:
	var start_time := sim_time
	var end_time := sim_time + dt
	if landed:
		if thrust_key_down and (infinite_weightless_fuel or fuel > 0.0):
			var surface_state := _surface_body_state(landed_body_name)
			var normal := landed_surface_normal.normalized()
			rotation_angle = normal.angle() - Vector2.UP.angle()
			angular_velocity = 0.0
			_set_rocket_position_relative_to_body(surface_state, normal * (float(surface_state.radius) + 5.0))
			velocity = surface_state.velocity + Vector2(-normal.y, normal.x) * float(surface_state.radius) * float(surface_state.rotation_rate)
			landed = false
			status_message = "LAUNCHING FROM %s" % landed_body_name.to_upper()
		else:
			sim_time = end_time
			var landed_surface_state := _surface_body_state(landed_body_name)
			landed_surface_normal = landed_surface_normal.rotated(float(landed_surface_state.rotation_rate) * dt).normalized()
			_set_rocket_position_relative_to_body(landed_surface_state, landed_surface_normal * (float(landed_surface_state.radius) + 0.5))
			velocity = landed_surface_state.velocity + Vector2(-landed_surface_normal.y, landed_surface_normal.x) * float(landed_surface_state.radius) * float(landed_surface_state.rotation_rate)
			throttle = 0.0
			return
	var initial_rocket_position_components: PackedFloat64Array = rocket_position_precise.duplicate()
	var local_body := _nearest_body_state(rocket_position)
	var altitude := maxf(0.0, float(local_body.get("distance", EARTH_RADIUS)) - float(local_body.get("radius", EARTH_RADIUS)))
	if not crashed and guidance_enabled:
		_update_guidance(dt)
	if not crashed and autopilot_enabled and autopilot_phase in ["COAST", "COAST_TO_TARGET", "WAIT_WINDOW", "ALIGN_DEPARTURE", "TRANSFER_COAST", "ARRIVAL_APPROACH", "ARRIVAL_PENDING", "ROUTE_COAST", "COMPLETE", "FAILED"]:
		thrust_key_down = false
	var active := _active_stage_data()
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	var rcs_translation_input: Vector2 = Vector2.ZERO
	var flight_controls_blocked := _flight_input_blocked_by_gui()
	if has_rcs() and input_enabled and not flight_controls_blocked:
		rcs_translation_input = Vector2(
			float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
		).limit_length(1.0)
		if not autopilot_enabled:
			var rotate_right := Input.is_action_pressed("rotate_right") or Input.is_physical_key_pressed(KEY_D)
			var rotate_left := Input.is_action_pressed("rotate_left") or Input.is_physical_key_pressed(KEY_A)
			rcs_rotation_input = float(rotate_right) - float(rotate_left)
			rcs_rotation_scale = 1.0 if absf(rcs_rotation_input) > 0.001 else 0.0
	elif not autopilot_enabled:
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0
	var initial_rcs_mass_properties := _vehicle_mass_properties()
	var rcs_profile := _rcs_force_profile(rcs_translation_input, rcs_rotation_input, Vector2(initial_rcs_mass_properties.center_of_mass))
	var rcs_control_scale := clampf(rcs_rotation_scale, 0.0, 1.0) if absf(rcs_rotation_input) > 0.001 else 1.0
	var rcs_flow_rate := float(rcs_profile.flow) * rcs_control_scale
	var rcs_fuel_used := minf(rcs_propellant_remaining, rcs_flow_rate * dt) if not crashed else 0.0
	var propellant_available := not crashed and (infinite_weightless_fuel or fuel > 0.0 or resource_amount("xenon") > 0.0 or resource_amount("solid_propellant") > 0.0)
	var solid_motor_burning := _has_ignited_solid_motor() and resource_amount("solid_propellant") > 0.0
	throttle = 1.0 if solid_motor_burning else (autopilot_throttle if not crashed and autopilot_enabled and autopilot_phase == "LANDING_DESCENT" and propellant_available else (1.0 if not crashed and thrust_key_down and propellant_available else 0.0))
	var available_liquid := resource_amount("liquid_propellant")
	var fuel_used := minf(infinite_fuel_stage_remaining, total_flow * throttle * dt) if infinite_weightless_fuel and total_flow > 0.0 else (minf(available_liquid, total_flow * throttle * dt) if total_flow > 0.0 else 0.0)
	var effective_fuel := infinite_fuel_stage_remaining if infinite_weightless_fuel else -1.0
	var mass_before := maxf(1.0, _current_vehicle_mass(effective_fuel))
	var mass_after := maxf(1.0, mass_before - fuel_used - rcs_fuel_used)
	var engine_mass_after: float = maxf(1.0, mass_before - fuel_used)
	var mass_mid := (mass_before + mass_after) * 0.5
	var initial_atmosphere: Dictionary = {}
	if realism != "Arcade" or throttle > 0.0:
		initial_atmosphere = _atmosphere_at(rocket_position, velocity, start_time, rocket_position_precise)
	var thrust_force_vector_local := Vector2.ZERO
	var angular_acceleration := 0.0
	var initial_rotation_angle := rotation_angle
	var initial_angular_velocity := angular_velocity
	var thrust_force := 0.0
	var engine_profile: Dictionary = {"force": Vector2.ZERO, "torque": 0.0, "resource_flows": {}, "electric_draw_w": 0.0}
	if throttle > 0.0:
		var pressure_ratio := float(initial_atmosphere.get("density", 0.0)) * float(initial_atmosphere.get("gas_constant", PlanetarySystem.earth_atmosphere_gas_constant())) * float(initial_atmosphere.get("temperature", 250.0)) / 101325.0
		var midpoint_fuel := maxf(0.0, (effective_fuel if infinite_weightless_fuel else fuel) - fuel_used * 0.5)
		var midpoint_rcs_fuel := maxf(0.0, rcs_propellant_remaining - rcs_fuel_used * 0.5)
		var mass_properties := _vehicle_mass_properties(midpoint_fuel, midpoint_rcs_fuel)
		engine_profile = _engine_force_profile(Vector2(mass_properties.center_of_mass), pressure_ratio, throttle)
		thrust_force_vector_local = Vector2(engine_profile.force)
		thrust_force = thrust_force_vector_local.length()
		angular_acceleration = float(engine_profile.torque) / float(mass_properties.moment_of_inertia)
	var additional_propellant_used := 0.0
	for resource in engine_profile.get("resource_flows", {}):
		if str(resource) != "liquid_propellant":
			additional_propellant_used += _consume_resource(str(resource), float(engine_profile.resource_flows[resource]) * throttle * dt)
	_consume_resource("electricity", float(engine_profile.get("electric_draw_w", 0.0)) * throttle * dt)
	_fill_resource_tanks("electricity", _solar_generation_rate() * dt)
	mass_after = maxf(1.0, mass_before - fuel_used - rcs_fuel_used - additional_propellant_used)
	mass_mid = (mass_before + mass_after) * 0.5
	var rcs_impulse_local: Vector2 = Vector2.ZERO
	if rcs_fuel_used > 0.0 and rcs_flow_rate > 0.0:
		var rcs_power_scale := rcs_fuel_used / maxf(0.000001, rcs_flow_rate * dt)
		var rcs_force: Vector2 = Vector2(rcs_profile.force) * rcs_power_scale * rcs_control_scale
		rcs_impulse_local = rcs_force / mass_mid * dt
		var current_inertia: float = float(_vehicle_mass_properties(-1.0, maxf(0.0, rcs_propellant_remaining - rcs_fuel_used * 0.5)).get("moment_of_inertia", 1.0))
		angular_acceleration += float(rcs_profile.torque) * rcs_power_scale * rcs_control_scale / maxf(1.0, current_inertia)
	angular_velocity = initial_angular_velocity + angular_acceleration * dt
	rotation_angle = wrapf(initial_rotation_angle + initial_angular_velocity * dt + 0.5 * angular_acceleration * dt * dt, -PI, PI)
	var thrust_delta_v := 0.0
	if fuel_used > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
		thrust_delta_v = thrust_force / total_flow * log(mass_before / engine_mass_after)
	elif throttle > 0.0 and thrust_force > 0.0:
		thrust_delta_v = thrust_force / mass_mid * dt
	if infinite_weightless_fuel:
		infinite_fuel_stage_remaining = maxf(0.0, infinite_fuel_stage_remaining - fuel_used)
	else:
		_consume_resource("liquid_propellant", fuel_used)
		_sync_legacy_fuel_from_tanks()
	_consume_rcs_propellant(rcs_fuel_used)
	var average_rotation_angle := initial_rotation_angle + initial_angular_velocity * dt * 0.5 + angular_acceleration * dt * dt / 6.0
	var engine_impulse := thrust_force_vector_local.normalized() * thrust_delta_v if thrust_force_vector_local.length_squared() > 0.0 else Vector2.ZERO
	var thrust_impulse := (engine_impulse + rcs_impulse_local).rotated(average_rotation_angle)
	engine_impulse = engine_impulse.rotated(average_rotation_angle)
	if manual_burn_tracking_enabled and not autopilot_enabled and thrust_delta_v > 0.0:
		manual_burn_accumulated_vector += engine_impulse
	if autopilot_enabled and autopilot_phase in ["CIRCULARISE_BURN", "TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"] and thrust_delta_v > 0.0:
		autopilot_burn_remaining = maxf(0.0, autopilot_burn_remaining - thrust_delta_v)
		if autopilot_burn_remaining <= FlightComputer.BURN_COMPLETION_TOLERANCE:
			thrust_key_down = false
			if autopilot_phase == "CIRCULARISE_BURN":
				var apsis_body := _nearest_body_state(rocket_position, rocket_position_precise)
				autopilot_apsis_correction_armed = false
				autopilot_apsis_correction_angle = apsis_body.relative_position.angle()
				autopilot_phase = "COAST_TO_TARGET"
				status_message = "AUTOPILOT  •  COASTING TO TARGET ORBIT"
			elif autopilot_phase == "TRANSFER_BURN":
				autopilot_transfer_start_time = sim_time
				autopilot_phase = "TRANSFER_COAST"
			elif autopilot_phase == "ARRIVAL_CAPTURE_BURN":
				var arrival_state := _autopilot_target_state()
				var arrival_position := _relative_position_to_body(arrival_state)
				var arrival_velocity: Vector2 = velocity + thrust_impulse - arrival_state.velocity
				var arrival_orbit := FlightComputer.orbital_state(arrival_position, arrival_velocity, G * float(arrival_state.mass))
				var arrival_minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(str(arrival_state.get("name", "")), float(arrival_state.radius))
				if bool(arrival_orbit.get("bound", false)) and float(arrival_orbit.get("periapsis", 0.0)) > float(arrival_state.radius) + arrival_minimum_safe_altitude:
					autopilot_apsis_correction_armed = false
					autopilot_apsis_correction_angle = _relative_position_to_body(arrival_state).angle()
					autopilot_phase = "COAST_TO_TARGET"
				else:
					_fail_autopilot("ARRIVAL BURN DID NOT PRODUCE A SAFE ORBIT")
			elif autopilot_phase == "ROUTE_BURN":
				autopilot_route_node_index += 1
				if autopilot_route_node_index < autopilot_route_nodes.size():
					autopilot_phase = "ROUTE_COAST"
					status_message = "AUTOPILOT  •  COASTING TO NEXT MANOEUVRE"
				else:
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
					status_message = "AUTOPILOT  •  ROUTE COMPLETE"
			else:
				autopilot_phase = "COMPLETE"
				autopilot_complete = true
				status_message = "AUTOPILOT  •  MANOEUVRE BURN COMPLETE"
	var initial_gravity_states: Dictionary = _ephemeris_states_at(start_time)
	var final_gravity_states: Dictionary = _ephemeris_states_at(end_time)
	var initial_gravity := PlanetarySystem.gravity_acceleration_from_precise_states(rocket_position_precise, initial_gravity_states)
	var initial_aero := _aerodynamic_acceleration(rocket_position, velocity, mass_mid, start_time, rocket_position_precise, initial_atmosphere)
	var half_velocity := velocity + (initial_gravity + initial_aero) * (0.5 * dt) + thrust_impulse * 0.5
	var next_position_components := PackedFloat64Array([
		rocket_position_precise[0] + half_velocity.x * dt,
		rocket_position_precise[1] + half_velocity.y * dt
	])
	var next_position := Vector2(next_position_components[0], next_position_components[1])
	var final_gravity := PlanetarySystem.gravity_acceleration_from_precise_states(next_position_components, final_gravity_states)
	var final_atmosphere: Dictionary = _atmosphere_at(next_position, half_velocity, end_time, next_position_components)
	var final_aero := _aerodynamic_acceleration(next_position, half_velocity, mass_mid, end_time, next_position_components, final_atmosphere)
	velocity = half_velocity + (final_gravity + final_aero) * (0.5 * dt) + thrust_impulse * 0.5
	final_atmosphere["relative_velocity"] = Vector2(final_atmosphere.get("relative_velocity", Vector2.ZERO)) + velocity - half_velocity
	_set_rocket_position_components(next_position_components[0], next_position_components[1])
	sim_time = end_time
	if not infinite_weightless_fuel:
		fuel = maxf(0.0, fuel - fuel_used)
		if stage_index < stage_fuel_remaining.size():
			stage_fuel_remaining[stage_index] = fuel
	_update_flight_environment(final_atmosphere)
	_update_heating(dt, final_atmosphere)
	if not crashed:
		if infinite_weightless_fuel and infinite_fuel_stage_remaining <= 0.0001 and stage_index < rocket_stages.size() - 1:
			_separate_stage()
		elif not infinite_weightless_fuel and fuel <= 0.0001 and resource_amount("xenon") <= 0.0001 and resource_amount("solid_propellant") <= 0.0001 and stage_index < rocket_stages.size() - 1:
			_separate_stage()
	_handle_body_contact()
	if simulate_belt_collisions and not crashed and not landed:
		var collision: Dictionary = _small_body_collision(
			start_time,
			end_time,
			initial_rocket_position_components,
			rocket_position_precise,
			initial_gravity_states,
			final_gravity_states
		)
		if not collision.is_empty():
			crashed = true
			landed = false
			thrust_key_down = false
			throttle = 0.0
			guidance_enabled = false
			autopilot_enabled = false
			status_message = "ASTEROID IMPACT  •  %s  •  %.0f M/S" % [str(collision.get("belt_name", "SMALL BODY")).to_upper(), float(collision.get("impact_speed_m_s", 0.0))]
	var final_body := _nearest_body_state(rocket_position)
	var final_altitude := maxf(0.0, float(final_body.get("distance", EARTH_RADIUS)) - float(final_body.get("radius", EARTH_RADIUS)))
	if not autopilot_enabled and not landed and not crashed:
		status_message = "STAGE %d  •  ENGINE FIRING" % (stage_index + 1) if throttle > 0.0 else "PAD READY  •  W TO IGNITE" if final_altitude < 100.0 else "FLIGHT ACTIVE"

func _small_body_collision(start_time: float, end_time: float, rocket_start_components: PackedFloat64Array, rocket_end_components: PackedFloat64Array, start_states: Dictionary, end_states: Dictionary) -> Dictionary:
	var earth_start: PackedFloat64Array = start_states.get("earth_heliocentric_position_components", PackedFloat64Array([0.0, 0.0]))
	var earth_end: PackedFloat64Array = end_states.get("earth_heliocentric_position_components", PackedFloat64Array([0.0, 0.0]))
	var rocket_start_x: float = earth_start[0] + rocket_start_components[0]
	var rocket_start_y: float = earth_start[1] + rocket_start_components[1]
	var rocket_end_x: float = earth_end[0] + rocket_end_components[0]
	var rocket_end_y: float = earth_end[1] + rocket_end_components[1]
	var radial_start := sqrt(rocket_start_x * rocket_start_x + rocket_start_y * rocket_start_y)
	var radial_end := sqrt(rocket_end_x * rocket_end_x + rocket_end_y * rocket_end_y)
	var radial_min := minf(radial_start, radial_end)
	var radial_max := maxf(radial_start, radial_end)
	var duration := maxf(0.000001, end_time - start_time)
	for belt_variant in solar_belt_particles:
		var belt: Dictionary = belt_variant
		var maximum_radius := float(belt.get("max_collision_radius_m", 0.0))
		var belt_inner := float(belt.get("inner_radius_m", 0.0)) - maximum_radius
		var belt_outer := float(belt.get("outer_radius_m", 0.0)) + maximum_radius
		if radial_max < belt_inner or radial_min > belt_outer:
			continue
		for particle_variant in belt.get("particles", []):
			var particle: Dictionary = particle_variant
			var body_radius := float(particle.get("radius_m", 0.0))
			var phase := float(particle.get("phase_rad", 0.0))
			var angular_rate := float(particle.get("angular_rate", 0.0))
			var start_angle := phase + angular_rate * start_time
			var end_angle := phase + angular_rate * end_time
			var asteroid_start_x := cos(start_angle) * body_radius
			var asteroid_start_y := sin(start_angle) * body_radius
			var asteroid_end_x := cos(end_angle) * body_radius
			var asteroid_end_y := sin(end_angle) * body_radius
			var relative_start_x := rocket_start_x - asteroid_start_x
			var relative_start_y := rocket_start_y - asteroid_start_y
			var relative_delta_x := (rocket_end_x - asteroid_end_x) - relative_start_x
			var relative_delta_y := (rocket_end_y - asteroid_end_y) - relative_start_y
			var denominator := relative_delta_x * relative_delta_x + relative_delta_y * relative_delta_y
			var closest_fraction := 0.0
			if denominator > 0.0:
				closest_fraction = clampf(-(relative_start_x * relative_delta_x + relative_start_y * relative_delta_y) / denominator, 0.0, 1.0)
			var closest_x := relative_start_x + relative_delta_x * closest_fraction
			var closest_y := relative_start_y + relative_delta_y * closest_fraction
			var collision_radius := float(particle.get("collision_radius_m", 0.0)) + 10.0
			if closest_x * closest_x + closest_y * closest_y <= collision_radius * collision_radius:
				return {
					"belt_name": belt.get("name", "Small-body belt"),
					"particle_id": particle.get("id", -1),
					"impact_speed_m_s": sqrt(denominator) / duration
				}
	return {}

func _adaptive_step_size() -> float:
	var body := _nearest_body_state(rocket_position, rocket_position_precise)
	var radius: float = maxf(float(body.radius), float(body.distance))
	var altitude: float = maxf(0.0, float(body.distance) - float(body.radius))
	var gravity: float = G * float(body.mass) / (radius * radius)
	var orbital_limit: float = 0.002 * sqrt(radius / maxf(0.001, gravity))
	var relative_position: Vector2 = body.relative_position
	var relative_velocity: Vector2 = velocity - Vector2(body.velocity)
	var local_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, G * float(body.mass))
	var speed: float = relative_velocity.length()
	var deep_space: bool = altitude > 1.0e8
	var atmosphere_height: float = PlanetarySystem.planetary_atmosphere_height(str(body.get("name", "Earth")))
	var in_atmosphere: bool = altitude < atmosphere_height
	var maximum_step: float = 0.25 if in_atmosphere else 1800.0
	var travel_distance_limit: float = 250.0 if in_atmosphere else maxf(100000.0, radius * 0.01)
	if bool(local_orbit.get("bound", false)) and not in_atmosphere:
		maximum_step = minf(maximum_step, 0.5)
		travel_distance_limit = minf(travel_distance_limit, maxf(1000.0, radius * 0.002))
	if autopilot_enabled and autopilot_phase == "COAST_TO_TARGET":
		maximum_step = minf(maximum_step, 10.0)
	if deep_space:
		travel_distance_limit = maxf(50000000.0, radius * 0.01)
	var travel_limit: float = travel_distance_limit / maxf(100.0, speed)
	var drag_acceleration := 0.0
	if realism != "Arcade" and in_atmosphere:
		drag_acceleration = _aerodynamic_acceleration(rocket_position, velocity, maxf(1.0, _current_vehicle_mass()), -1.0, rocket_position_precise).length()
	var drag_limit := 0.08 * speed / drag_acceleration if drag_acceleration > 0.01 else maximum_step
	var active := _active_stage_data()
	var effective_fuel := infinite_fuel_stage_remaining if infinite_weightless_fuel else -1.0
	var engine_acceleration := _engine_thrust(altitude) / maxf(1.0, _current_vehicle_mass(effective_fuel)) if thrust_key_down and (infinite_weightless_fuel or fuel > 0.0) else 0.0
	var thrust_limit := 0.08 * maxf(100.0, speed) / engine_acceleration if engine_acceleration > 0.01 else maximum_step
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	var burnout_fuel := infinite_fuel_stage_remaining if infinite_weightless_fuel else fuel
	var has_burnout_limit := not infinite_weightless_fuel or stage_index < rocket_stages.size() - 1
	var burnout_limit := burnout_fuel / total_flow if thrust_key_down and has_burnout_limit and burnout_fuel > 0.0 and total_flow > 0.0 else maximum_step
	var physics_limit := clampf(minf(minf(orbital_limit, travel_limit), minf(drag_limit, thrust_limit)), 0.0005, maximum_step)
	var step_limit := minf(physics_limit, burnout_limit)
	if autopilot_enabled and autopilot_phase in ["CIRCULARISE_BURN", "TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"] and not thrust_key_down:
		step_limit = minf(step_limit, 0.1)
	if autopilot_enabled and autopilot_phase in ["CIRCULARISE_BURN", "TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"] and autopilot_burn_remaining > 0.0:
		var current_mass := maxf(1.0, _current_vehicle_mass(effective_fuel))
		var current_thrust := _engine_thrust(altitude)
		if infinite_weightless_fuel:
			var acceleration := current_thrust / current_mass
			if acceleration > 0.0:
				step_limit = minf(step_limit, autopilot_burn_remaining / acceleration)
		elif total_flow > 0.0:
			var effective_exhaust_velocity := current_thrust / total_flow
			if effective_exhaust_velocity > 0.0:
				var required_propellant := current_mass * (1.0 - exp(-autopilot_burn_remaining / effective_exhaust_velocity))
				step_limit = minf(step_limit, required_propellant / total_flow)
	if autopilot_enabled and autopilot_phase == "COAST":
		var coast_orbit: Dictionary = FlightComputer.orbital_state(body.relative_position, velocity - Vector2(body.velocity), G * float(body.mass))
		var coast_radial_speed: float = absf(float(coast_orbit.get("radial_speed", 0.0)))
		var body_name := str(body.get("name", ""))
		var body_minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(body_name, float(body.radius))
		var body_maximum_stable_altitude := FlightComputer.maximum_stable_orbit_altitude(float(body.radius), float(body.get("soi", 0.0)))
		var parking_altitude := clampf(200000.0, body_minimum_safe_altitude, maxf(body_minimum_safe_altitude, body_maximum_stable_altitude))
		var coast_orbit_altitude := autopilot_target_altitude if body_name == _autopilot_target_body_name() and float(body.get("distance", INF)) <= float(body.get("soi", 0.0)) else parking_altitude
		if bool(coast_orbit.get("bound", false)) and coast_radial_speed < 500.0 and float(coast_orbit.get("apoapsis", 0.0)) >= float(body.radius) + coast_orbit_altitude * 0.95:
			step_limit = minf(step_limit, 10.0)
	if autopilot_enabled and autopilot_phase == "ROUTE_COAST" and autopilot_route_node_index < autopilot_route_nodes.size():
		var next_node: Dictionary = autopilot_route_nodes[autopilot_route_node_index]
		var time_until_node: float = maxf(0.0, float(next_node.get("time", sim_time)) - sim_time)
		if time_until_node > 0.0:
			step_limit = minf(step_limit, time_until_node)
	var rotation_throttle := 1.0 if thrust_key_down else (autopilot_throttle if autopilot_enabled and autopilot_phase == "LANDING_DESCENT" else 0.0)
	if rotation_throttle > 0.0 and not crashed:
		var rotation_atmosphere := _atmosphere_at(rocket_position, velocity)
		var rotation_pressure_ratio := float(rotation_atmosphere.get("density", 0.0)) * float(rotation_atmosphere.get("gas_constant", PlanetarySystem.earth_atmosphere_gas_constant())) * float(rotation_atmosphere.get("temperature", 250.0)) / 101325.0
		var rotation_fuel := infinite_fuel_stage_remaining if infinite_weightless_fuel else fuel
		var rotation_mass := _vehicle_mass_properties(rotation_fuel)
		var rotation_profile := _engine_force_profile(Vector2(rotation_mass.center_of_mass), rotation_pressure_ratio, rotation_throttle)
		var rotation_acceleration := absf(float(rotation_profile.torque) / float(rotation_mass.moment_of_inertia))
		if rotation_acceleration > 0.000001:
			step_limit = minf(step_limit, sqrt(0.08 / rotation_acceleration))
	if absf(angular_velocity) > 0.000001:
		step_limit = minf(step_limit, 0.08 / absf(angular_velocity))
	if has_rcs() and (rcs_rotation_input != 0.0 or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN)):
		var rcs_system := _remaining_rcs_system()
		var rcs_mass := maxf(1.0, _current_vehicle_mass())
		var rcs_linear_acceleration := float(rcs_system.thrust) / rcs_mass
		var rcs_angular_acceleration := float(rcs_system.torque) / maxf(1.0, float(_vehicle_mass_properties().moment_of_inertia))
		if rcs_linear_acceleration > 0.001:
			step_limit = minf(step_limit, sqrt(0.08 / rcs_linear_acceleration))
		if rcs_angular_acceleration > 0.000001:
			step_limit = minf(step_limit, sqrt(0.08 / rcs_angular_acceleration))
	if autopilot_enabled and autopilot_phase in ["TRANSFER_COAST", "ARRIVAL_APPROACH"]:
		var destination_state := _autopilot_target_state()
		var relative_distance := _relative_position_to_body(destination_state).length()
		var relative_speed: float = (velocity - Vector2(destination_state.velocity)).length()
		if relative_speed > 1.0:
			step_limit = minf(step_limit, 0.02 * relative_distance / relative_speed)
	return step_limit

func _atmosphere_at(position: Vector2, current_velocity: Vector2, time_seconds: float = -1.0, position_components: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var sample_time := sim_time if time_seconds < 0.0 else time_seconds
	var best := {
		"body_name": "",
		"altitude": 0.0,
		"density": 0.0,
		"temperature": 250.0,
		"gas_constant": PlanetarySystem.earth_atmosphere_gas_constant(),
		"gamma": PlanetarySystem.earth_atmosphere_gamma(),
		"relative_velocity": Vector2.ZERO
	}
	var components := position_components
	if components.size() < 2:
		components = rocket_position_precise if position == rocket_position else PackedFloat64Array([position.x, position.y])
	var position_radius := sqrt(components[0] * components[0] + components[1] * components[1])
	var earth_altitude := position_radius - EARTH_RADIUS
	var earth_density := PlanetarySystem.atmospheric_density(earth_altitude)
	if earth_density > 0.0:
		best = {
			"body_name": "Earth",
			"altitude": earth_altitude,
			"density": earth_density,
			"temperature": PlanetarySystem.atmospheric_temperature(earth_altitude),
			"gas_constant": PlanetarySystem.earth_atmosphere_gas_constant(),
			"gamma": PlanetarySystem.earth_atmosphere_gamma(),
			"relative_velocity": current_velocity - Vector2(-components[1], components[0]) * EARTH_ROTATION_RATE
		}
	var ephemeris: Dictionary = _ephemeris_states_at(sample_time)
	for body in ephemeris.get("surface_bodies", []):
		var body_name: String = str(body.get("name", ""))
		if body_name == "Earth":
			continue
		var body_velocity: Vector2 = body.get("velocity", Vector2.ZERO)
		var body_components := _body_position_components(body)
		var relative_position := Vector2(components[0] - body_components[0], components[1] - body_components[1])
		var body_altitude: float = relative_position.length() - float(body.get("radius", 0.0))
		var density: float = PlanetarySystem.planetary_atmosphere_density(body_name, body_altitude)
		if density <= float(best.get("density", 0.0)):
			continue
		var atmospheric_rotation: Vector2 = Vector2(-relative_position.y, relative_position.x) * float(body.get("rotation_rate", 0.0))
		var gas_constant := PlanetarySystem.planetary_atmosphere_gas_constant(body_name)
		var gamma := PlanetarySystem.planetary_atmosphere_gamma(body_name)
		best = {
			"body_name": body_name,
			"altitude": body_altitude,
			"density": density,
			"temperature": PlanetarySystem.planetary_atmosphere_temperature(body_name),
			"gas_constant": gas_constant,
			"gamma": gamma,
			"relative_velocity": current_velocity - body_velocity - atmospheric_rotation
		}
	return best

func _engine_thrust(altitude: float, atmosphere_override: Dictionary = {}) -> float:
	var active := _active_stage_data()
	var atmosphere := atmosphere_override if not atmosphere_override.is_empty() else _atmosphere_at(rocket_position, velocity)
	var ambient_pressure_ratio := float(atmosphere.density) * float(atmosphere.gas_constant) * float(atmosphere.temperature) / 101325.0
	var sea_level_thrust := float(active.get("thrust", 0.0))
	var vacuum_thrust := float(active.get("vacuum_thrust", 0.0))
	return lerpf(vacuum_thrust, sea_level_thrust, clampf(ambient_pressure_ratio, 0.0, 1.0)) * float(active.get("engine_count", 1))

func _aerodynamic_acceleration(position: Vector2, current_velocity: Vector2, mass: float, time_seconds: float = -1.0, position_components: PackedFloat64Array = PackedFloat64Array(), atmosphere_override: Dictionary = {}) -> Vector2:
	if realism == "Arcade":
		return Vector2.ZERO
	var atmosphere := atmosphere_override if not atmosphere_override.is_empty() else _atmosphere_at(position, current_velocity, time_seconds, position_components)
	var density := float(atmosphere.density)
	var relative_velocity: Vector2 = atmosphere.relative_velocity
	var relative_speed := relative_velocity.length()
	if density <= 0.0 or relative_speed < 0.01:
		return Vector2.ZERO
	var direction := relative_velocity / relative_speed
	var dynamic_pressure := 0.5 * density * relative_speed * relative_speed
	var drag_coefficient := 0.35
	var lift_force := 0.0
	if realism in ["Realistic", "Hardcore"]:
		var nose := Vector2.UP.rotated(rotation_angle + gimbal_angle)
		var angle_of_attack := asin(clampf(nose.cross(direction), -1.0, 1.0))
		var temperature := float(atmosphere.temperature)
		var speed_of_sound := sqrt(float(atmosphere.gamma) * float(atmosphere.gas_constant) * temperature)
		var mach := relative_speed / maxf(1.0, speed_of_sound)
		drag_coefficient = 0.22 + 0.28 * exp(-pow((mach - 1.0) / 0.3, 2.0)) + 0.08 * pow(sin(angle_of_attack), 2.0)
		if realism == "Hardcore":
			drag_coefficient += 0.12 + 0.18 * pow(sin(angle_of_attack), 2.0)
			lift_force = dynamic_pressure * LIFT_AREA * sin(2.0 * angle_of_attack) * (0.45 if realism == "Hardcore" else 0.35)
	var drag_force := dynamic_pressure * DRAG_AREA * drag_coefficient
	var lift_direction := Vector2(-direction.y, direction.x)
	return -direction * (drag_force / maxf(1.0, mass)) + lift_direction * (lift_force / maxf(1.0, mass))

func _update_flight_environment(atmosphere: Dictionary) -> void:
	var density := float(atmosphere.density)
	if density <= 0.0:
		mach_number = 0.0
		dynamic_pressure_pa = 0.0
		return
	var relative_velocity: Vector2 = atmosphere.relative_velocity
	var relative_speed := relative_velocity.length()
	var temperature := float(atmosphere.temperature)
	mach_number = relative_speed / sqrt(float(atmosphere.gamma) * float(atmosphere.gas_constant) * temperature)
	dynamic_pressure_pa = 0.5 * density * relative_speed * relative_speed
	max_dynamic_pressure_pa = maxf(max_dynamic_pressure_pa, dynamic_pressure_pa)

func _update_heating(dt: float, atmosphere: Dictionary) -> void:
	if realism == "Arcade":
		heat_flux_mw = 0.0
		return
	var density := float(atmosphere.density)
	var relative_velocity: Vector2 = atmosphere.relative_velocity
	var heat_flux_w := 0.0
	if density > 0.0:
		var nose_radius := 0.5
		heat_flux_w = 1.83e-4 * sqrt(density / nose_radius) * pow(relative_velocity.length(), 3.0)
	if realism == "Standard":
		heat_flux_w *= 0.65
	heat_flux_mw = heat_flux_w / 1000000.0
	peak_heat_flux_mw = maxf(peak_heat_flux_mw, heat_flux_mw)
	var absorbed_flux := heat_flux_w * (0.22 if realism == "Hardcore" else 0.15)
	var radiated_flux := 0.82 * 5.670374419e-8 * (pow(heat_shield_temperature, 4.0) - pow(290.0, 4.0))
	var temperature_rate := (absorbed_flux - radiated_flux) / 60000.0
	heat_shield_temperature = maxf(290.0, heat_shield_temperature + temperature_rate * dt)

func _separate_stage() -> void:
	if stage_index >= rocket_stages.size() - 1:
		return
	if stage_index < stage_fuel_remaining.size():
		stage_fuel_remaining[stage_index] = fuel
	_reconcile_legacy_fuel_inventory()
	var separated_stage: Dictionary = rocket_stages[stage_index].duplicate(true)
	var separated_fuel := fuel
	var separated_rcs_capacity := RocketDesign.stage_rcs_propellant_capacity(separated_stage)
	var total_rcs_capacity := _own_rcs_propellant_capacity()
	var own_rcs_remaining := maxf(0.0, rcs_propellant_remaining - _external_rcs_propellant_total())
	var separated_rcs_fuel := own_rcs_remaining * separated_rcs_capacity / total_rcs_capacity if total_rcs_capacity > 0.0 else 0.0
	var separated_resource_tanks: Array = []
	var remaining_resource_tanks: Array = []
	var separated_resource_mass := 0.0
	for tank in resource_tanks:
		if str(tank.get("module_id", vehicle_name)) == vehicle_name and int(tank.get("stage_index", -1)) == stage_index:
			separated_resource_tanks.append(tank.duplicate(true))
			separated_resource_mass += float(tank.get("resources", {}).get("xenon", 0.0)) + float(tank.get("resources", {}).get("solid_propellant", 0.0))
		else:
			remaining_resource_tanks.append(tank.duplicate(true))
	var dockable_module := stage_separation_is_dockable_module()
	var separated_dry_mass := RocketDesign.stage_total_dry_mass(separated_stage)
	var separated_mass := separated_dry_mass + separated_fuel + separated_rcs_fuel + separated_resource_mass
	var vehicle_mass_before := _current_vehicle_mass()
	var upper_stack_mass := maxf(0.001, vehicle_mass_before - separated_mass)
	var total_separated_mass := maxf(0.001, separated_mass + upper_stack_mass)
	var separation_direction := Vector2.UP.rotated(rotation_angle)
	var relative_separation_speed := 2.0
	separation_grace_until = sim_time + 12.0
	var debris_velocity := velocity - separation_direction * relative_separation_speed * upper_stack_mass / total_separated_mass
	var upper_stack_velocity := velocity + separation_direction * relative_separation_speed * separated_mass / total_separated_mass
	stage_separated.emit({
		"stage": separated_stage,
		"fuel": separated_fuel,
		"rcs_fuel": separated_rcs_fuel,
		"resource_tanks": separated_resource_tanks,
		"dockable_module": dockable_module,
		"position_components": rocket_position_precise.duplicate(),
		"velocity": debris_velocity,
		"rotation_angle": rotation_angle,
		"angular_velocity": angular_velocity,
		"sim_time": sim_time,
		"launch_time": launch_time,
		"parent_vehicle_name": vehicle_name,
		"separation_speed": relative_separation_speed
	})
	discarded_stage_mass += separated_dry_mass
	discarded_propellant_mass += separated_fuel
	if stage_index < stage_fuel_remaining.size():
		stage_fuel_remaining[stage_index] = 0.0
	rcs_propellant_remaining = maxf(0.0, rcs_propellant_remaining - separated_rcs_fuel)
	resource_tanks = remaining_resource_tanks
	velocity = upper_stack_velocity
	stage_index += 1
	_sync_legacy_fuel_from_tanks()
	infinite_fuel_stage_remaining = fuel
	thrust_key_down = false


func _release_component_group(port_uid: String) -> bool:
	if resource_inventory_external or docked_mass > 0.001:
		return false
	var group_id := ""
	var port_stage_index := -1
	var port_offset := Vector2.ZERO
	var separation_direction := Vector2.UP
	var total_length := 0.0
	var geometries: Array[Dictionary] = []
	for stage in rocket_stages:
		var geometry := RocketAssembly.stage_geometry(stage)
		geometries.append(geometry)
		total_length += float(geometry.get("length", 1.0))
	var cursor := -total_length * 0.5
	for stage_index_value in range(rocket_stages.size()):
		var stage: Dictionary = rocket_stages[stage_index_value]
		var stage_center := cursor + float(geometries[stage_index_value].get("length", 1.0)) * 0.5
		for port in RocketAssembly.stage_docking_ports(stage, stage_center):
			if str(port.get("part_uid", "")) == port_uid:
				var components: Array = stage.get("components", [])
				var component: Dictionary = components[int(port.get("component_index", -1))]
				group_id = RocketAssembly.component_group_id(component)
				port_stage_index = stage_index_value
				port_offset = Vector2(port.position)
				separation_direction = -Vector2(port.normal).normalized()
				break
		if not group_id.is_empty():
			break
		cursor += float(geometries[stage_index_value].get("length", 1.0))
	if group_id.is_empty() or port_stage_index < stage_index:
		return false
	var released_stages: Array = []
	var retained_stages: Array = []
	var released_old_indices: Array[int] = []
	var retained_old_indices: Array[int] = []
	for old_index in range(rocket_stages.size()):
		if old_index < stage_index:
			retained_stages.append(rocket_stages[old_index].duplicate(true))
			retained_old_indices.append(old_index)
			continue
		var split := RocketAssembly.split_stage_by_group(rocket_stages[old_index], group_id)
		if split.is_empty():
			retained_stages.append(rocket_stages[old_index].duplicate(true))
			retained_old_indices.append(old_index)
		else:
			released_stages.append(split.released)
			released_old_indices.append(old_index)
			if split.has("retained"):
				retained_stages.append(split.retained)
				retained_old_indices.append(old_index)
	if released_stages.is_empty() or retained_stages.is_empty() or not retained_old_indices.has(stage_index):
		return false
	var released_has_rcs := false
	var retained_has_rcs := false
	for stage in released_stages:
		for component in stage.get("components", []):
			if str(component.get("kind", "")) == "rcs" and float(component.get("rcs_thrust", 0.0)) > 0.0:
				released_has_rcs = true
	for stage in retained_stages:
		for component in stage.get("components", []):
			if str(component.get("kind", "")) == "rcs" and float(component.get("rcs_thrust", 0.0)) > 0.0:
				retained_has_rcs = true
	if not released_has_rcs or not retained_has_rcs:
		return false
	var group_parts: Dictionary = {}
	for stage in released_stages:
		for component in stage.get("components", []):
			group_parts[str(component.get("part_uid", ""))] = true
	var retained_parts: Dictionary = {}
	for stage in retained_stages:
		for component in stage.get("components", []):
			retained_parts[str(component.get("part_uid", ""))] = true
	var released_tanks: Array = []
	var retained_tanks: Array = []
	var released_fuel_by_old_stage: Dictionary = {}
	var retained_fuel_by_old_stage: Dictionary = {}
	var released_stage_map: Dictionary = {}
	var retained_stage_map: Dictionary = {}
	for index in range(released_old_indices.size()):
		released_stage_map[released_old_indices[index]] = index
	for index in range(retained_old_indices.size()):
		retained_stage_map[retained_old_indices[index]] = index
	for tank_variant in resource_tanks:
		if not tank_variant is Dictionary:
			continue
		var tank: Dictionary = tank_variant.duplicate(true)
		if str(tank.get("module_id", vehicle_name)) != vehicle_name:
			retained_tanks.append(tank)
			continue
		var old_stage := int(tank.get("stage_index", 0))
		if group_parts.has(str(tank.get("part_uid", ""))) and released_stage_map.has(old_stage):
			tank["stage_index"] = int(released_stage_map[old_stage])
			released_tanks.append(tank)
			released_fuel_by_old_stage[old_stage] = float(released_fuel_by_old_stage.get(old_stage, 0.0)) + float(tank.get("resources", {}).get("liquid_propellant", 0.0))
		elif retained_stage_map.has(old_stage):
			tank["stage_index"] = int(retained_stage_map[old_stage])
			retained_tanks.append(tank)
			retained_fuel_by_old_stage[old_stage] = float(retained_fuel_by_old_stage.get(old_stage, 0.0)) + float(tank.get("resources", {}).get("liquid_propellant", 0.0))
	var released_fuel: Array[float] = []
	var retained_fuel: Array[float] = []
	for index in range(released_stages.size()):
		var old_index := released_old_indices[index]
		released_fuel.append(float(released_fuel_by_old_stage.get(old_index, 0.0)))
	for index in range(retained_stages.size()):
		var old_index := retained_old_indices[index]
		retained_fuel.append(float(retained_fuel_by_old_stage.get(old_index, 0.0)))
	var released_rcs_capacity := 0.0
	var total_rcs_capacity := _own_rcs_propellant_capacity()
	for stage in released_stages:
		released_rcs_capacity += RocketDesign.stage_rcs_propellant_capacity(stage)
	var own_rcs_remaining := maxf(0.0, rcs_propellant_remaining - _external_rcs_propellant_total())
	var released_rcs_fuel := own_rcs_remaining * released_rcs_capacity / total_rcs_capacity if total_rcs_capacity > 0.0 else 0.0
	var carries_payload := payload_subassembly_id == group_id
	var released_payload_mass := payload_mass if carries_payload else 0.001
	var released_payload_type := payload_type if carries_payload else "debris"
	var released_payload_visual := payload_visual.duplicate(true) if carries_payload else {}
	var physical_payload_profile := RocketAssembly.physical_payload_profile(released_stages)
	if not physical_payload_profile.is_empty():
		released_payload_mass = 0.001
		released_payload_type = str(physical_payload_profile.get("part_id", "physical_payload"))
		released_payload_visual = physical_payload_profile
	var released_mass := released_rcs_fuel + released_payload_mass
	for index in range(released_stages.size()):
		released_mass += RocketDesign.stage_total_dry_mass(released_stages[index]) + released_fuel[index]
	for tank in released_tanks:
		var resources: Dictionary = tank.get("resources", {})
		released_mass += float(resources.get("xenon", 0.0)) + float(resources.get("solid_propellant", 0.0))
	var total_mass := maxf(0.001, _current_vehicle_mass())
	released_mass = clampf(released_mass, 0.001, total_mass - 0.001)
	var retained_mass := total_mass - released_mass
	var world_offset := port_offset.rotated(rotation_angle)
	var world_direction := separation_direction.rotated(rotation_angle).normalized()
	var separation_speed := 1.0
	var old_position := rocket_position
	var old_velocity := velocity
	var released_position := old_position + world_offset * (retained_mass / total_mass)
	var retained_position := old_position - world_offset * (released_mass / total_mass)
	var released_velocity := old_velocity + world_direction * separation_speed * (retained_mass / total_mass)
	var retained_velocity := old_velocity - world_direction * separation_speed * (released_mass / total_mass)
	var retained_stage_index := retained_old_indices.find(stage_index)
	if retained_stage_index < 0:
		return false
	var released_stage_index := released_old_indices.find(stage_index)
	if released_stage_index < 0:
		return false
	rocket_stages = retained_stages
	stage_fuel_remaining = retained_fuel
	resource_tanks = retained_tanks
	stage_index = retained_stage_index
	rcs_propellant_remaining = maxf(0.0, rcs_propellant_remaining - released_rcs_fuel)
	if carries_payload:
		payload_mass = 0.001
		payload_type = "debris"
		payload_visual.clear()
		payload_subassembly_id = "main"
	_set_rocket_position_components(retained_position.x, retained_position.y)
	velocity = retained_velocity
	fuel = stage_fuel_remaining[stage_index] if stage_index < stage_fuel_remaining.size() else 0.0
	_sync_legacy_fuel_from_tanks()
	infinite_fuel_stage_remaining = fuel
	var released_plan: Array = []
	var retained_plan: Array = []
	for plan_stage in staging_plan:
		var released_actions: Array = []
		var retained_actions: Array = []
		for action in plan_stage.get("actions", []):
			if not action is Dictionary:
				continue
			var part_id := str(action.get("part_id", ""))
			if group_parts.has(part_id):
				released_actions.append(action.duplicate(true))
			elif retained_parts.has(part_id):
				retained_actions.append(action.duplicate(true))
		released_plan.append({"id":str(plan_stage.get("id", "")), "label":str(plan_stage.get("label", "")), "actions":released_actions})
		retained_plan.append({"id":str(plan_stage.get("id", "")), "label":str(plan_stage.get("label", "")), "actions":retained_actions})
	staging_plan = retained_plan
	staging_part_states = _current_staging_part_states()
	action_stage_index = clampi(action_stage_index, 0, maxi(0, staging_plan.size() - 1))
	staging_changed.emit()
	stage_separated.emit({
		"stages": released_stages,
		"stage_fuel_remaining": released_fuel,
		"payload_mass": released_payload_mass,
		"payload_type": released_payload_type,
		"payload_visual": released_payload_visual,
		"fuel": released_fuel[released_stage_index],
		"rcs_fuel": released_rcs_fuel,
		"resource_tanks": released_tanks,
		"dockable_module": true,
		"position_components": PackedFloat64Array([released_position.x, released_position.y]),
		"velocity": released_velocity,
		"rotation_angle": rotation_angle,
		"angular_velocity": angular_velocity,
		"sim_time": sim_time,
		"launch_time": launch_time,
		"parent_vehicle_name": vehicle_name,
		"separation_speed": separation_speed,
		"staging_plan": released_plan
	})
	return true


func _release_upper_module(module_stage_index: int) -> bool:
	if resource_inventory_external or docked_mass > 0.001:
		return false
	if module_stage_index <= stage_index or module_stage_index >= rocket_stages.size():
		return false
	var boundaries := RocketAssembly.docking_module_boundaries(rocket_stages)
	if not boundaries.has(module_stage_index):
		return false
	var boundary: Dictionary = boundaries[module_stage_index]
	var module_stages: Array = rocket_stages.slice(module_stage_index)
	var remaining_stages: Array = rocket_stages.slice(0, module_stage_index)
	var module_fuel: Array[float] = []
	var remaining_fuel: Array[float] = []
	for index in range(stage_fuel_remaining.size()):
		if index >= module_stage_index:
			module_fuel.append(stage_fuel_remaining[index])
		else:
			remaining_fuel.append(stage_fuel_remaining[index])
	var module_tanks: Array = []
	var remaining_tanks: Array = []
	for tank_variant in resource_tanks:
		if not tank_variant is Dictionary:
			continue
		var tank: Dictionary = tank_variant.duplicate(true)
		if str(tank.get("module_id", vehicle_name)) == vehicle_name and int(tank.get("stage_index", -1)) >= module_stage_index:
			tank["stage_index"] = int(tank.get("stage_index", module_stage_index)) - module_stage_index
			module_tanks.append(tank)
		else:
			remaining_tanks.append(tank)
	var module_rcs_capacity := 0.0
	var total_rcs_capacity := _own_rcs_propellant_capacity()
	for module_stage in module_stages:
		module_rcs_capacity += RocketDesign.stage_rcs_propellant_capacity(module_stage)
	var own_rcs_remaining := maxf(0.0, rcs_propellant_remaining - _external_rcs_propellant_total())
	var module_rcs_fuel := own_rcs_remaining * module_rcs_capacity / total_rcs_capacity if total_rcs_capacity > 0.0 else 0.0
	var module_payload_mass := payload_mass
	var module_payload_type := payload_type
	var module_payload_visual := payload_visual.duplicate(true)
	var physical_payload_profile := RocketAssembly.physical_payload_profile(module_stages)
	if not physical_payload_profile.is_empty():
		module_payload_mass = 0.001
		module_payload_type = str(physical_payload_profile.get("part_id", "physical_payload"))
		module_payload_visual = physical_payload_profile
	var module_mass := module_payload_mass + module_rcs_fuel
	for index in range(module_stages.size()):
		module_mass += RocketDesign.stage_total_dry_mass(module_stages[index]) + module_fuel[index]
	for tank in module_tanks:
		var resources: Dictionary = tank.get("resources", {})
		module_mass += float(resources.get("xenon", 0.0)) + float(resources.get("solid_propellant", 0.0))
	var total_mass := maxf(0.001, _current_vehicle_mass())
	module_mass = clampf(module_mass, 0.001, total_mass - 0.001)
	var remaining_mass := total_mass - module_mass
	var connector_offset: Vector2 = Vector2(boundary.get("offset", Vector2.ZERO)).rotated(rotation_angle)
	var separation_direction: Vector2 = Vector2(boundary.get("separation_direction", Vector2.UP)).rotated(rotation_angle).normalized()
	var old_position := rocket_position
	var old_velocity := velocity
	var separation_speed := 2.0
	var module_position := old_position + connector_offset * (remaining_mass / total_mass)
	var parent_position := old_position - connector_offset * (module_mass / total_mass)
	var module_velocity := old_velocity + separation_direction * separation_speed * (remaining_mass / total_mass)
	var parent_velocity := old_velocity - separation_direction * separation_speed * (module_mass / total_mass)
	rocket_stages = remaining_stages
	stage_fuel_remaining = remaining_fuel
	resource_tanks = remaining_tanks
	payload_mass = 0.001
	payload_type = "debris"
	payload_visual.clear()
	rcs_propellant_remaining = maxf(0.0, rcs_propellant_remaining - module_rcs_fuel)
	_set_rocket_position_components(parent_position.x, parent_position.y)
	velocity = parent_velocity
	if stage_index < stage_fuel_remaining.size():
		fuel = stage_fuel_remaining[stage_index]
	_sync_legacy_fuel_from_tanks()
	infinite_fuel_stage_remaining = fuel
	var attached_parts: Dictionary = {}
	for stage in rocket_stages:
		for component in stage.get("components", []):
			attached_parts[str(component.get("part_uid", ""))] = true
	for plan_index in range(staging_plan.size()):
		var plan_stage: Dictionary = staging_plan[plan_index].duplicate(true)
		var retained_actions: Array = []
		for action in plan_stage.get("actions", []):
			if action is Dictionary and attached_parts.has(str(action.get("part_id", ""))):
				retained_actions.append(action)
		plan_stage["actions"] = retained_actions
		staging_plan[plan_index] = plan_stage
	staging_part_states = _current_staging_part_states()
	action_stage_index = clampi(action_stage_index, 0, maxi(0, staging_plan.size() - 1))
	staging_changed.emit()
	stage_separated.emit({
		"stages": module_stages,
		"stage_fuel_remaining": module_fuel,
		"payload_mass": module_payload_mass,
		"payload_type": module_payload_type,
		"payload_visual": module_payload_visual,
		"fuel": module_fuel[0] if not module_fuel.is_empty() else 0.0,
		"rcs_fuel": module_rcs_fuel,
		"resource_tanks": module_tanks,
		"dockable_module": true,
		"position_components": PackedFloat64Array([module_position.x, module_position.y]),
		"velocity": module_velocity,
		"rotation_angle": rotation_angle,
		"angular_velocity": angular_velocity,
		"sim_time": sim_time,
		"launch_time": launch_time,
		"parent_vehicle_name": vehicle_name,
		"separation_speed": separation_speed
	})
	return true

func _autopilot_target_body_name() -> String:
	return FlightComputer.target_body_name(autopilot_planet_index)

func _autopilot_target_state() -> Dictionary:
	var body_name: String = _autopilot_target_body_name()
	if body_name.is_empty():
		return {}
	return _surface_body_state(body_name)

func _fail_autopilot(reason: String) -> void:
	autopilot_phase = "FAILED"
	thrust_key_down = false
	rcs_rotation_input = 0.0
	rcs_rotation_scale = 0.0
	status_message = "AUTOPILOT FAILED  •  %s" % reason

func _begin_arrival_capture(target_state: Dictionary) -> void:
	var relative_position := _relative_position_to_body(target_state)
	var relative_velocity: Vector2 = velocity - target_state.velocity
	var target_name := str(target_state.get("name", ""))
	var minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(target_name, float(target_state.radius))
	var capture := FlightComputer.arrival_capture_burn(relative_position, relative_velocity, G * float(target_state.mass), float(target_state.radius), autopilot_target_altitude, minimum_safe_altitude)
	if not bool(capture.get("valid", false)):
		_fail_autopilot("APPROACH CANNOT REACH SELECTED ORBIT")
		return
	autopilot_arrival_burn_vector = capture.burn_vector
	autopilot_burn_direction = autopilot_arrival_burn_vector.normalized()
	autopilot_burn_remaining = float(capture.delta_v)
	if autopilot_burn_remaining <= FlightComputer.BURN_COMPLETION_TOLERANCE:
		autopilot_apsis_correction_armed = false
		autopilot_apsis_correction_angle = relative_position.angle()
		autopilot_phase = "COAST_TO_TARGET"
	else:
		autopilot_phase = "ARRIVAL_CAPTURE_BURN"

func _ephemeris_states_at(time_seconds: float) -> Dictionary:
	if ephemeris_cache.is_empty() or time_seconds < ephemeris_cache_time or time_seconds - ephemeris_cache_time >= 0.5:
		ephemeris_cache = PlanetarySystem.gravity_body_states(time_seconds)
		ephemeris_cache_time = time_seconds
		ephemeris_output_cache.clear()
		ephemeris_output_cache_time = -INF
	var offset: float = time_seconds - ephemeris_cache_time
	if absf(offset) < 0.000001:
		return ephemeris_cache
	if absf(time_seconds - ephemeris_output_cache_time) < 0.000001 and not ephemeris_output_cache.is_empty():
		return ephemeris_output_cache
	var adjusted_bodies: Array[Dictionary] = []
	for body in ephemeris_cache.get("bodies", []):
		var adjusted: Dictionary = body.duplicate()
		var body_position: Vector2 = body.get("position", Vector2.ZERO)
		var body_velocity: Vector2 = body.get("velocity", Vector2.ZERO)
		var position_components: PackedFloat64Array = body.get("position_components", PackedFloat64Array([body_position.x, body_position.y]))
		var velocity_components: PackedFloat64Array = body.get("velocity_components", PackedFloat64Array([body_velocity.x, body_velocity.y]))
		var adjusted_components := PackedFloat64Array([
			position_components[0] + velocity_components[0] * offset,
			position_components[1] + velocity_components[1] * offset
		])
		adjusted["position_components"] = adjusted_components
		adjusted["position"] = Vector2(adjusted_components[0], adjusted_components[1])
		adjusted_bodies.append(adjusted)
	var adjusted_surface: Array[Dictionary] = []
	for body in ephemeris_cache.get("surface_bodies", []):
		var adjusted: Dictionary = body.duplicate()
		var body_position: Vector2 = body.get("position", Vector2.ZERO)
		var body_velocity: Vector2 = body.get("velocity", Vector2.ZERO)
		var position_components: PackedFloat64Array = body.get("position_components", PackedFloat64Array([body_position.x, body_position.y]))
		var velocity_components: PackedFloat64Array = body.get("velocity_components", PackedFloat64Array([body_velocity.x, body_velocity.y]))
		var adjusted_components := PackedFloat64Array([
			position_components[0] + velocity_components[0] * offset,
			position_components[1] + velocity_components[1] * offset
		])
		adjusted["position_components"] = adjusted_components
		adjusted["position"] = Vector2(adjusted_components[0], adjusted_components[1])
		adjusted_surface.append(adjusted)
	var adjusted_heliocentric: Array[Dictionary] = []
	for body in ephemeris_cache.get("heliocentric_bodies", []):
		var adjusted: Dictionary = body.duplicate()
		var body_position: Vector2 = body.get("position", Vector2.ZERO)
		var body_velocity: Vector2 = body.get("velocity", Vector2.ZERO)
		var position_components: PackedFloat64Array = body.get("position_components", PackedFloat64Array([body_position.x, body_position.y]))
		var velocity_components: PackedFloat64Array = body.get("velocity_components", PackedFloat64Array([body_velocity.x, body_velocity.y]))
		var adjusted_components := PackedFloat64Array([
			position_components[0] + velocity_components[0] * offset,
			position_components[1] + velocity_components[1] * offset
		])
		adjusted["position_components"] = adjusted_components
		adjusted["position"] = Vector2(adjusted_components[0], adjusted_components[1])
		adjusted_heliocentric.append(adjusted)
	var moon_state: Dictionary = PlanetarySystem.moon_state(time_seconds)
	var moon_position_components: PackedFloat64Array = moon_state.position_components
	var moon_velocity_components: PackedFloat64Array = moon_state.velocity_components
	var moon_position := Vector2(moon_position_components[0], moon_position_components[1])
	var moon_velocity := Vector2(moon_velocity_components[0], moon_velocity_components[1])
	for i in range(adjusted_bodies.size()):
		if str(adjusted_bodies[i].get("name", "")) == "Moon":
			adjusted_bodies[i]["position"] = moon_position
			adjusted_bodies[i]["position_components"] = moon_position_components
			adjusted_bodies[i]["velocity"] = moon_velocity
			adjusted_bodies[i]["velocity_components"] = moon_velocity_components
			break
	for i in range(adjusted_surface.size()):
		if str(adjusted_surface[i].get("name", "")) == "Moon":
			adjusted_surface[i]["position"] = moon_position
			adjusted_surface[i]["position_components"] = moon_position_components
			adjusted_surface[i]["velocity"] = moon_velocity
			adjusted_surface[i]["velocity_components"] = moon_velocity_components
			break
	var earth_position_components: PackedFloat64Array = ephemeris_cache.get("earth_heliocentric_position_components", PackedFloat64Array([0.0, 0.0]))
	var earth_velocity_components: PackedFloat64Array = ephemeris_cache.get("earth_heliocentric_velocity_components", PackedFloat64Array([0.0, 0.0]))
	var adjusted_earth_components := PackedFloat64Array([
		earth_position_components[0] + earth_velocity_components[0] * offset,
		earth_position_components[1] + earth_velocity_components[1] * offset
	])
	var adjusted_earth_position := Vector2(adjusted_earth_components[0], adjusted_earth_components[1])
	var adjusted_earth_velocity := Vector2(earth_velocity_components[0], earth_velocity_components[1])
	var moon_heliocentric_components := PackedFloat64Array([
		adjusted_earth_components[0] + moon_position_components[0],
		adjusted_earth_components[1] + moon_position_components[1]
	])
	var moon_heliocentric_velocity_components := PackedFloat64Array([
		earth_velocity_components[0] + moon_velocity_components[0],
		earth_velocity_components[1] + moon_velocity_components[1]
	])
	for i in range(adjusted_heliocentric.size()):
		if str(adjusted_heliocentric[i].get("name", "")) == "Moon":
			adjusted_heliocentric[i]["position_components"] = moon_heliocentric_components
			adjusted_heliocentric[i]["position"] = Vector2(moon_heliocentric_components[0], moon_heliocentric_components[1])
			adjusted_heliocentric[i]["velocity_components"] = moon_heliocentric_velocity_components
			adjusted_heliocentric[i]["velocity"] = Vector2(moon_heliocentric_velocity_components[0], moon_heliocentric_velocity_components[1])
			break
	var adjusted_moon_velocity := Vector2(moon_heliocentric_velocity_components[0], moon_heliocentric_velocity_components[1])
	ephemeris_output_cache = {
		"bodies": adjusted_bodies,
		"surface_bodies": adjusted_surface,
		"heliocentric_bodies": adjusted_heliocentric,
		"earth_heliocentric_position": adjusted_earth_position,
		"earth_heliocentric_position_components": adjusted_earth_components,
		"earth_heliocentric_velocity": adjusted_earth_velocity,
		"earth_heliocentric_velocity_components": earth_velocity_components,
		"moon_heliocentric_velocity": adjusted_moon_velocity,
		"moon_heliocentric_velocity_components": moon_heliocentric_velocity_components
	}
	ephemeris_output_cache_time = time_seconds
	return ephemeris_output_cache

func _surface_body_state(body_name: String) -> Dictionary:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	for body in states.get("surface_bodies", []):
		if str(body.get("name", "")) == body_name:
			return body.duplicate()
	return {}
func _body_position_components(body: Dictionary) -> PackedFloat64Array:
	var body_position: Vector2 = body.get("position", Vector2.ZERO)
	return body.get("position_components", PackedFloat64Array([body_position.x, body_position.y]))

func _relative_position_to_body(body: Dictionary, position_components: PackedFloat64Array = PackedFloat64Array()) -> Vector2:
	var components := rocket_position_precise if position_components.size() < 2 else position_components
	var body_components := _body_position_components(body)
	return Vector2(components[0] - body_components[0], components[1] - body_components[1])

func _set_rocket_position_relative_to_body(body: Dictionary, relative_position: Vector2) -> void:
	var body_components := _body_position_components(body)
	_set_rocket_position_components(body_components[0] + relative_position.x, body_components[1] + relative_position.y)

func _nearest_body_state(position: Vector2, position_components: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	var components := position_components
	if components.size() < 2:
		components = rocket_position_precise if position == rocket_position else PackedFloat64Array([position.x, position.y])
	var nearest_body: Dictionary = {}
	var nearest_delta := Vector2.ZERO
	var nearest_distance_squared: float = INF
	for body_variant in states.get("surface_bodies", []):
		var body: Dictionary = body_variant
		var body_components := _body_position_components(body)
		var delta_x: float = components[0] - body_components[0]
		var delta_y: float = components[1] - body_components[1]
		var distance_squared := delta_x * delta_x + delta_y * delta_y
		var soi := float(body.get("soi", 0.0))
		if distance_squared > soi * soi:
			continue
		if distance_squared < nearest_distance_squared:
			nearest_body = body
			nearest_delta = Vector2(delta_x, delta_y)
			nearest_distance_squared = distance_squared
	if nearest_body.is_empty():
		nearest_body = _surface_body_state("Earth")
		nearest_delta = Vector2(components[0], components[1])
		nearest_distance_squared = components[0] * components[0] + components[1] * components[1]
	var nearest: Dictionary = nearest_body.duplicate()
	nearest["relative_position"] = nearest_delta
	nearest["distance"] = sqrt(nearest_distance_squared)
	return nearest

func _handle_body_contact() -> void:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	for body_variant in states.get("surface_bodies", []):
		var body: Dictionary = body_variant
		var body_components := _body_position_components(body)
		var relative_x: float = rocket_position_precise[0] - body_components[0]
		var relative_y: float = rocket_position_precise[1] - body_components[1]
		var body_radius := float(body.radius)
		var contact_distance := body_radius + 0.5
		if relative_x * relative_x + relative_y * relative_y > contact_distance * contact_distance:
			continue
		var relative_position := Vector2(relative_x, relative_y)
		var normal := relative_position.normalized()
		var body_velocity: Vector2 = body.velocity
		var surface_velocity := body_velocity + Vector2(-relative_position.y, relative_position.x) * float(body.rotation_rate)
		var relative_speed := (velocity - surface_velocity).length()
		_set_rocket_position_relative_to_body(body, normal * (body_radius + 0.5))
		if not bool(body.solid):
			crashed = true
			status_message = "LOST IN %s  •  ATMOSPHERIC LIMIT REACHED" % str(body.name).to_upper()
		elif relative_speed <= 35.0:
			landed = true
			angular_velocity = 0.0
			crashed = false
			landed_body_name = str(body.name)
			landed_surface_normal = normal
			velocity = surface_velocity
			status_message = "LANDED  •  %s" % landed_body_name.to_upper()
		else:
			crashed = true
			landed = false
			status_message = "CRASHED  •  %s  •  %.0f M/S" % [str(body.name).to_upper(), relative_speed]
		if crashed:
			velocity = body_velocity
		else:
			velocity = surface_velocity
		thrust_key_down = false
		throttle = 0.0
		guidance_enabled = false
		autopilot_enabled = false
		return

func _update_guidance(dt: float) -> void:
	var guidance_body := _nearest_body_state(rocket_position, rocket_position_precise)
	var guidance_position: Vector2 = guidance_body.relative_position
	var guidance_velocity: Vector2 = velocity - guidance_body.velocity
	var radial := guidance_position.normalized()
	var altitude := maxf(0.0, float(guidance_body.distance) - float(guidance_body.radius))
	var propellant_available := infinite_weightless_fuel or fuel > 0.0
	var destination_is_local := float(guidance_body.get("distance", INF)) <= float(guidance_body.get("soi", 0.0)) and str(guidance_body.get("name", "")) == _autopilot_target_body_name()
	var guidance_body_name := str(guidance_body.get("name", ""))
	var minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(guidance_body_name, float(guidance_body.radius))
	var maximum_stable_altitude := FlightComputer.maximum_stable_orbit_altitude(float(guidance_body.radius), float(guidance_body.get("soi", 0.0)))
	var parking_altitude := clampf(200000.0, minimum_safe_altitude, maxf(minimum_safe_altitude, maximum_stable_altitude))
	var guidance_orbit_altitude := autopilot_target_altitude if destination_is_local else parking_altitude
	var tangent := Vector2(-radial.y, radial.x)
	var atmosphere_height := PlanetarySystem.planetary_atmosphere_height(guidance_body_name)
	var pitch_reference_altitude := maxf(100000.0, guidance_orbit_altitude * 0.75)
	var pitch_above_horizon := lerpf(90.0, 5.0, clampf(altitude / pitch_reference_altitude, 0.0, 1.0))
	if autopilot_enabled and autopilot_phase == "ASCENT" and not destination_is_local and maximum_stable_altitude <= minimum_safe_altitude:
		_fail_autopilot("NO SAFE PARKING ORBIT EXISTS AROUND %s" % guidance_body_name.to_upper())
	if autopilot_enabled:
		var orbit := FlightComputer.orbital_state(guidance_position, guidance_velocity, G * float(guidance_body.mass))
		var target_radius := float(guidance_body.radius) + guidance_orbit_altitude
		var target_orbit_speed := FlightComputer.circular_orbit_speed(target_radius, G * float(guidance_body.mass))
		var orbit_target_tolerance := FlightComputer.orbit_radius_tolerance(target_radius)
		var prograde := guidance_velocity.normalized() if guidance_velocity.length() > 1.0 else tangent
		match autopilot_phase:
			"ASCENT":
				status_message = "AUTOPILOT  •  ASCENT TO %.0f KM" % (guidance_orbit_altitude / 1000.0)
				var ascent_orbit_periapsis := float(orbit.get("periapsis", 0.0))
				var ascent_orbit_apoapsis := float(orbit.get("apoapsis", INF))
				var ascent_orbit_radial_speed := absf(float(orbit.get("radial_speed", 0.0)))
				var inside_guidance_body_soi := float(guidance_body.get("distance", INF)) <= float(guidance_body.get("soi", 0.0))
				var safe_parking_orbit := inside_guidance_body_soi and bool(orbit.get("bound", false)) and ascent_orbit_periapsis > float(guidance_body.radius) + minimum_safe_altitude and ascent_orbit_apoapsis < float(guidance_body.radius) + maximum_stable_altitude
				var already_in_stable_orbit := safe_parking_orbit and ascent_orbit_radial_speed < maxf(1.0, target_orbit_speed * 0.01)
				if not propellant_available and not already_in_stable_orbit:
					_fail_autopilot("OUT OF PROPELLANT BEFORE SAFE PARKING ORBIT")
					return
				var reached_parking_orbit := already_in_stable_orbit and float(orbit.get("apoapsis", 0.0)) >= target_radius - maxf(orbit_target_tolerance, minf(25000.0, target_radius * 0.002))
				if reached_parking_orbit and not destination_is_local:
					thrust_key_down = false
					autopilot_phase = "PLAN_TRANSFER"
				elif reached_parking_orbit and destination_is_local and absf(guidance_position.length() - target_radius) < orbit_target_tolerance:
					thrust_key_down = false
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
				elif already_in_stable_orbit:
					thrust_key_down = false
					autopilot_phase = "CIRCULARISE"
				elif safe_parking_orbit and float(orbit.get("apoapsis", 0.0)) >= target_radius - maxf(orbit_target_tolerance, minf(25000.0, target_radius * 0.002)):
					thrust_key_down = false
					autopilot_phase = "COAST"
				else:
					var ascent_tangential_speed: float = absf(float(orbit.get("tangential_speed", 0.0)))
					var surface_rotation_speed: float = absf(float(guidance_body.get("rotation_rate", 0.0))) * float(guidance_body.radius)
					var ascent_speed_gain: float = maxf(0.0, ascent_tangential_speed - surface_rotation_speed)
					var ascent_altitude_fraction: float = clampf(altitude / pitch_reference_altitude, 0.0, 1.0)
					pitch_above_horizon = lerpf(88.0, 4.0, ascent_altitude_fraction)
					status_message = "AUTOPILOT  •  ASCENT  •  ALT %.0f KM  •  Vt %.2f KM/S  •  PITCH %.0f°" % [altitude / 1000.0, ascent_tangential_speed / 1000.0, pitch_above_horizon]
					thrust_key_down = propellant_available
			"COAST":
				status_message = "AUTOPILOT  •  COASTING TO APOAPSIS"
				thrust_key_down = false
				var coast_radial_speed: float = float(orbit.get("radial_speed", 0.0))
				var coast_speed_tolerance := maxf(0.1, minf(10.0, target_orbit_speed * 0.01))
				if absf(coast_radial_speed) <= coast_speed_tolerance and altitude > minimum_safe_altitude:
					autopilot_phase = "CIRCULARISE"
			"COAST_TO_TARGET":
				status_message = "AUTOPILOT  •  COASTING TO TARGET ORBIT"
				thrust_key_down = false
				var target_distance_error: float = absf(guidance_position.length() - target_radius)
				var target_radial_speed: float = absf(float(orbit.get("radial_speed", 0.0)))
				var target_bound: bool = bool(orbit.get("bound", false))
				var target_periapsis: float = float(orbit.get("periapsis", 0.0))
				var target_apoapsis: float = float(orbit.get("apoapsis", INF))
				var safe_target_orbit: bool = target_bound and target_periapsis > float(guidance_body.radius) + minimum_safe_altitude
				var target_alignment_window_radius := maxf(2.0, minf(50.0, target_radius * 0.00002))
				var target_apsis_tolerance := target_alignment_window_radius
				var target_alignment_speed_tolerance := maxf(0.05, minf(0.5, target_orbit_speed * 0.0001))
				var apsis_speed_tolerance := maxf(0.05, minf(0.5, target_orbit_speed * 0.0001))
				var target_alignment_window: bool = target_distance_error < target_alignment_window_radius and target_radial_speed < target_alignment_speed_tolerance
				var periapsis_target_error: float = absf(target_periapsis - target_radius)
				var apoapsis_target_error: float = absf(target_apoapsis - target_radius)
				var orbit_completion_tolerance := maxf(1000.0, minf(5000.0, target_radius * 0.001))
				var target_orbit_complete: bool = safe_target_orbit and periapsis_target_error <= orbit_completion_tolerance and apoapsis_target_error <= orbit_completion_tolerance
				var angular_distance_since_correction := absf(wrapf(guidance_position.angle() - autopilot_apsis_correction_angle, -PI, PI))
				if not autopilot_apsis_correction_armed and angular_distance_since_correction > deg_to_rad(150.0):
					autopilot_apsis_correction_armed = true
				var target_apsis_reached: bool = autopilot_apsis_correction_armed and target_radial_speed <= apsis_speed_tolerance and altitude > minimum_safe_altitude
				var transfer_already_reaches_target: bool = target_bound and minf(periapsis_target_error, apoapsis_target_error) <= target_apsis_tolerance
				var target_correction_needed := false
				var spacecraft_at_target_apsis := absf(guidance_position.length() - target_radius) <= orbit_completion_tolerance
				if target_apsis_reached and (not transfer_already_reaches_target or spacecraft_at_target_apsis):
					var coast_correction_plan: Dictionary = FlightComputer.target_radius_burn(guidance_position, guidance_velocity, target_radius, G * float(guidance_body.mass))
					target_correction_needed = bool(coast_correction_plan.get("valid", false)) and float(coast_correction_plan.get("delta_v", INF)) > FlightComputer.BURN_COMPLETION_TOLERANCE
				if target_orbit_complete:
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
					status_message = "AUTOPILOT  •  TARGET ORBIT ACHIEVED"
				elif target_alignment_window:
					autopilot_phase = "CIRCULARISE"
				elif target_correction_needed:
					autopilot_apsis_correction_armed = false
					autopilot_apsis_correction_angle = guidance_position.angle()
					autopilot_phase = "CIRCULARISE"
					status_message = "AUTOPILOT  •  CORRECTING ORBIT AT APSIS"
				elif safe_target_orbit or (altitude > minimum_safe_altitude and propellant_available):
					status_message = "AUTOPILOT  •  APPROACHING TARGET RADIUS"
				else:
					_fail_autopilot("TARGET PERIAPSIS IS BELOW THE BODY")
			"CIRCULARISE_BURN":
				var updated_recovery_plan: Dictionary = FlightComputer.target_radius_burn(guidance_position, guidance_velocity, target_radius, G * float(guidance_body.mass))
				if not bool(updated_recovery_plan.get("valid", false)):
					thrust_key_down = false
					_fail_autopilot("ORBIT RECOVERY BECAME UNSTABLE")
				else:
					var updated_burn_vector: Vector2 = updated_recovery_plan.get("burn_vector", Vector2.ZERO)
					autopilot_burn_direction = updated_burn_vector.normalized()
					autopilot_burn_remaining = float(updated_recovery_plan.get("delta_v", INF))
					status_message = "AUTOPILOT  •  RECOVERING ORBIT  %.0f M/S" % autopilot_burn_remaining
					if autopilot_burn_remaining <= FlightComputer.BURN_COMPLETION_TOLERANCE:
						thrust_key_down = false
						autopilot_apsis_correction_armed = false
						autopilot_apsis_correction_angle = guidance_position.angle()
						autopilot_phase = "COAST_TO_TARGET"
					else:
						thrust_key_down = propellant_available
					if not propellant_available and stage_index >= rocket_stages.size() - 1:
						_fail_autopilot("OUT OF PROPELLANT DURING CIRCULARISATION")
			"CIRCULARISE":
				status_message = "AUTOPILOT  •  ORBITAL CIRCULARISATION"
				var target_orbit_plan: Dictionary = FlightComputer.target_radius_burn(guidance_position, guidance_velocity, target_radius, G * float(guidance_body.mass))
				var target_burn_vector: Vector2 = target_orbit_plan.get("burn_vector", Vector2.ZERO)
				var target_burn_delta_v: float = float(target_orbit_plan.get("delta_v", INF))
				var circularised_velocity: Vector2 = target_orbit_plan.get("desired_velocity", guidance_velocity)
				var circularised_orbit: Dictionary = FlightComputer.orbital_state(guidance_position, circularised_velocity, G * float(guidance_body.mass))
				var safe_periapsis: float = float(guidance_body.radius) + minimum_safe_altitude
				var target_orbit_tolerance := FlightComputer.orbit_radius_tolerance(target_radius)
				var circularised_periapsis: float = float(circularised_orbit.get("periapsis", 0.0))
				var circularised_apoapsis: float = float(circularised_orbit.get("apoapsis", INF))
				var circularisation_complete: bool = bool(target_orbit_plan.get("valid", false)) and target_burn_delta_v <= FlightComputer.BURN_COMPLETION_TOLERANCE and bool(circularised_orbit.get("bound", false)) and circularised_periapsis > safe_periapsis and absf(circularised_periapsis - target_radius) < target_orbit_tolerance and absf(circularised_apoapsis - target_radius) < target_orbit_tolerance
				if not bool(target_orbit_plan.get("valid", false)):
					thrust_key_down = false
					_fail_autopilot("ORBIT INSERTION HAS AN INVALID STATE")
				elif circularisation_complete:
					thrust_key_down = false
					if not destination_is_local:
						autopilot_phase = "PLAN_TRANSFER"
					else:
						autopilot_phase = "COMPLETE"
						autopilot_complete = true
				else:
					autopilot_burn_direction = target_burn_vector.normalized()
					autopilot_burn_remaining = target_burn_delta_v
					if target_burn_delta_v <= FlightComputer.BURN_COMPLETION_TOLERANCE:
						thrust_key_down = false
						autopilot_apsis_correction_armed = false
						autopilot_apsis_correction_angle = guidance_position.angle()
						autopilot_phase = "COAST_TO_TARGET"
					else:
						autopilot_phase = "CIRCULARISE_BURN"

			"PLAN_TRANSFER":
				status_message = "AUTOPILOT  •  SIMULATING TRANSFER TRAJECTORIES"
				thrust_key_down = false
				var transfer_plan: Dictionary = autopilot_precomputed_transfer_plan.duplicate(true)
				autopilot_precomputed_transfer_plan.clear()
				if not transfer_plan.is_empty():
					var planned_position: Vector2 = transfer_plan.get("planned_position", Vector2.INF)
					var planned_velocity: Vector2 = transfer_plan.get("planned_velocity", Vector2.INF)
					var plan_matches_target := int(transfer_plan.get("target_id", -999)) == autopilot_planet_index and is_equal_approx(float(transfer_plan.get("target_altitude", -1.0)), autopilot_target_altitude)
					var plan_matches_state := absf(sim_time - float(transfer_plan.get("planned_at_time", -INF))) <= 2.0 and planned_position.distance_to(rocket_position) <= 20000.0 and planned_velocity.distance_to(velocity) <= 5.0
					if not plan_matches_target or not plan_matches_state:
						transfer_plan.clear()
				if transfer_plan.is_empty():
					var vehicle_design := {"payload_mass": payload_mass, "stages": rocket_stages}
					var available_transfer_delta_v := FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if infinite_weightless_fuel else FlightComputer.available_delta_v(vehicle_design, stage_index, fuel) * (1.0 - clampf(autopilot_safety_margin, 0.0, 0.4))
					transfer_plan = FlightComputer.simulated_transfer_search_precise(rocket_position_precise, velocity, sim_time, autopilot_planet_index, available_transfer_delta_v, autopilot_speed_priority, false, autopilot_target_altitude)
					if not bool(transfer_plan.get("valid", false)):
						var window_search := FlightComputer.scan_launch_windows(rocket_position, velocity, sim_time, autopilot_planet_index, available_transfer_delta_v, autopilot_speed_priority, 540, 30, autopilot_target_altitude, rocket_position_precise)
						if bool(window_search.get("valid", false)):
							transfer_plan = window_search.best
				if not bool(transfer_plan.get("valid", false)):
					_fail_autopilot("TRANSFER PLANNING FAILED  •  " + str(transfer_plan.get("reason", "NO FEASIBLE TRAJECTORY")))
				else:
					var departure_time := float(transfer_plan.get("departure_time_seconds", sim_time))
					if departure_time > sim_time + 2.0:
						autopilot_precomputed_transfer_plan = transfer_plan.duplicate(true)
						autopilot_phase = "WAIT_WINDOW"
						status_message = "AUTOPILOT  •  WAITING FOR VALIDATED DEPARTURE WINDOW  •  %.1f DAYS" % ((departure_time - sim_time) / 86400.0)
					else:
						var planned_burn_direction: Vector2 = transfer_plan.get("departure_direction", Vector2.ZERO)
						autopilot_burn_direction = planned_burn_direction.normalized()
						autopilot_burn_remaining = float(transfer_plan.get("departure_delta_v", 0.0))
						autopilot_transfer_duration = float(transfer_plan.get("transfer_time", 0.0))
						autopilot_transfer_start_time = -1.0
						if autopilot_burn_remaining <= FlightComputer.BURN_COMPLETION_TOLERANCE:
							autopilot_transfer_start_time = sim_time
							autopilot_phase = "TRANSFER_COAST"
						else:
							autopilot_phase = "TRANSFER_BURN"
						status_message = "AUTOPILOT  •  SIMULATED TRANSFER  •  %.2f KM/S" % (autopilot_burn_remaining / 1000.0)
			"WAIT_WINDOW":
				var waiting_plan: Dictionary = autopilot_precomputed_transfer_plan
				var departure_time := float(waiting_plan.get("departure_time_seconds", -1.0))
				thrust_key_down = false
				if waiting_plan.is_empty() or departure_time < 0.0:
					autopilot_precomputed_transfer_plan.clear()
					autopilot_phase = "PLAN_TRANSFER"
					status_message = "AUTOPILOT  •  REPLANNING DEPARTURE WINDOW"
				else:
					var remaining_window := maxf(0.0, departure_time - sim_time)
					status_message = "AUTOPILOT  •  WAITING FOR VALIDATED DEPARTURE WINDOW  •  %.1f DAYS" % (remaining_window / 86400.0)
					if remaining_window <= 0.0:
						autopilot_phase = "PLAN_TRANSFER"
			"ALIGN_DEPARTURE":
				status_message = "AUTOPILOT  •  ALIGNING DEPARTURE ORBIT"
				thrust_key_down = false
				var desired_radial := FlightComputer.departure_periapsis_direction(autopilot_planet_index, sim_time, guidance_position.length())
				if desired_radial.length_squared() > 0.5 and guidance_position.normalized().dot(desired_radial) >= cos(deg_to_rad(1.5)):
					autopilot_burn_direction = tangent * autopilot_transfer_direction
					autopilot_phase = "TRANSFER_BURN"
			"MANEUVER_BURN":
				status_message = "AUTOPILOT  •  PLANNED MANOEUVRE  %.0f M/S" % autopilot_burn_remaining
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE
				if not propellant_available and stage_index >= rocket_stages.size() - 1:
					_fail_autopilot("OUT OF PROPELLANT DURING MANOEUVRE")
			"ROUTE_COAST":
				thrust_key_down = false
				if autopilot_route_node_index >= autopilot_route_nodes.size():
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
				else:
					var route_node: Dictionary = autopilot_route_nodes[autopilot_route_node_index]
					var node_time: float = float(route_node.get("time", sim_time))
					status_message = "AUTOPILOT  •  COAST TO NODE %d  •  T+ %.1f MIN" % [autopilot_route_node_index + 1, maxf(0.0, node_time - sim_time) / 60.0]
					if sim_time >= node_time:
						var route_radial: Vector2 = guidance_position.normalized()
						var route_tangent := Vector2(-route_radial.y, route_radial.x)
						if guidance_position.cross(guidance_velocity) < 0.0:
							route_tangent = -route_tangent
						var route_burn_vector: Vector2 = route_tangent * float(route_node.get("prograde", 0.0)) + route_radial * float(route_node.get("radial", 0.0))
						if route_burn_vector.length() < 0.1:
							autopilot_route_node_index += 1
						else:
							autopilot_burn_direction = route_burn_vector.normalized()
							autopilot_burn_remaining = route_burn_vector.length()
							autopilot_phase = "ROUTE_BURN"
			"ROUTE_BURN":
				status_message = "AUTOPILOT  •  EXECUTING NODE %d  •  %.0f M/S" % [autopilot_route_node_index + 1, autopilot_burn_remaining]
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE
				if not propellant_available and stage_index >= rocket_stages.size() - 1:
					_fail_autopilot("OUT OF PROPELLANT DURING ROUTE BURN")
			"TRANSFER_BURN":
				status_message = "AUTOPILOT  •  INTERPLANETARY INJECTION  %.0f M/S" % autopilot_burn_remaining
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE
				if not propellant_available and stage_index >= rocket_stages.size() - 1:
					_fail_autopilot("OUT OF PROPELLANT DURING DEPARTURE BURN")
			"TRANSFER_COAST":
				thrust_key_down = false
				var transfer_elapsed := maxf(0.0, sim_time - autopilot_transfer_start_time)
				var transfer_remaining := maxf(0.0, autopilot_transfer_duration - transfer_elapsed)
				var transfer_destination_state := _autopilot_target_state()
				var destination_distance := _relative_position_to_body(transfer_destination_state).length()
				var encounter_radius := float(transfer_destination_state.soi)
				status_message = "AUTOPILOT  •  TRANSFER TO %s  •  %.1f DAYS REMAINING" % [str(transfer_destination_state.name).to_upper(), transfer_remaining / 86400.0]
				var current_nearest_body := _nearest_body_state(rocket_position, rocket_position_precise)
				if destination_distance <= encounter_radius and str(current_nearest_body.get("name", "")) == str(transfer_destination_state.get("name", "")):
					autopilot_phase = "ARRIVAL_APPROACH"
				elif transfer_elapsed > autopilot_transfer_duration * 0.4 and autopilot_transfer_corrections < 2:
					autopilot_transfer_corrections += 1
					autopilot_phase = "PLAN_TRANSFER"
					status_message = "AUTOPILOT  •  SIMULATING MID-COURSE CORRECTION"
				elif transfer_elapsed > autopilot_transfer_duration * 1.5:
					autopilot_phase = "ARRIVAL_PENDING"
			"ARRIVAL_APPROACH":
				thrust_key_down = false
				var approach_target_state := _autopilot_target_state()
				var approach_relative_position := _relative_position_to_body(approach_target_state)
				var approach_relative_velocity: Vector2 = velocity - approach_target_state.velocity
				var arrival_orbit := FlightComputer.orbital_state(approach_relative_position, approach_relative_velocity, G * float(approach_target_state.mass))
				var approach_radial_speed := float(arrival_orbit.get("radial_speed", 0.0))
				status_message = "AUTOPILOT  •  ARRIVAL AT %s  •  ALT %.0f KM" % [str(approach_target_state.name).to_upper(), (approach_relative_position.length() - float(approach_target_state.radius)) / 1000.0]
				if approach_radial_speed < 0.0:
					_begin_arrival_capture(approach_target_state)
				else:
					_fail_autopilot("ARRIVAL CAPTURE WINDOW MISSED  •  SPACECRAFT IS MOVING AWAY FROM THE TARGET")
			"ARRIVAL_CAPTURE_BURN":
				status_message = "AUTOPILOT  •  CAPTURING AT %s  •  %.0f M/S" % [_autopilot_target_body_name().to_upper(), autopilot_burn_remaining]
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE
				if not propellant_available and stage_index >= rocket_stages.size() - 1:
					_fail_autopilot("OUT OF PROPELLANT DURING ARRIVAL CAPTURE")
			"LANDING_DESCENT":
				var landing_target_state := _autopilot_target_state()
				var landing_relative_position := _relative_position_to_body(landing_target_state)
				var landing_relative_velocity: Vector2 = velocity - landing_target_state.velocity
				var landing_distance := landing_relative_position.length()
				var landing_altitude := landing_distance - float(landing_target_state.radius)
				var landing_up := landing_relative_position.normalized()
				var landing_tangent := Vector2(-landing_up.y, landing_up.x)
				var landing_gravity := G * float(landing_target_state.mass) / (landing_distance * landing_distance)
				var landing_radial_speed := landing_relative_velocity.dot(landing_up)
				var landing_tangential_speed := landing_relative_velocity.dot(landing_tangent)
				var landing_target_descent_speed := -maxf(1.5, minf(60.0, sqrt(2.0 * landing_gravity * maxf(0.0, landing_altitude - 2.0))))
				var landing_radial_acceleration := maxf(0.0, landing_gravity + (landing_target_descent_speed - landing_radial_speed) / 15.0)
				var landing_tangential_acceleration := -landing_tangential_speed / 180.0
				var landing_required_acceleration := landing_up * landing_radial_acceleration + landing_tangent * landing_tangential_acceleration
				var landing_available_acceleration := _engine_thrust(landing_altitude) / maxf(1.0, _current_vehicle_mass())
				autopilot_throttle = clampf(landing_required_acceleration.length() / maxf(0.01, landing_available_acceleration), 0.0, 1.0)
				thrust_key_down = autopilot_throttle > 0.001
				status_message = "LANDING GUIDANCE  •  %s  •  ALT %.1f KM  •  V/S %.1f M/S" % [str(landing_target_state.name).to_upper(), landing_altitude / 1000.0, landing_radial_speed]
				if not propellant_available and stage_index >= rocket_stages.size() - 1:
					_fail_autopilot("OUT OF PROPELLANT DURING LANDING")
			"ARRIVAL_PENDING":
				_fail_autopilot("ARRIVAL WINDOW MISSED  •  TARGET OUTSIDE CAPTURE REGION")
			"COMPLETE":
				status_message = "AUTOPILOT  •  TARGET ORBIT ACHIEVED"
				thrust_key_down = false
				autopilot_complete = true
			"FAILED":
				thrust_key_down = false
		var autopilot_direction := prograde
		if autopilot_phase == "ASCENT":
			autopilot_direction = radial * sin(deg_to_rad(pitch_above_horizon)) + tangent * cos(deg_to_rad(pitch_above_horizon))
		elif autopilot_phase in ["CIRCULARISE", "CIRCULARISE_BURN"]:
			autopilot_direction = autopilot_burn_direction if autopilot_burn_direction.length_squared() > 0.5 else tangent
		elif autopilot_phase in ["WAIT_WINDOW", "ALIGN_DEPARTURE"]:
			autopilot_direction = tangent * autopilot_transfer_direction
		elif autopilot_phase in ["TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"]:
			autopilot_direction = autopilot_burn_direction if autopilot_burn_direction.length_squared() > 0.5 else tangent * autopilot_transfer_direction
		elif autopilot_phase == "LANDING_DESCENT":
			var landing_direction_state := _autopilot_target_state()
			var landing_direction_position := _relative_position_to_body(landing_direction_state)
			var landing_direction_velocity: Vector2 = velocity - landing_direction_state.velocity
			var landing_direction_up := landing_direction_position.normalized()
			var landing_direction_tangent := Vector2(-landing_direction_up.y, landing_direction_up.x)
			var landing_direction_gravity := G * float(landing_direction_state.mass) / pow(landing_direction_position.length(), 2.0)
			var landing_direction_radial_speed := landing_direction_velocity.dot(landing_direction_up)
			var landing_direction_tangential_speed := landing_direction_velocity.dot(landing_direction_tangent)
			var landing_direction_altitude := landing_direction_position.length() - float(landing_direction_state.radius)
			var landing_direction_target_speed := -maxf(1.5, minf(60.0, sqrt(2.0 * landing_direction_gravity * maxf(0.0, landing_direction_altitude - 2.0))))
			var landing_direction_radial_acceleration := maxf(0.0, landing_direction_gravity + (landing_direction_target_speed - landing_direction_radial_speed) / 15.0)
			var landing_direction_tangential_acceleration := -landing_direction_tangential_speed / 180.0
			var landing_direction_vector := landing_direction_up * landing_direction_radial_acceleration + landing_direction_tangent * landing_direction_tangential_acceleration
			autopilot_direction = landing_direction_vector.normalized() if landing_direction_vector.length_squared() > 0.001 else landing_direction_up
		if autopilot_phase in ["FAILED", "COMPLETE"]:
			rcs_rotation_input = 0.0
			rcs_rotation_scale = 0.0
			return
		var autopilot_target_rotation := autopilot_direction.angle() - Vector2.UP.angle()
		var burn_expected := autopilot_phase in ["ASCENT", "CIRCULARISE_BURN", "TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN", "LANDING_DESCENT"]
		var attitude_ready := _autopilot_attitude_control(autopilot_target_rotation, dt, burn_expected)
		if burn_expected and not attitude_ready:
			thrust_key_down = false
		return
	elif guidance_velocity.length() > 1500.0:
		pitch_above_horizon = minf(pitch_above_horizon, 12.0)
	var manual_target_direction := radial * sin(deg_to_rad(pitch_above_horizon)) + tangent * cos(deg_to_rad(pitch_above_horizon))
	var manual_target_rotation := manual_target_direction.angle() - Vector2.UP.angle()
	rotation_angle = lerp_angle(rotation_angle, manual_target_rotation, clampf(dt * 0.08, 0.0, 1.0))
	angular_velocity = 0.0

func _flight_input_blocked_by_gui() -> bool:
	if not is_inside_tree():
		return false
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is CodeEdit

func _input(event: InputEvent) -> void:
	if not input_enabled or not event is InputEventKey or not event.pressed or event.echo:
		return
	if _flight_input_blocked_by_gui():
		return
	var ignite_pressed: bool = event.is_action_pressed("engine_toggle") or event.keycode == KEY_W or event.physical_keycode == KEY_W
	var cutoff_pressed: bool = event.is_action_pressed("throttle_cutoff") or event.keycode == KEY_S or event.physical_keycode == KEY_S
	if event.keycode == KEY_T or event.physical_keycode == KEY_T:
		if str(payload_visual.get("visual_type", "")) == "satellite" and float(payload_visual.get("telescope_range_au", 0.0)) > 0.0:
			telescope_active = not telescope_active
			status_message = "TELESCOPE ACTIVE  •  PROGRADE SCANNING" if telescope_active else "TELESCOPE STANDBY"
	if ignite_pressed:
		if autopilot_enabled:
			autopilot_enabled = false
			guidance_enabled = false
			rcs_rotation_input = 0.0
			rcs_rotation_scale = 0.0
		if landed and (infinite_weightless_fuel or fuel > 0.0):
			thrust_key_down = true
		else:
			thrust_key_down = not thrust_key_down
	elif cutoff_pressed:
		if autopilot_enabled:
			autopilot_enabled = false
			guidance_enabled = false
			rcs_rotation_input = 0.0
			rcs_rotation_scale = 0.0
		thrust_key_down = false
		throttle_cutoff_key_down = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		thrust_key_down = false
		throttle_cutoff_key_down = false
		rcs_rotation_input = 0.0
		rcs_rotation_scale = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and _flight_input_blocked_by_gui():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var selected_part := _part_at_screen_position(event.position)
			if not selected_part.is_empty():
				part_selected.emit(selected_part)
				get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if show_solar_system:
				solar_map_zoom = minf(8.0, solar_map_zoom * 1.2)
			else:
				camera_zoom = minf(1.0, camera_zoom * 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if show_solar_system:
				solar_map_zoom = maxf(0.25, solar_map_zoom / 1.2)
			else:
				camera_zoom = maxf(0.00000000002, camera_zoom / 1.2)
		return
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	if event.is_action_pressed("stage_next"):
		staging_stage_requested.emit()
	elif event.is_action_pressed("stage_separation"):
		_separate_stage()
	elif event.is_action_pressed("guidance_toggle"):
		guidance_enabled = not guidance_enabled
		if not guidance_enabled:
			autopilot_enabled = false
			thrust_key_down = false
			rcs_rotation_input = 0.0
			rcs_rotation_scale = 0.0
	else:
		match event.keycode:
			KEY_HOME:
				camera_zoom = 0.000045
				solar_map_zoom = 1.0
			KEY_EQUAL, KEY_KP_ADD:
				time_warp = minf(1000000.0, time_warp * 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				time_warp = maxf(0.25, time_warp / 2.0)
			KEY_O:
				show_orbit = not show_orbit
			KEY_P:
				show_predicted_trajectory = not show_predicted_trajectory
				if show_predicted_trajectory:
					_calculate_predicted_trajectory()
			KEY_M:
				show_solar_system = not show_solar_system
			KEY_G:
				show_grid = not show_grid
			KEY_V:
				show_vectors = not show_vectors
			KEY_Q:
				gimbal_angle = clampf(gimbal_angle - deg_to_rad(1.0), deg_to_rad(-8.0), deg_to_rad(8.0))
			KEY_E:
				gimbal_angle = clampf(gimbal_angle + deg_to_rad(1.0), deg_to_rad(-8.0), deg_to_rad(8.0))

func _launch_pad_surface_normal() -> Vector2:
	return launch_pad_normal.rotated(EARTH_ROTATION_RATE * (sim_time - launch_pad_reference_time)).normalized()

func _smooth_circle_segments(radius: float) -> int:
	var visible_radius := minf(maxf(1.0, radius), maxf(size.x, size.y) * 2.0)
	return clampi(ceili(TAU * sqrt(visible_radius * 0.75)), 96, 512)

func _draw_smooth_disc(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var segments := _smooth_circle_segments(radius)
	var points := PackedVector2Array()
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)

func _draw_smooth_circle(center: Vector2, radius: float, color: Color, width: float = 1.0) -> void:
	if radius <= 0.0:
		return
	var segments := _smooth_circle_segments(radius)
	var points := PackedVector2Array()
	for index in range(segments + 1):
		var angle := TAU * float(index % segments) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, color, width, true)

func _draw_atmosphere(center: Vector2, planet_radius: float, atmosphere_height: float, atmosphere_color: Color) -> void:
	if atmosphere_height <= 0.0:
		return
	var physical_thickness := atmosphere_height * camera_zoom * _visual_scale()
	var visible_thickness := clampf(physical_thickness, 3.0, 34.0)
	var rings := 18
	if planet_radius > maxf(size.x, size.y) * 2.0:
		rings = 6
	elif planet_radius > maxf(size.x, size.y):
		rings = 10
	for ring in range(rings, 0, -1):
		var fraction := float(ring) / float(rings)
		var ring_radius := planet_radius + visible_thickness * fraction
		var alpha := 0.012 + 0.075 * (1.0 - fraction)
		_draw_smooth_disc(center, ring_radius, Color(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, alpha))
	_draw_smooth_circle(center, planet_radius + visible_thickness, Color(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, 0.34), 1.0)

func _draw_planet_rings(center: Vector2, planet_radius: float, visual_data: Dictionary, opacity_scale: float = 1.0) -> void:
	if not bool(visual_data.get("has_rings", false)):
		return
	var inner_radius := planet_radius * float(visual_data.get("ring_inner_ratio", 1.2))
	var outer_radius := planet_radius * float(visual_data.get("ring_outer_ratio", 2.0))
	var ring_color: Color = visual_data.get("ring_color", Color.WHITE)
	var alpha := float(visual_data.get("ring_opacity", 0.5)) * opacity_scale
	var line_width := maxf(1.0, (outer_radius - inner_radius) * 0.16)
	for ring_radius in [inner_radius, (inner_radius + outer_radius) * 0.5, outer_radius]:
		_draw_smooth_circle(center, ring_radius, Color(ring_color.r, ring_color.g, ring_color.b, alpha), line_width)

func _planet_atmosphere_visual(name: String) -> Dictionary:
	var visual_data := PlanetarySystem.planet_visual_data(name)
	return {
		"height": float(visual_data.get("atmosphere_height", 0.0)),
		"color": visual_data.get("atmosphere_color", Color.TRANSPARENT)
	}

func _draw_destination_satellites(host_name: String, host_screen: Vector2, host_radius_px: float, host_state: Dictionary) -> void:
	var host_planet: Dictionary = {}
	for planet in PlanetarySystem.PLANETS:
		if str(planet.get("name", "")) == host_name:
			host_planet = planet
			break
	if host_planet.is_empty():
		return
	for satellite_variant in host_planet.get("satellites", []):
		var satellite: Dictionary = satellite_variant
		var satellite_name := "%s %s" % [host_name, str(satellite.get("name", "Moon"))]
		if not discovered_body_names.has(satellite_name):
			continue
		var satellite_state := _surface_body_state(satellite_name)
		if satellite_state.is_empty():
			continue
		var host_position: Vector2 = host_state.get("position", Vector2.ZERO)
		var satellite_position: Vector2 = satellite_state.get("position", Vector2.ZERO)
		var world_offset := satellite_position - host_position
		var direction := Vector2(world_offset.x, -world_offset.y).normalized()
		var orbit_ratio := maxf(1.0, float(satellite.get("semi_major_axis_m", 0.0)) / float(host_planet.get("radius", 1.0)))
		var orbit_radius_px := host_radius_px + 4.0 + log(orbit_ratio) * maxf(1.5, host_radius_px * 0.08)
		var satellite_color := PlanetarySystem.color_from_rgb(satellite.get("color_rgb", []), Color(0.75, 0.78, 0.82))
		var satellite_visited := visited_body_names.has(satellite_name)
		if not satellite_visited:
			satellite_color = satellite_color.darkened(0.58).lerp(Color(0.34, 0.44, 0.58), 0.4)
		draw_arc(host_screen, orbit_radius_px, 0.0, TAU, 48, Color(satellite_color.r, satellite_color.g, satellite_color.b, 0.3 if satellite_visited else 0.1), 1.0)
		var satellite_screen := host_screen + direction * orbit_radius_px
		if not satellite_visited:
			draw_circle(satellite_screen, maxf(3.5, host_radius_px * 0.09), Color(0.34, 0.58, 0.84, 0.18))
		draw_circle(satellite_screen, maxf(1.5, host_radius_px * 0.06), satellite_color)
		if host_radius_px >= 16.0:
			draw_string(ThemeDB.fallback_font, satellite_screen + Vector2(4.0, -3.0), str(satellite.get("name", "Moon")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, satellite_color)


func _draw() -> void:
	var view_center := get_viewport_rect().size * 0.5
	var world_scale_factor := _visual_scale()
	var radius_px := maxf(4.0, EARTH_RADIUS * camera_zoom * world_scale_factor)
	var rocket_screen := view_center
	var radial_direction := rocket_position.normalized()
	var altitude_for_view := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
	var altitude_display := altitude_for_view * (1.0 + 7.0 * exp(-altitude_for_view / 100000.0))
	var altitude_visual_scale := camera_zoom * world_scale_factor
	var earth_screen := view_center - radial_direction * (radius_px + altitude_display * altitude_visual_scale)
	camera_offset = rocket_position

	for star in star_points:
		var p := view_center + star * 0.035
		draw_circle(p, 1.0, Color(0.55, 0.7, 0.9, 0.5))

	if show_solar_system:
		_draw_solar_system(view_center)
		_draw_docked_visuals(view_center, RocketVisual.camera_scale(camera_zoom, world_scale_factor))
		_draw_hud()
		return
	if camera_zoom <= 0.0000000002:
		_draw_full_system_zoom(view_center)
		_draw_docked_visuals(view_center, RocketVisual.camera_scale(camera_zoom, world_scale_factor))
		_draw_offscreen_body_indicators(view_center, altitude_visual_scale)
		_draw_hud()
		return

	if show_grid:
		_draw_grid(view_center)

	var earth_visual := PlanetarySystem.planet_visual_data("Earth")
	_draw_atmosphere(earth_screen, radius_px, float(earth_visual.get("atmosphere_height", 100000.0)), earth_visual.get("atmosphere_color", Color(0.22, 0.62, 1.0)))
	_draw_smooth_disc(earth_screen, radius_px + 7.0, Color(0.15, 0.35, 0.58, 0.12))
	var earth_color: Color = earth_visual.get("surface_color", Color(0.10, 0.28, 0.53))
	_draw_smooth_disc(earth_screen, radius_px, earth_color)
	_draw_smooth_circle(earth_screen, radius_px, earth_color.lightened(0.25), 2.0)
	draw_arc(earth_screen, radius_px * 0.76, -0.4, 2.4, 96, Color(0.18, 0.43, 0.48, 0.45), 2.0, true)
	draw_arc(earth_screen, radius_px * 0.53, 2.2, 5.4, 96, Color(0.18, 0.43, 0.48, 0.35), 2.0, true)
	var object_scale := RocketVisual.camera_scale(camera_zoom, world_scale_factor)
	var pad_width := clampf(34.0 * object_scale, 0.5, 85.0)
	var pad_height := clampf(7.0 * object_scale, 0.5, 18.0)
	var pad_normal := _launch_pad_surface_normal()
	var pad_tangent := Vector2(-pad_normal.y, pad_normal.x)
	var pad_center := earth_screen + pad_normal * (radius_px + 2.0 * object_scale)
	draw_line(pad_center - pad_tangent * pad_width, pad_center + pad_tangent * pad_width, Color(0.65, 0.72, 0.82), 3.0 * object_scale)
	draw_line(pad_center - pad_tangent * pad_width * 0.58, pad_center - pad_tangent * pad_width * 0.58 - pad_normal * pad_height, Color(0.65, 0.72, 0.82), 2.0 * object_scale)
	draw_line(pad_center + pad_tangent * pad_width * 0.58, pad_center + pad_tangent * pad_width * 0.58 - pad_normal * pad_height, Color(0.65, 0.72, 0.82), 2.0 * object_scale)
	draw_string(ThemeDB.fallback_font, earth_screen + Vector2(radius_px + 12, 4), "EARTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.78, 1.0))

	var moon_world := PlanetarySystem.moon_position(sim_time)
	var moon_screen := rocket_screen + (moon_world - rocket_position) * camera_zoom * world_scale_factor
	var moon_radius_px := maxf(2.0, PlanetarySystem.MOON_RADIUS * camera_zoom * world_scale_factor)
	if discovered_body_names.has("Moon") and moon_screen.x > -moon_radius_px and moon_screen.x < size.x + moon_radius_px and moon_screen.y > -moon_radius_px and moon_screen.y < size.y + moon_radius_px:
		var moon_color: Color = PlanetarySystem.planet_visual_data("Moon").get("color", Color(0.72, 0.74, 0.78))
		if not visited_body_names.has("Moon"):
			moon_color = moon_color.darkened(0.58).lerp(Color(0.34, 0.44, 0.58), 0.4)
			draw_circle(moon_screen, moon_radius_px + 5.0, Color(0.34, 0.58, 0.84, 0.18))
		else:
			draw_circle(moon_screen, moon_radius_px + 3.0, Color(0.55, 0.58, 0.66, 0.16))
		_draw_smooth_disc(moon_screen, moon_radius_px, moon_color.darkened(0.2))
		_draw_smooth_circle(moon_screen, moon_radius_px, moon_color, 1.0)
		draw_string(ThemeDB.fallback_font, moon_screen + Vector2(moon_radius_px + 8.0, 4.0), "MOON", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.84) if visited_body_names.has("Moon") else Color(0.43, 0.56, 0.72))

	var destination := _nearest_body_state(rocket_position)
	if str(destination.name) not in ["Earth", "Moon"] and float(destination.distance) < float(destination.soi):
		var destination_screen: Vector2 = rocket_screen + (Vector2(destination.position) - rocket_position) * altitude_visual_scale
		var destination_radius := clampf(float(destination.radius) * altitude_visual_scale, 3.0, 72.0)
		if destination_screen.x > -destination_radius - 30.0 and destination_screen.x < size.x + destination_radius + 30.0 and destination_screen.y > -destination_radius - 30.0 and destination_screen.y < size.y + destination_radius + 30.0:
			var destination_visual := PlanetarySystem.planet_visual_data(str(destination.name))
			var destination_color: Color = destination_visual.get("color", Color(0.82, 0.38, 0.25))
			if not visited_body_names.has(str(destination.name)):
				destination_color = destination_color.darkened(0.58).lerp(Color(0.32, 0.43, 0.58), 0.4)
			var atmosphere_visual: Dictionary = _planet_atmosphere_visual(str(destination.name))
			_draw_atmosphere(destination_screen, destination_radius, float(atmosphere_visual.get("height", 0.0)), atmosphere_visual.get("color", Color.TRANSPARENT))
			_draw_smooth_disc(destination_screen, destination_radius + 5.0, Color(0.45, 0.7, 1.0, 0.12))
			_draw_planet_rings(destination_screen, destination_radius, destination_visual)
			_draw_smooth_disc(destination_screen, destination_radius, destination_color)
			_draw_smooth_circle(destination_screen, destination_radius, Color(0.9, 0.92, 1.0, 0.8), 1.0)
			draw_string(ThemeDB.fallback_font, destination_screen + Vector2(destination_radius + 8.0, 4.0), str(destination.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.88, 1.0))
			_draw_destination_satellites(str(destination.name), destination_screen, destination_radius, destination)
		var soi_pixels := float(destination.soi) * altitude_visual_scale
		if soi_pixels > destination_radius and soi_pixels < 1200.0:
			draw_arc(destination_screen, soi_pixels, 0.0, TAU, 100, Color(0.35, 0.72, 1.0, 0.22), 1.0)

	_draw_offscreen_body_indicators(rocket_screen, altitude_visual_scale)

	if show_orbit:
		_draw_orbit(rocket_screen, world_scale_factor)

	if trail.size() > 1:
		var trail_points := PackedVector2Array()
		for p_world in trail:
			trail_points.append(view_center + (p_world - rocket_position) * camera_zoom * world_scale_factor + (rocket_screen - view_center))
		draw_polyline(trail_points, Color(0.2, 0.85, 0.95, 0.7), 2.0)

	if show_predicted_trajectory and predicted_path.size() > 1:
		var prediction_points := PackedVector2Array()
		for point in predicted_path:
			prediction_points.append(rocket_screen + (point - rocket_position) * camera_zoom * world_scale_factor)
		draw_polyline(prediction_points, Color(1.0, 0.72, 0.22, 0.85), 2.0)
	if landed:
		draw_line(rocket_screen + Vector2(-30.0, 13.0) * object_scale, rocket_screen + Vector2(30.0, 13.0) * object_scale, Color(0.72, 0.78, 0.86), 3.0 * object_scale)
		draw_line(rocket_screen + Vector2(-18.0, 13.0) * object_scale, rocket_screen + Vector2(-18.0, 25.0) * object_scale, Color(0.72, 0.78, 0.86), 2.0 * object_scale)
		draw_line(rocket_screen + Vector2(18.0, 13.0) * object_scale, rocket_screen + Vector2(18.0, 25.0) * object_scale, Color(0.72, 0.78, 0.86), 2.0 * object_scale)
	for fleet_entry in fleet_visuals:
		var fleet_position: Vector2 = fleet_entry.get("position", rocket_position)
		var fleet_orbit: PackedVector2Array = fleet_entry.get("orbit_points", PackedVector2Array())
		if fleet_orbit.size() > 1:
			var orbit_screen := PackedVector2Array()
			for orbit_point in fleet_orbit:
				orbit_screen.append(rocket_screen + (orbit_point - rocket_position) * altitude_visual_scale)
			draw_polyline(orbit_screen, Color(0.2, 0.75, 1.0, 0.62), 1.8)
		var fleet_screen := rocket_screen + (fleet_position - rocket_position) * altitude_visual_scale
		if fleet_screen.x < -40.0 or fleet_screen.x > size.x + 40.0 or fleet_screen.y < -40.0 or fleet_screen.y > size.y + 40.0:
			continue
		var fleet_design: Dictionary = fleet_entry.get("design", {})
		var fleet_stage := int(fleet_entry.get("stage_index", 0))
		if bool(fleet_entry.get("crashed", false)):
			RocketVisual.draw_wreck(self, fleet_screen, float(fleet_entry.get("rotation", 0.0)), object_scale * 0.72)
		else:
			RocketVisual.draw_vehicle(self, fleet_design, fleet_screen, float(fleet_entry.get("rotation", 0.0)), object_scale * 0.72, fleet_stage, 0.0, false)
	if crashed:
		RocketVisual.draw_wreck(self, rocket_screen, rotation_angle, object_scale)
	else:
		_draw_rocket(rocket_screen, object_scale)
	_draw_docked_visuals(rocket_screen, object_scale)
	_draw_collision_effects(rocket_screen, altitude_visual_scale)
	if show_vectors:
		var velocity_end := rocket_screen + velocity.normalized() * 65.0
		draw_line(rocket_screen, velocity_end, Color(0.25, 0.9, 0.55), 2.0)
		draw_string(ThemeDB.fallback_font, velocity_end + Vector2(6, 0), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.9, 0.55))

	_draw_hud()


func _draw_collision_effects(rocket_screen: Vector2, scale: float) -> void:
	for effect in collision_effects:
		var duration := maxf(0.001, float(effect.get("duration", 2.4)))
		var progress := clampf(float(effect.get("age", 0.0)) / duration, 0.0, 1.0)
		var intensity := float(effect.get("intensity", 1.0))
		var position: Vector2 = effect.get("position", rocket_position)
		var screen_position := rocket_screen + (position - rocket_position) * scale
		if screen_position.x < -180.0 or screen_position.x > size.x + 180.0 or screen_position.y < -180.0 or screen_position.y > size.y + 180.0:
			continue
		var radius := (10.0 + progress * 105.0) * sqrt(intensity)
		var alpha := 1.0 - progress
		draw_circle(screen_position, maxf(1.0, 13.0 * (1.0 - progress) * intensity), Color(1.0, 0.72, 0.28, alpha * 0.72))
		draw_arc(screen_position, radius, 0.0, TAU, 48, Color(1.0, 0.36, 0.12, alpha * 0.9), maxf(1.0, 3.0 * (1.0 - progress)))
		draw_arc(screen_position, radius * 0.68, 0.0, TAU, 40, Color(1.0, 0.82, 0.48, alpha * 0.7), maxf(1.0, 2.0 * (1.0 - progress)))
		for spark_index in range(12):
			var angle := TAU * float(spark_index) / 12.0 + float(effect.get("age", 0.0)) * (0.7 if spark_index % 2 == 0 else -0.5)
			var distance := radius * (0.55 + 0.35 * sin(progress * PI))
			var direction := Vector2.RIGHT.rotated(angle)
			draw_line(screen_position + direction * radius * 0.2, screen_position + direction * distance, Color(1.0, 0.62, 0.24, alpha), 1.6)

func _draw_docked_visuals(rocket_screen: Vector2, object_scale: float) -> void:
	for attached in docked_visuals:
		var direction: Vector2 = attached.get("direction", Vector2.RIGHT)
		if direction.length_squared() < 0.0001:
			direction = Vector2.RIGHT
		direction = direction.normalized()
		var child_screen := rocket_screen + direction * 38.0 * object_scale
		draw_line(rocket_screen, child_screen, Color(0.55, 0.82, 1.0, 0.9), 2.0 * object_scale)
		draw_circle(child_screen, 3.5 * object_scale, Color(0.55, 0.82, 1.0))
		var child_rotation := float(attached.get("rotation", rotation_angle))
		var child_design: Dictionary = attached.get("design", {})
		_draw_rocket(child_screen, object_scale * 0.72, child_design, int(attached.get("stage_index", 0)), 0.0, false)
		draw_string(ThemeDB.fallback_font, child_screen + Vector2(10.0, 4.0) * object_scale, str(attached.get("name", "DOCKED")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.68, 0.84, 1.0))

func _draw_full_system_zoom(view_center: Vector2) -> void:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	var bodies: Array = states.get("bodies", [])
	var scale := camera_zoom * _visual_scale()
	var sun_position := Vector2.ZERO
	for body_variant in bodies:
		var body: Dictionary = body_variant
		if str(body.get("name", "")) == "Sun":
			sun_position = Vector2(body.get("position", Vector2.ZERO))
			break
	var sun_screen := view_center + (sun_position - rocket_position) * scale
	for planet in PlanetarySystem.PLANETS:
		if not discovered_body_names.has(str(planet.get("name", ""))):
			continue
		var planet_name := str(planet.get("name", ""))
		var orbit_radius := float(planet.a) * PlanetarySystem.ASTRONOMICAL_UNIT * scale
		if orbit_radius > 2.0 and orbit_radius < maxf(size.x, size.y) * 1.5:
			var orbit_alpha := 0.28 if visited_body_names.has(planet_name) else 0.1
			draw_arc(sun_screen, orbit_radius, 0.0, TAU, 160, Color(0.28, 0.43, 0.58, orbit_alpha), 1.0)
	for body_variant in bodies:
		var body: Dictionary = body_variant
		var body_name := str(body.get("name", ""))
		if body_name != "Sun" and not discovered_body_names.has(body_name):
			continue
		var body_position: Vector2 = Vector2(body.get("position", Vector2.ZERO))
		var screen_position := view_center + (body_position - rocket_position) * scale
		if screen_position.x < -24.0 or screen_position.x > size.x + 24.0 or screen_position.y < -24.0 or screen_position.y > size.y + 24.0:
			continue
		var body_radius := clampf(float(body.get("radius", 1.0)) * scale, 1.5, 9.0)
		var body_color: Color
		if body_name == "Sun":
			body_color = PlanetarySystem.system_visual_color()
			draw_circle(screen_position, body_radius + 5.0, Color(body_color.r, body_color.g, body_color.b, 0.14))
		else:
			body_color = PlanetarySystem.planet_visual_data(body_name).get("color", Color(0.72, 0.78, 0.86))
			if not visited_body_names.has(body_name):
				body_color = body_color.darkened(0.62).lerp(Color(0.38, 0.48, 0.62), 0.35)
				draw_circle(screen_position, body_radius + 3.0, Color(0.36, 0.58, 0.82, 0.16))
		_draw_smooth_disc(screen_position, body_radius, body_color)
		if body_radius >= 2.0 or body_name in ["Sun", "Earth", "Moon"]:
			var label_position := screen_position + Vector2(body_radius + 4.0, 3.0)
			draw_string(ThemeDB.fallback_font, label_position, body_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, body_color.lightened(0.2))
	var earth_screen := view_center - rocket_position * scale
	var earth_radius := clampf(PlanetarySystem.EARTH_RADIUS * scale, 1.5, 9.0)
	var earth_color: Color = PlanetarySystem.planet_visual_data("Earth").get("color", Color(0.25, 0.55, 0.82))
	_draw_smooth_disc(earth_screen, earth_radius, earth_color)
	if earth_screen.distance_to(view_center) > 12.0:
		draw_string(ThemeDB.fallback_font, earth_screen + Vector2(earth_radius + 4.0, 3.0), "EARTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, earth_color)
	draw_circle(view_center, 3.0, Color(0.3, 1.0, 0.65))
	draw_string(ThemeDB.fallback_font, view_center + Vector2(7.0, -7.0), "ROCKET", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 1.0, 0.72))
	draw_string(ThemeDB.fallback_font, Vector2(18.0, 20.0), "SOLAR SYSTEM  •  ROCKET-CENTRED VIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.8, 1.0))

func _draw_offscreen_body_indicators(view_center: Vector2, scale: float) -> void:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	var candidates: Array[Dictionary] = []
	var earth_position := Vector2.ZERO
	var earth_screen := view_center + (earth_position - rocket_position) * scale
	if earth_screen.x < 0.0 or earth_screen.x > size.x or earth_screen.y < 0.0 or earth_screen.y > size.y:
		candidates.append({"name": "Earth", "distance": earth_position.distance_to(rocket_position), "direction": (earth_screen - view_center).normalized(), "color": PlanetarySystem.planet_visual_data("Earth").get("color", Color(0.25, 0.55, 0.82))})
	for body_variant in states.get("bodies", []):
		var body: Dictionary = body_variant
		var body_name := str(body.get("name", ""))
		if body_name != "Sun" and not discovered_body_names.has(body_name):
			continue
		var body_position: Vector2 = Vector2(body.get("position", Vector2.ZERO))
		var screen_position := view_center + (body_position - rocket_position) * scale
		if screen_position.x >= 0.0 and screen_position.x <= size.x and screen_position.y >= 0.0 and screen_position.y <= size.y:
			continue
		var distance := body_position.distance_to(rocket_position)
		var color: Color = PlanetarySystem.system_visual_color() if body_name == "Sun" else PlanetarySystem.planet_visual_data(body_name).get("color", Color(0.72, 0.78, 0.86))
		candidates.append({"name": body_name, "distance": distance, "direction": (screen_position - view_center).normalized(), "color": color})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var count := mini(4, candidates.size())
	for index in range(count):
		var candidate: Dictionary = candidates[index]
		var direction: Vector2 = candidate.direction
		if direction.length_squared() < 0.0001:
			continue
		var half_size := size * 0.5 - Vector2(34.0, 34.0)
		var edge_distance := INF
		if absf(direction.x) > 0.0001:
			edge_distance = minf(edge_distance, half_size.x / absf(direction.x))
		if absf(direction.y) > 0.0001:
			edge_distance = minf(edge_distance, half_size.y / absf(direction.y))
		var edge_position := view_center + direction * edge_distance
		edge_position.y = clampf(edge_position.y + (float(index) - float(count - 1) * 0.5) * 24.0, 28.0, size.y - 28.0)
		var color: Color = candidate.color
		if not visited_body_names.has(str(candidate.name)):
			color = color.darkened(0.58).lerp(Color(0.32, 0.43, 0.58), 0.4)
		var side := direction
		var tip := edge_position + side * 9.0
		var base := edge_position - side * 7.0
		var perpendicular := Vector2(-side.y, side.x)
		draw_colored_polygon(PackedVector2Array([tip, base + perpendicular * 6.0, base - perpendicular * 6.0]), color)
		var distance_text := "%.2f AU" % (float(candidate.distance) / PlanetarySystem.ASTRONOMICAL_UNIT) if float(candidate.distance) >= 1000000000.0 else _format_distance(float(candidate.distance))
		var label := "%s  %s" % [str(candidate.name).to_upper(), distance_text]
		var label_offset := Vector2(12.0, 4.0) if direction.x < 0.7 else Vector2(-150.0, 4.0)
		draw_string(ThemeDB.fallback_font, edge_position + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, 145, 10, color)


func _draw_solar_label(label: String, anchor: Vector2, font_size: int, color: Color, occupied: Array[Rect2]) -> void:
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_size := text_size + Vector2(10.0, 6.0)
	var offsets: Array[Vector2] = [
		Vector2(10.0, -label_size.y - 5.0),
		Vector2(10.0, 5.0),
		Vector2(-label_size.x - 10.0, -label_size.y - 5.0),
		Vector2(-label_size.x - 10.0, 5.0),
		Vector2(0.0, -label_size.y - 13.0),
		Vector2(0.0, 13.0),
		Vector2(15.0, -label_size.y * 0.5),
		Vector2(-label_size.x - 15.0, -label_size.y * 0.5)
	]
	var chosen := Rect2()
	var found := false
	for offset in offsets:
		var candidate := Rect2(anchor + offset, label_size)
		candidate.position.x = clampf(candidate.position.x, 8.0, maxf(8.0, size.x - label_size.x - 8.0))
		candidate.position.y = clampf(candidate.position.y, 8.0, maxf(8.0, size.y - label_size.y - 42.0))
		var overlaps := false
		for existing in occupied:
			if candidate.intersects(existing):
				overlaps = true
				break
		if not overlaps:
			chosen = candidate
			found = true
			break
	if not found:
		var columns: Array[float] = [12.0, maxf(12.0, size.x - label_size.x - 12.0)]
		var row_count: int = maxi(1, int((size.y - 60.0) / (label_size.y + 5.0)))
		for row in range(row_count):
			for column_x in columns:
				var candidate_y: float = 42.0 + float(row) * (label_size.y + 5.0)
				var candidate := Rect2(Vector2(column_x, candidate_y), label_size)
				var overlaps := false
				for existing in occupied:
					if candidate.intersects(existing):
						overlaps = true
						break
				if not overlaps:
					chosen = candidate
					found = true
					break
			if found:
				break
		if not found:
			chosen = Rect2(Vector2(columns[1], maxf(42.0, size.y - label_size.y - 42.0)), label_size)
	if chosen.position.distance_to(anchor) > 24.0:
		draw_line(anchor, chosen.position + Vector2(0.0, label_size.y * 0.5), Color(color.r, color.g, color.b, 0.5), 1.0)
	draw_rect(chosen, Color(0.025, 0.045, 0.075, 0.88), true)
	draw_string(font, chosen.position + Vector2(5.0, text_size.y + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	occupied.append(chosen)

func _draw_solar_system(center: Vector2) -> void:
	var ephemeris: Dictionary = PlanetarySystem.gravity_body_states(sim_time)
	var heliocentric_bodies: Array = ephemeris.get("heliocentric_bodies", [])
	if heliocentric_bodies.is_empty():
		return
	var earth_heliocentric: Vector2 = Vector2(ephemeris.get("earth_heliocentric_position", Vector2.ZERO))
	var system_extent: float = PlanetarySystem.ASTRONOMICAL_UNIT
	for planet in PlanetarySystem.PLANETS:
		system_extent = maxf(system_extent, float(planet.a) * PlanetarySystem.ASTRONOMICAL_UNIT)
	for belt in solar_belt_particles:
		system_extent = maxf(system_extent, float(belt.get("outer_radius_m", 0.0)))
	var map_scale: float = minf(size.x * 0.82, size.y * 0.78) / (system_extent * 2.0) * solar_map_zoom
	var occupied: Array[Rect2] = []
	var header := Rect2(Vector2(18.0, 14.0), Vector2(minf(size.x - 36.0, 370.0), 24.0))
	draw_rect(header, Color(0.025, 0.045, 0.075, 0.9), true)
	draw_string(ThemeDB.fallback_font, header.position + Vector2(7.0, 18.0), "SOLAR SYSTEM  •  KNOWN BODIES ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.8, 1.0))
	occupied.append(header)
	var sun_screen := center
	var sun_color := PlanetarySystem.system_visual_color()
	draw_circle(sun_screen, 7.0, sun_color)
	draw_circle(sun_screen, 11.0, Color(sun_color.r, sun_color.g, sun_color.b, 0.12))
	_draw_solar_label("SUN", sun_screen, 11, sun_color.lightened(0.15), occupied)
	var positions: Dictionary = {}
	for planet in PlanetarySystem.PLANETS:
		if not discovered_body_names.has(str(planet.get("name", ""))):
			continue
		var planet_name := str(planet.get("name", ""))
		var orbit_radius: float = float(planet.a) * PlanetarySystem.ASTRONOMICAL_UNIT
		var orbit_alpha := 0.34 if visited_body_names.has(planet_name) else 0.12
		draw_arc(center, orbit_radius * map_scale, 0.0, TAU, 180, Color(0.28, 0.43, 0.58, orbit_alpha), 1.0)
	for belt in solar_belt_particles:
		var belt_inner_radius := float(belt.get("inner_radius_m", 0.0))
		var belt_outer_radius := float(belt.get("outer_radius_m", 0.0))
		var belt_color: Color = belt.get("color", Color(0.72, 0.65, 0.52))
		var belt_opacity := float(belt.get("opacity", 0.35))
		draw_arc(center, belt_inner_radius * map_scale, 0.0, TAU, 180, Color(belt_color.r, belt_color.g, belt_color.b, belt_opacity * 0.12), 1.0)
		draw_arc(center, belt_outer_radius * map_scale, 0.0, TAU, 180, Color(belt_color.r, belt_color.g, belt_color.b, belt_opacity * 0.12), 1.0)
		for particle_variant in belt.get("particles", []):
			var particle: Dictionary = particle_variant
			var angle := wrapf(float(particle.phase_rad) + float(particle.angular_rate) * sim_time, -PI, PI)
			var radius := float(particle.radius_m)
			var particle_position := Vector2(radius * cos(angle), radius * sin(angle))
			var particle_screen := center + Vector2(particle_position.x, -particle_position.y) * map_scale
			draw_circle(particle_screen, float(particle.size_px), Color(belt_color.r, belt_color.g, belt_color.b, belt_opacity))
		var label_radius := (belt_inner_radius + belt_outer_radius) * 0.5
		var label_angle := 1.1
		var label_position := center + Vector2(cos(label_angle), -sin(label_angle)) * label_radius * map_scale
		_draw_solar_label(str(belt.get("name", "BELT")).to_upper(), label_position, 9, Color(belt_color.r, belt_color.g, belt_color.b, 0.9), occupied)
	for body_variant in heliocentric_bodies:
		var body: Dictionary = body_variant
		var body_name: String = str(body.get("name", ""))
		positions[body_name] = Vector2(body.get("position", Vector2.ZERO))
	for planet in PlanetarySystem.PLANETS:
		var planet_name: String = str(planet.name)
		if not discovered_body_names.has(planet_name):
			continue
		var planet_position: Vector2 = Vector2(positions.get(planet_name, Vector2.ZERO))
		var planet_screen: Vector2 = center + Vector2(planet_position.x, -planet_position.y) * map_scale
		var planet_radius: float = clampf(pow(float(planet.radius) / EARTH_RADIUS, 0.45) * 3.0, 2.0, 8.0)
		var planet_visual := PlanetarySystem.planet_visual_data(planet_name)
		var planet_color: Color = planet_visual.get("color", Color(0.65, 0.72, 0.82))
		var visited := visited_body_names.has(planet_name)
		if not visited:
			planet_color = planet_color.darkened(0.58).lerp(Color(0.32, 0.43, 0.58), 0.4)
		_draw_planet_rings(planet_screen, planet_radius, planet_visual, 0.85 if visited else 0.2)
		if not visited:
			_draw_smooth_disc(planet_screen, planet_radius + 4.0, Color(0.34, 0.58, 0.84, 0.2))
			_draw_smooth_disc(planet_screen, planet_radius, Color(0.025, 0.045, 0.075, 0.42))
		_draw_smooth_disc(planet_screen, planet_radius, planet_color)
		_draw_solar_label(planet_name.to_upper(), planet_screen, 10, Color(0.82, 0.88, 0.96) if visited else Color(0.43, 0.56, 0.72), occupied)
	for planet in PlanetarySystem.PLANETS:
		var planet_name: String = str(planet.name)
		if not discovered_body_names.has(planet_name):
			continue
		var host_position: Vector2 = positions.get(planet_name, Vector2.ZERO)
		var host_screen := center + Vector2(host_position.x, -host_position.y) * map_scale
		var host_radius := clampf(pow(float(planet.radius) / EARTH_RADIUS, 0.45) * 3.0, 2.0, 8.0)
		for satellite_variant in planet.get("satellites", []):
			var satellite: Dictionary = satellite_variant
			var satellite_name := "%s %s" % [planet_name, str(satellite.get("name", "Moon"))]
			if not discovered_body_names.has(satellite_name):
				continue
			var satellite_position: Vector2 = positions.get(satellite_name, host_position)
			var relative_direction := Vector2(satellite_position.x - host_position.x, -(satellite_position.y - host_position.y)).normalized()
			var orbit_ratio := maxf(1.0, float(satellite.get("semi_major_axis_m", 0.0)) / float(planet.radius))
			var orbit_radius_px := host_radius + 2.0 + log(orbit_ratio) * 1.6
			var satellite_color := PlanetarySystem.color_from_rgb(satellite.get("color_rgb", []), Color(0.75, 0.78, 0.82))
			var satellite_visited := visited_body_names.has(satellite_name)
			if not satellite_visited:
				satellite_color = satellite_color.darkened(0.58).lerp(Color(0.34, 0.44, 0.58), 0.4)
			draw_arc(host_screen, orbit_radius_px, 0.0, TAU, 32, Color(satellite_color.r, satellite_color.g, satellite_color.b, 0.22 if satellite_visited else 0.08), 1.0)
			var satellite_screen := host_screen + relative_direction * orbit_radius_px
			if not satellite_visited:
				draw_circle(satellite_screen, maxf(2.8, host_radius * 0.55), Color(0.34, 0.58, 0.84, 0.18))
			draw_circle(satellite_screen, maxf(1.3, host_radius * 0.45), satellite_color)
			if solar_map_zoom >= 2.0:
				_draw_solar_label(str(satellite.get("name", "MOON")).to_upper(), satellite_screen, 8, satellite_color, occupied)
	var earth_position: Vector2 = Vector2(positions.get("Earth", Vector2.ZERO))
	var earth_screen: Vector2 = center + Vector2(earth_position.x, -earth_position.y) * map_scale
	var moon_position: Vector2 = Vector2(positions.get("Moon", earth_position))
	var moon_offset := Vector2(moon_position.x - earth_position.x, -(moon_position.y - earth_position.y)).normalized()
	var earth_marker_radius := clampf(pow(PlanetarySystem.EARTH_RADIUS / EARTH_RADIUS, 0.45) * 3.0, 2.0, 8.0)
	var moon_orbit_display_radius := earth_marker_radius + 2.0 + log(PlanetarySystem.MOON_ORBIT_RADIUS / PlanetarySystem.EARTH_RADIUS) * 1.6
	var moon_screen := earth_screen + moon_offset * moon_orbit_display_radius
	if discovered_body_names.has("Moon"):
		draw_arc(earth_screen, moon_orbit_display_radius, 0.0, TAU, 32, Color(0.65, 0.69, 0.77, 0.22 if visited_body_names.has("Moon") else 0.08), 1.0)
		var moon_color: Color = PlanetarySystem.planet_visual_data("Moon").get("color", Color(0.72, 0.74, 0.78))
		if not visited_body_names.has("Moon"):
			moon_color = moon_color.darkened(0.58).lerp(Color(0.34, 0.44, 0.58), 0.4)
			draw_circle(moon_screen, 5.0, Color(0.34, 0.58, 0.84, 0.18))
		draw_circle(moon_screen, 2.5, moon_color)
		_draw_solar_label("MOON", moon_screen, 9, Color(0.78, 0.82, 0.9) if visited_body_names.has("Moon") else Color(0.43, 0.56, 0.72), occupied)
	var rocket_heliocentric: Vector2 = earth_heliocentric + rocket_position
	var rocket_screen: Vector2 = center + Vector2(rocket_heliocentric.x, -rocket_heliocentric.y) * map_scale
	draw_line(rocket_screen + Vector2(-6.0, 0.0), rocket_screen + Vector2(6.0, 0.0), Color(0.3, 1.0, 0.65), 2.0)
	draw_line(rocket_screen + Vector2(0.0, -6.0), rocket_screen + Vector2(0.0, 6.0), Color(0.3, 1.0, 0.65), 2.0)
	draw_circle(rocket_screen, 3.0, Color(0.3, 1.0, 0.65))
	_draw_solar_label("ROCKET", rocket_screen, 10, Color(0.4, 1.0, 0.72), occupied)
	for fleet_entry in fleet_visuals:
		var fleet_position: Vector2 = fleet_entry.get("position", rocket_position)
		var fleet_heliocentric := earth_heliocentric + fleet_position
		var fleet_marker := center + Vector2(fleet_heliocentric.x, -fleet_heliocentric.y) * map_scale
		draw_circle(fleet_marker, 2.4, Color(0.35, 0.78, 1.0))
		if solar_map_zoom >= 2.0:
			_draw_solar_label(str(fleet_entry.get("name", "SPACECRAFT")).to_upper(), fleet_marker, 8, Color(0.55, 0.82, 1.0), occupied)
	var footer_text: String = "SIM TIME  %.2f DAYS     MAP SCALE  %.2f×     WHEEL TO ZOOM" % [sim_time / 86400.0, solar_map_zoom]
	var footer_size: Vector2 = ThemeDB.fallback_font.get_string_size(footer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var footer_rect := Rect2(Vector2(18.0, size.y - 34.0), Vector2(footer_size.x + 14.0, 23.0))
	draw_rect(footer_rect, Color(0.025, 0.045, 0.075, 0.9), true)
	draw_string(ThemeDB.fallback_font, footer_rect.position + Vector2(7.0, 16.0), footer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.9))

func _calculate_predicted_trajectory() -> void:
	predicted_path.clear()
	var position := rocket_position
	var position_components := rocket_position_precise.duplicate()
	var predicted_velocity := velocity
	var predicted_fuel := fuel
	var predicted_stage_fuel_remaining := stage_fuel_remaining.duplicate()
	var predicted_stage := stage_index
	var dt := 5.0
	for i in range(360):
		var step_time := sim_time + float(i) * dt
		var mass := payload_mass + docked_mass
		var active: Dictionary = {}
		var total_flow := 0.0
		var thrust_force := 0.0
		var burn := 0.0
		if predicted_stage < rocket_stages.size():
			active = rocket_stages[predicted_stage]
			mass += RocketDesign.stage_total_dry_mass(active)
			mass += predicted_fuel
			for j in range(predicted_stage + 1, rocket_stages.size()):
				var upper: Dictionary = rocket_stages[j]
				mass += RocketDesign.stage_total_dry_mass(upper)
				mass += predicted_stage_fuel_remaining[j] if j < predicted_stage_fuel_remaining.size() else RocketDesign.stage_total_fuel_capacity(upper)
			total_flow = RocketDesign.stage_total_flow(active)
			if not infinite_weightless_fuel:
				burn = minf(predicted_fuel, total_flow * throttle * dt)
			var atmosphere := _atmosphere_at(position, predicted_velocity, step_time, position_components)
			var pressure_ratio := float(atmosphere.density) * float(atmosphere.gas_constant) * float(atmosphere.temperature) / 101325.0
			thrust_force = lerpf(RocketDesign.stage_total_thrust(active, true), RocketDesign.stage_total_thrust(active, false), clampf(pressure_ratio, 0.0, 1.0)) * throttle
		var mass_after := mass if infinite_weightless_fuel else maxf(1.0, mass - burn)
		var mass_mid := (mass + mass_after) * 0.5
		var thrust_delta_v := 0.0
		if infinite_weightless_fuel and throttle > 0.0 and thrust_force > 0.0:
			thrust_delta_v = thrust_force / maxf(1.0, mass) * dt
		elif burn > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
			thrust_delta_v = thrust_force / total_flow * log(mass / mass_after)
		var thrust_impulse := Vector2.UP.rotated(rotation_angle + gimbal_angle) * thrust_delta_v
		var initial_gravity_states := PlanetarySystem.gravity_body_states(step_time)
		var initial_gravity := PlanetarySystem.gravity_acceleration_from_precise_states(position_components, initial_gravity_states)
		var initial_aero := _aerodynamic_acceleration(position, predicted_velocity, mass_mid, step_time, position_components)
		var half_velocity := predicted_velocity + (initial_gravity + initial_aero) * (0.5 * dt) + thrust_impulse * 0.5
		var next_position_components := PackedFloat64Array([
			position_components[0] + half_velocity.x * dt,
			position_components[1] + half_velocity.y * dt
		])
		var next_position := Vector2(next_position_components[0], next_position_components[1])
		var final_gravity_states := PlanetarySystem.gravity_body_states(step_time + dt)
		var final_gravity := PlanetarySystem.gravity_acceleration_from_precise_states(next_position_components, final_gravity_states)
		var final_aero := _aerodynamic_acceleration(next_position, half_velocity, mass_mid, step_time + dt, next_position_components)
		predicted_velocity = half_velocity + (final_gravity + final_aero) * (0.5 * dt) + thrust_impulse * 0.5
		position_components = next_position_components
		position = next_position
		if not infinite_weightless_fuel:
			predicted_fuel = maxf(0.0, predicted_fuel - burn)
			predicted_stage_fuel_remaining[predicted_stage] = predicted_fuel
		if not infinite_weightless_fuel and predicted_fuel <= 0.0001 and predicted_stage < rocket_stages.size() - 1:
			predicted_stage_fuel_remaining[predicted_stage] = 0.0
			predicted_stage += 1
			predicted_fuel = predicted_stage_fuel_remaining[predicted_stage]
		predicted_path.append(position)
		var impacted := false
		for body in final_gravity_states.get("surface_bodies", []):
			var body_components := _body_position_components(body)
			var delta_x: float = position_components[0] - body_components[0]
			var delta_y: float = position_components[1] - body_components[1]
			if sqrt(delta_x * delta_x + delta_y * delta_y) <= float(body.get("radius", 0.0)):
				impacted = true
				break
		if impacted:
			break

func _draw_grid(center: Vector2) -> void:
	var spacing := 80.0
	for x in range(0, int(size.x / spacing) + 1):
		var px := x * spacing
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color(0.18, 0.28, 0.4, 0.12), 1.0)
	for y in range(0, int(size.y / spacing) + 1):
		var py := y * spacing
		draw_line(Vector2(0, py), Vector2(size.x, py), Color(0.18, 0.28, 0.4, 0.12), 1.0)

func _draw_orbit(rocket_screen: Vector2, factor: float) -> void:
	var body := _nearest_body_state(rocket_position)
	var relative_position: Vector2 = body.relative_position
	var relative_velocity: Vector2 = velocity - body.velocity
	var mu := G * float(body.mass)
	var radius := relative_position.length()
	var speed_squared := relative_velocity.length_squared()
	var specific_energy := speed_squared * 0.5 - mu / radius
	if specific_energy >= 0.0:
		return
	var semi_major := -mu / (2.0 * specific_energy)
	var angular_momentum := relative_position.cross(relative_velocity)
	var eccentricity_sq := maxf(0.0, 1.0 + 2.0 * specific_energy * angular_momentum * angular_momentum / (mu * mu))
	var eccentricity := sqrt(eccentricity_sq)
	var periapsis := semi_major * (1.0 - eccentricity)
	var apoapsis := semi_major * (1.0 + eccentricity)
	if periapsis <= float(body.radius):
		return
	var points := PackedVector2Array()
	var direction := atan2(relative_position.y, relative_position.x)
	for i in range(121):
		var theta := TAU * float(i) / 120.0
		var orbit_radius := semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(theta))
		var local := Vector2(cos(theta + direction), sin(theta + direction)) * orbit_radius
		points.append(rocket_screen + (local - relative_position) * camera_zoom * factor)
	draw_polyline(points, Color(0.2, 0.75, 1.0, 0.5), 1.5)

func _rocket_visual_design() -> Dictionary:
	return {
		"name": vehicle_name,
		"payload_mass": payload_mass,
		"payload_type": payload_type,
		"payload_visual": payload_visual,
		"stages": rocket_stages
	}

func _draw_rocket(p: Vector2, object_scale: float, vehicle_design: Dictionary = {}, vehicle_stage_index: int = -1, vehicle_throttle: float = -1.0, engine_enabled: bool = true) -> void:
	if crashed:
		RocketVisual.draw_wreck(self, p, rotation_angle, object_scale)
		return
	var design := vehicle_design if not vehicle_design.is_empty() else _rocket_visual_design()
	var visible_stage := stage_index if vehicle_stage_index < 0 else vehicle_stage_index
	var active_throttle := throttle if vehicle_throttle < 0.0 else vehicle_throttle
	RocketVisual.draw_vehicle(self, design, p, rotation_angle, object_scale, visible_stage, active_throttle, engine_enabled and (infinite_weightless_fuel or fuel > 0.0))


func _draw_hud() -> void:
	var ui_scale := clampf(minf(size.x / 1440.0, size.y / 900.0), 0.7, 1.0)
	var local_body := _nearest_body_state(rocket_position)
	var local_position: Vector2 = local_body.relative_position
	var local_velocity: Vector2 = velocity - local_body.velocity
	var altitude := maxf(0.0, float(local_body.distance) - float(local_body.radius))
	var orbital_speed := local_velocity.length()
	var local_orbit := FlightComputer.orbital_state(local_position, local_velocity, G * float(local_body.mass))
	var periapsis := maxf(0.0, float(local_orbit.get("periapsis", 0.0)) - float(local_body.radius)) if bool(local_orbit.get("valid", false)) else 0.0
	var apoapsis := maxf(0.0, float(local_orbit.get("apoapsis", INF)) - float(local_body.radius)) if bool(local_orbit.get("valid", false)) else INF
	var local_gravity := G * float(local_body.mass) / pow(maxf(1.0, float(local_body.distance)), 2.0)
	var current_thrust := _engine_thrust(altitude)
	var current_mass := _current_vehicle_mass()
	var active_fuel_capacity := float(_active_stage_data().get("fuel_capacity", 1.0))
	var thrust_to_weight := current_thrust / (current_mass * local_gravity)
	var remaining_delta_v := _remaining_ideal_delta_v(current_mass)
	var lines := [
		"BODY           %s" % str(local_body.name).to_upper(),
		"FLIGHT STATE   %s" % ("CRASHED" if crashed else "LANDED: " + landed_body_name if landed else "IN FLIGHT"),
		"ALTITUDE       %s" % _format_distance(altitude),
		"INERTIAL SPEED %s" % _format_speed(orbital_speed),
		"VERTICAL SPEED %s" % _format_speed(local_velocity.dot(local_position.normalized())),
		"FUEL           %s" % ("INFINITE • MASS RETAINED" if infinite_weightless_fuel else "%d%%" % roundi(100.0 * fuel / maxf(1.0, active_fuel_capacity))),
		"RCS PROP       %s" % ("NOT FITTED" if _remaining_rcs_propellant_capacity() <= 0.0 else "%d%%" % roundi(100.0 * rcs_propellant_remaining / maxf(1.0, _remaining_rcs_propellant_capacity()))),
		"XENON          %.1f kg" % resource_amount("xenon"),
		"SOLID PROP.    %.1f kg" % resource_amount("solid_propellant"),
		"ELECTRICITY    %.1f kWh" % (resource_amount("electricity") / 3600000.0),
		"THROTTLE       %s%%" % str(roundi(throttle * 100.0)),
		"THRUST / WEIGHT %.2f" % thrust_to_weight,
		"IDEAL ΔV EST.  %s" % ("UNLIMITED" if infinite_weightless_fuel else "%.2f km/s" % (remaining_delta_v / 1000.0)),
		"STAGE          %d / %d" % [stage_index + 1, rocket_stages.size()],
		"MACH NUMBER    %.2f" % mach_number,
		"DYNA PRESSURE  %.1f kPa" % (dynamic_pressure_pa / 1000.0),
		"MAX-Q          %.1f kPa" % (max_dynamic_pressure_pa / 1000.0),
		"HEAT FLUX      %.2f MW/m²" % heat_flux_mw,
		"SHIELD TEMP    %.0f K" % heat_shield_temperature,
		"PEAK HEATING   %.2f MW/m²" % peak_heat_flux_mw,
		"GUIDANCE       %s" % ("AUTO" if guidance_enabled else "MANUAL"),
		"PERIAPSIS      %s" % _format_distance(periapsis),
		"APOAPSIS       %s" % _format_distance(apoapsis),
		"MISSION TIME   %s" % _format_time(sim_time),
		"TIME WARP      x%s%s" % [str(snappedf(time_warp, 0.01)), "  •  CATCHING UP" if simulation_time_backlog > 1.0 else ""]
	]
	if autopilot_enabled:
		var target_state: Dictionary = _autopilot_target_state()
		if not target_state.is_empty():
			var target_range: float = _relative_position_to_body(target_state).length()
			var target_relative_speed: float = (velocity - target_state["velocity"]).length()
			lines.append("TARGET RANGE   %s" % _format_distance(target_range))
			lines.append("TARGET SPEED   %s" % _format_speed(target_relative_speed))
		lines.append("AUTOPILOT      %s" % autopilot_phase.replace("_", " "))
	var hud_height := 421.0 + maxf(0.0, float(lines.size() - 18) * 23.0)
	var box := Rect2(Vector2(18.0 * ui_scale, size.y - (hud_height + 20.0) * ui_scale), Vector2(310.0 * ui_scale, hud_height * ui_scale))
	draw_rect(box, Color(0.015, 0.035, 0.065, 0.86), true)
	draw_rect(box, Color(0.18, 0.42, 0.6, 0.7), false, 1.0)
	for i in range(lines.size()):
		draw_string(ThemeDB.fallback_font, Vector2(32.0 * ui_scale, box.position.y + 27.0 * ui_scale + i * 23.0 * ui_scale), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(13.0 * ui_scale)), Color(0.68, 0.82, 0.94))
	var status_width := minf(size.x - 420.0 * ui_scale, 760.0 * ui_scale)
	var status_rect := Rect2(Vector2((size.x - status_width) * 0.5, 18.0 * ui_scale), Vector2(status_width, 34.0 * ui_scale))
	draw_rect(status_rect, Color(0.015, 0.035, 0.065, 0.88), true)
	draw_rect(status_rect, Color(0.18, 0.42, 0.6, 0.75), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(status_rect.position.x + 8.0 * ui_scale, status_rect.position.y + 23.0 * ui_scale), status_message, HORIZONTAL_ALIGNMENT_CENTER, status_width - 16.0 * ui_scale, maxi(10, roundi(14.0 * ui_scale)), Color(0.35, 0.9, 0.78))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 280.0 * ui_scale, size.y - 28.0 * ui_scale), realism.to_upper() + "  /  " + world_scale.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(12.0 * ui_scale)), Color(0.48, 0.68, 0.84))

func _remaining_ideal_delta_v(current_mass: float) -> float:
	if infinite_weightless_fuel:
		return INF
	var total := 0.0
	var mass := current_mass
	for i in range(stage_index, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[i]
		var propellant := fuel if i == stage_index else RocketDesign.stage_total_fuel_capacity(stage)
		var dry := RocketDesign.stage_total_dry_mass(stage)
		var thrust := RocketDesign.stage_total_thrust(stage, true)
		var flow := RocketDesign.stage_total_flow(stage)
		var final_mass := mass - propellant
		if propellant > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > dry:
			total += thrust / flow * log(mass / final_mass)
		mass = final_mass - dry
	return total

func _apsis(apo: bool) -> float:
	var body := _nearest_body_state(rocket_position)
	var relative_position: Vector2 = body.relative_position
	var relative_velocity: Vector2 = velocity - body.velocity
	var orbit := FlightComputer.orbital_state(relative_position, relative_velocity, G * float(body.mass))
	if not bool(orbit.get("valid", false)):
		return INF if apo else 0.0
	var radius := float(orbit.get("apoapsis", INF) if apo else orbit.get("periapsis", 0.0))
	return maxf(0.0, radius - float(body.radius)) if is_finite(radius) else INF

func _visual_scale() -> float:
	match world_scale:
		"Balanced":
			return 0.55
		"Realistic distances":
			return 0.22
		_:
			return 1.0

func _format_distance(value: float) -> String:
	if is_inf(value):
		return "ESCAPE"
	if absf(value) >= 1000000.0:
		return "%.2f Mm" % (value / 1000000.0)
	if absf(value) < 100000.0:
		return "%.1f km" % (value / 1000.0)
	return "%.0f km" % (value / 1000.0)

func _format_speed(value: float) -> String:
	return "%.0f m/s" % value

func _format_time(value: float) -> String:
	var total := int(value)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]

func _saved_departure_plan() -> Dictionary:
	if autopilot_precomputed_transfer_plan.is_empty() or not autopilot_precomputed_transfer_plan.has("departure_time_seconds"):
		return {}
	var plan := autopilot_precomputed_transfer_plan
	var position: Vector2 = plan.get("planned_position", Vector2.ZERO)
	var velocity_value: Vector2 = plan.get("planned_velocity", Vector2.ZERO)
	var direction: Vector2 = plan.get("departure_direction", Vector2.ZERO)
	return {
		"target_id": int(plan.get("target_id", autopilot_planet_index)),
		"target_altitude": float(plan.get("target_altitude", autopilot_target_altitude)),
		"departure_time_seconds": float(plan.get("departure_time_seconds", -1.0)),
		"planned_at_time": float(plan.get("planned_at_time", -1.0)),
		"planned_position_x": position.x,
		"planned_position_y": position.y,
		"planned_velocity_x": velocity_value.x,
		"planned_velocity_y": velocity_value.y,
		"departure_direction_x": direction.x,
		"departure_direction_y": direction.y,
		"departure_delta_v": float(plan.get("departure_delta_v", 0.0)),
		"transfer_time": float(plan.get("transfer_time", 0.0))
	}

func _saved_manual_flight_plan() -> Dictionary:
	if manual_flight_plan.is_empty():
		return {}
	var plan := manual_flight_plan.duplicate(true)
	var departure_direction: Vector2 = plan.get("departure_direction", Vector2.ZERO)
	var burn_vector: Vector2 = plan.get("burn_vector", Vector2.ZERO)
	var planned_position: Vector2 = plan.get("planned_position", Vector2.ZERO)
	var planned_velocity: Vector2 = plan.get("planned_velocity", Vector2.ZERO)
	plan.erase("departure_direction")
	plan.erase("burn_vector")
	plan.erase("planned_position")
	plan.erase("planned_velocity")
	plan["departure_direction_x"] = departure_direction.x
	plan["departure_direction_y"] = departure_direction.y
	plan["burn_vector_x"] = burn_vector.x
	plan["burn_vector_y"] = burn_vector.y
	plan["planned_position_x"] = planned_position.x
	plan["planned_position_y"] = planned_position.y
	plan["planned_velocity_x"] = planned_velocity.x
	plan["planned_velocity_y"] = planned_velocity.y
	return plan

func _saved_resource_tanks() -> Array:
	var saved: Array = []
	for tank in resource_tanks:
		var physical_index := int(tank.get("stage_index", 0))
		if str(tank.get("module_id", vehicle_name)) == vehicle_name and physical_index < stage_index:
			continue
		var entry: Dictionary = tank.duplicate(true)
		if str(entry.get("module_id", vehicle_name)) == vehicle_name:
			entry["stage_index"] = physical_index - stage_index
		saved.append(entry)
	return saved

func get_save_data() -> Dictionary:
	var remaining_stages: Array = rocket_stages.slice(stage_index)
	var remaining_stage_fuel: Array[float] = stage_fuel_remaining.slice(stage_index)
	return {
		"sim_time": sim_time,
		"launch_time": launch_time,
		"position": [rocket_position.x, rocket_position.y],
		"position_precise": [rocket_position_precise[0], rocket_position_precise[1]],
		"velocity": [velocity.x, velocity.y],
		"rotation_angle": rotation_angle,
		"angular_velocity": angular_velocity,
		"fuel": fuel,
		"rcs_propellant_remaining": rcs_propellant_remaining,
		"docked_rcs_propellant": docked_rcs_propellant.duplicate(true),
		"resource_tanks": _saved_resource_tanks(),
		"stage_fuel_remaining": remaining_stage_fuel,
		"infinite_fuel_stage_remaining": infinite_fuel_stage_remaining,
		"stage_index": 0,
		"staging_plan": staging_plan.duplicate(true),
		"action_stage_index": action_stage_index,
		"staging_part_states": staging_part_states.duplicate(true),
		"discarded_stage_mass": discarded_stage_mass,
		"discarded_propellant_mass": discarded_propellant_mass,
		"gimbal_angle": gimbal_angle,
		"guidance_enabled": guidance_enabled,
		"infinite_weightless_fuel": infinite_weightless_fuel,
		"show_velocity_vector": show_vectors,
		"autopilot_enabled": autopilot_enabled,
		"autopilot_target_altitude": autopilot_target_altitude,
		"autopilot_target_mode": autopilot_target_mode,
		"autopilot_planet_index": autopilot_planet_index,
		"autopilot_burn_remaining": autopilot_burn_remaining,
		"autopilot_apsis_correction_armed": autopilot_apsis_correction_armed,
		"autopilot_apsis_correction_angle": autopilot_apsis_correction_angle,
		"autopilot_throttle": autopilot_throttle,
		"autopilot_transfer_start_time": autopilot_transfer_start_time,
		"autopilot_transfer_duration": autopilot_transfer_duration,
		"autopilot_departure_plan": _saved_departure_plan(),
		"autopilot_speed_priority": autopilot_speed_priority,
		"autopilot_safety_margin": autopilot_safety_margin,
		"autopilot_transfer_direction": autopilot_transfer_direction,
		"autopilot_arrival_burn_x": autopilot_arrival_burn_vector.x,
		"autopilot_arrival_burn_y": autopilot_arrival_burn_vector.y,
		"landed": landed,
		"crashed": crashed,
		"landed_body_name": landed_body_name,
		"landed_surface_normal_x": landed_surface_normal.x,
		"landed_surface_normal_y": landed_surface_normal.y,
		"launch_pad_normal_x": launch_pad_normal.x,
		"launch_pad_normal_y": launch_pad_normal.y,
		"launch_pad_reference_time": launch_pad_reference_time,
		"autopilot_burn_direction_x": autopilot_burn_direction.x,
		"autopilot_burn_direction_y": autopilot_burn_direction.y,
		"autopilot_route_nodes": autopilot_route_nodes.duplicate(true),
		"autopilot_route_node_index": autopilot_route_node_index,
		"manual_flight_plan": _saved_manual_flight_plan(),
		"manual_burn_tracking_enabled": manual_burn_tracking_enabled,
		"manual_burn_target_x": manual_burn_target_vector.x,
		"manual_burn_target_y": manual_burn_target_vector.y,
		"manual_burn_accumulated_x": manual_burn_accumulated_vector.x,
		"manual_burn_accumulated_y": manual_burn_accumulated_vector.y,
		"autopilot_complete": autopilot_complete,
		"autopilot_phase": autopilot_phase,
		"heat_shield_temperature": heat_shield_temperature,
		"peak_heat_flux_mw": peak_heat_flux_mw,
		"max_dynamic_pressure_pa": max_dynamic_pressure_pa,
		"throttle": throttle,
		"time_warp": time_warp,
		"paused": paused,
		"launch_design": launch_design.duplicate(true),
		"rocket_design": {"payload_mass": payload_mass, "payload_type": payload_type, "payload_visual": payload_visual.duplicate(true), "stages": remaining_stages, "staging_stage_count": staging_plan.size(), "preserve_part_uids": true},
		"vehicle_name": vehicle_name,
		"is_debris": is_debris,
		"passive_orbit_active": passive_orbit_active,
		"passive_orbit_forced": passive_orbit_forced,
		"passive_orbit_data": passive_orbit_data.duplicate(true),
		"telescope_active": telescope_active,
		"telescope_direction_angle": telescope_direction_angle
	}

func load_save_data(data: Dictionary) -> bool:
	var saved_design: Variant = data.get("rocket_design", null)
	if not saved_design is Dictionary:
		push_error("Save is missing a valid rocket design.")
		return false
	if not RocketDesign.validation_errors(saved_design).is_empty():
		push_error("Save contains an invalid rocket design.")
		return false
	var precise_position_data: Variant = data.get("position_precise", null)
	var position: Variant = data.get("position", null)
	if precise_position_data is Array:
		if precise_position_data.size() != 2 or not (precise_position_data[0] is float or precise_position_data[0] is int) or not (precise_position_data[1] is float or precise_position_data[1] is int):
			push_error("Save contains an invalid precise position.")
			return false
		if not is_finite(float(precise_position_data[0])) or not is_finite(float(precise_position_data[1])):
			push_error("Save contains a non-finite precise position.")
			return false
	elif position is Array:
		if position.size() != 2 or not (position[0] is float or position[0] is int) or not (position[1] is float or position[1] is int):
			push_error("Save contains an invalid position.")
			return false
		if not is_finite(float(position[0])) or not is_finite(float(position[1])):
			push_error("Save contains a non-finite position.")
			return false
	else:
		push_error("Save is missing a position.")
		return false
	var saved_velocity: Variant = data.get("velocity", null)
	if not saved_velocity is Array or saved_velocity.size() != 2:
		push_error("Save is missing a valid velocity.")
		return false
	if not (saved_velocity[0] is float or saved_velocity[0] is int) or not (saved_velocity[1] is float or saved_velocity[1] is int):
		push_error("Save contains an invalid velocity.")
		return false
	var velocity_x := float(saved_velocity[0])
	var velocity_y := float(saved_velocity[1])
	if not is_finite(velocity_x) or not is_finite(velocity_y):
		push_error("Save contains a non-finite velocity.")
		return false
	for key in ["sim_time", "rotation_angle", "angular_velocity", "fuel", "rcs_propellant_remaining", "gimbal_angle", "autopilot_burn_remaining", "heat_shield_temperature", "peak_heat_flux_mw", "max_dynamic_pressure_pa"]:
		var value: Variant = data.get(key, 0.0)
		if not (value is float or value is int) or not is_finite(float(value)):
			push_error("Save contains an invalid or non-finite %s value." % key)
			return false
	for key in ["discarded_stage_mass", "discarded_propellant_mass"]:
		var value: Variant = data.get(key, 0.0)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			push_error("Save contains an invalid %s value." % key)
			return false
	var stage_index_value: Variant = data.get("stage_index", 0)
	if not (stage_index_value is float or stage_index_value is int):
		push_error("Save contains an invalid stage index.")
		return false
	var stage_index: int = int(stage_index_value)
	var saved_stages: Array = saved_design.get("stages", [])
	if stage_index < 0 or stage_index >= saved_stages.size():
		push_error("Save stage index is outside the vehicle.")
		return false
	var saved_fuel: float = float(data.get("fuel", 0.0))
	var rcs_capacity := 0.0
	for saved_stage in saved_stages:
		rcs_capacity += RocketDesign.stage_rcs_propellant_capacity(saved_stage)
	var saved_rcs_propellant: float = float(data.get("rcs_propellant_remaining", rcs_capacity))
	if saved_rcs_propellant < 0.0 or saved_rcs_propellant > rcs_capacity:
		push_error("Save RCS propellant is outside the vehicle capacity.")
		return false
	var active_fuel_capacity: float = RocketDesign.stage_total_fuel_capacity(saved_stages[stage_index])
	if saved_fuel < 0.0 or saved_fuel > active_fuel_capacity:
		push_error("Save fuel amount is outside the active stage capacity.")
		return false
	var saved_stage_fuel: Variant = data.get("stage_fuel_remaining", null)
	var validated_stage_fuel: Array[float] = []
	if saved_stage_fuel is Array:
		if saved_stage_fuel.size() != saved_stages.size():
			push_error("Save stage fuel data does not match the vehicle stages.")
			return false
		for i in range(saved_stages.size()):
			var stage_fuel_value: Variant = saved_stage_fuel[i]
			var stage_capacity := RocketDesign.stage_total_fuel_capacity(saved_stages[i])
			if not (stage_fuel_value is float or stage_fuel_value is int) or not is_finite(float(stage_fuel_value)) or float(stage_fuel_value) < 0.0 or float(stage_fuel_value) > stage_capacity:
				push_error("Save contains an invalid stage fuel amount.")
				return false
			validated_stage_fuel.append(float(stage_fuel_value))
		if not is_equal_approx(validated_stage_fuel[stage_index], saved_fuel):
			push_error("Save active tank fuel does not match its stage fuel record.")
			return false
	else:
		for i in range(saved_stages.size()):
			if i < stage_index:
				validated_stage_fuel.append(0.0)
			elif i == stage_index:
				validated_stage_fuel.append(saved_fuel)
			else:
				validated_stage_fuel.append(RocketDesign.stage_total_fuel_capacity(saved_stages[i]))
	set_rocket_design(saved_design)
	var saved_launch_design: Variant = data.get("launch_design", saved_design)
	if saved_launch_design is Dictionary and RocketDesign.validation_errors(saved_launch_design).is_empty():
		launch_design = saved_launch_design.duplicate(true)
	saved_design["preserve_part_uids"] = true
	var saved_docked_rcs: Variant = data.get("docked_rcs_propellant", {})
	docked_rcs_propellant = saved_docked_rcs.duplicate(true) if saved_docked_rcs is Dictionary else {}
	var saved_resource_tanks: Variant = data.get("resource_tanks", null)
	if saved_resource_tanks is Array:
		resource_tanks = saved_resource_tanks.duplicate(true)
		_sync_legacy_fuel_from_tanks()
	var saved_staging_plan: Variant = data.get("staging_plan", null)
	if saved_staging_plan is Array and not saved_staging_plan.is_empty():
		staging_plan = saved_staging_plan.duplicate(true)
	action_stage_index = clampi(int(data.get("action_stage_index", 0)), 0, maxi(0, staging_plan.size() - 1))
	var saved_part_states: Variant = data.get("staging_part_states", {})
	staging_part_states = saved_part_states.duplicate(true) if saved_part_states is Dictionary else {}
	vehicle_name = str(data.get("vehicle_name", vehicle_name))
	is_debris = bool(data.get("is_debris", false))
	passive_orbit_active = bool(data.get("passive_orbit_active", false))
	passive_orbit_forced = bool(data.get("passive_orbit_forced", false))
	telescope_active = bool(data.get("telescope_active", false))
	telescope_direction_angle = wrapf(float(data.get("telescope_direction_angle", 0.0)), -PI, PI)
	var saved_passive_orbit: Variant = data.get("passive_orbit_data", {})
	passive_orbit_data = saved_passive_orbit.duplicate(true) if saved_passive_orbit is Dictionary else {}
	if passive_orbit_active and (str(passive_orbit_data.get("host_body_name", "")).is_empty() or not passive_orbit_data.get("elements", {}) is Dictionary):
		passive_orbit_active = false
		passive_orbit_data.clear()
	stage_index = clampi(int(data.get("stage_index", 0)), 0, maxi(0, rocket_stages.size() - 1))
	sim_time = float(data.get("sim_time", 0.0))
	launch_time = clampf(float(data.get("launch_time", sim_time)), 0.0, maxf(sim_time, 0.0))
	var p: Array = data.get("position", [0.0, -EARTH_RADIUS - 2.0])
	var precise_position: Array = data.get("position_precise", p)
	var v: Array = data.get("velocity", [EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0])
	_set_rocket_position_components(float(precise_position[0]), float(precise_position[1]))
	velocity = Vector2(float(v[0]), float(v[1]))
	rotation_angle = float(data.get("rotation_angle", 0.0))
	angular_velocity = float(data.get("angular_velocity", 0.0))
	fuel = float(data.get("fuel", _active_stage_data().get("fuel_capacity", 0.0)))
	rcs_propellant_remaining = clampf(float(data.get("rcs_propellant_remaining", _remaining_rcs_propellant_capacity())), 0.0, _remaining_rcs_propellant_capacity())
	stage_fuel_remaining = validated_stage_fuel
	infinite_fuel_stage_remaining = clampf(float(data.get("infinite_fuel_stage_remaining", fuel)), 0.0, float(_active_stage_data().get("fuel_capacity", 0.0)))
	discarded_stage_mass = float(data.get("discarded_stage_mass", 0.0))
	discarded_propellant_mass = float(data.get("discarded_propellant_mass", 0.0))
	gimbal_angle = float(data.get("gimbal_angle", 0.0))
	guidance_enabled = bool(data.get("guidance_enabled", false))
	infinite_weightless_fuel = bool(data.get("infinite_weightless_fuel", false))
	show_vectors = bool(data.get("show_velocity_vector", true))
	autopilot_enabled = bool(data.get("autopilot_enabled", false))
	autopilot_target_altitude = float(data.get("autopilot_target_altitude", 200000.0))
	autopilot_target_mode = str(data.get("autopilot_target_mode", "ORBIT"))
	autopilot_planet_index = int(data.get("autopilot_planet_index", -1))
	autopilot_burn_remaining = float(data.get("autopilot_burn_remaining", 0.0))
	autopilot_apsis_correction_armed = bool(data.get("autopilot_apsis_correction_armed", true))
	autopilot_apsis_correction_angle = float(data.get("autopilot_apsis_correction_angle", 0.0))
	autopilot_throttle = float(data.get("autopilot_throttle", 0.0))
	autopilot_transfer_start_time = float(data.get("autopilot_transfer_start_time", sim_time if str(data.get("autopilot_phase", "IDLE")) == "TRANSFER_COAST" else -1.0))
	autopilot_transfer_duration = float(data.get("autopilot_transfer_duration", 0.0))
	autopilot_precomputed_transfer_plan.clear()
	var saved_departure_plan: Variant = data.get("autopilot_departure_plan", {})
	if saved_departure_plan is Dictionary and not saved_departure_plan.is_empty():
		var departure_plan_valid := true
		for key in ["target_id", "target_altitude", "departure_time_seconds", "planned_at_time", "planned_position_x", "planned_position_y", "planned_velocity_x", "planned_velocity_y", "departure_direction_x", "departure_direction_y", "departure_delta_v", "transfer_time"]:
			var value: Variant = saved_departure_plan.get(key, null)
			if not (value is float or value is int) or not is_finite(float(value)):
				departure_plan_valid = false
				break
		if departure_plan_valid and str(data.get("autopilot_phase", "IDLE")) == "WAIT_WINDOW" and int(saved_departure_plan.target_id) == autopilot_planet_index and is_equal_approx(float(saved_departure_plan.target_altitude), autopilot_target_altitude) and float(saved_departure_plan.departure_time_seconds) >= sim_time - 2.0 and float(saved_departure_plan.departure_delta_v) >= 0.0 and float(saved_departure_plan.transfer_time) > 0.0:
			autopilot_precomputed_transfer_plan = {
				"valid": true,
				"target_id": int(saved_departure_plan.target_id),
				"target_altitude": float(saved_departure_plan.target_altitude),
				"departure_time_seconds": float(saved_departure_plan.departure_time_seconds),
				"planned_at_time": float(saved_departure_plan.planned_at_time),
				"planned_position": Vector2(float(saved_departure_plan.planned_position_x), float(saved_departure_plan.planned_position_y)),
				"planned_velocity": Vector2(float(saved_departure_plan.planned_velocity_x), float(saved_departure_plan.planned_velocity_y)),
				"departure_direction": Vector2(float(saved_departure_plan.departure_direction_x), float(saved_departure_plan.departure_direction_y)),
				"departure_delta_v": float(saved_departure_plan.departure_delta_v),
				"transfer_time": float(saved_departure_plan.transfer_time)
			}
	autopilot_speed_priority = clampf(float(data.get("autopilot_speed_priority", 0.35)), 0.0, 1.0)
	autopilot_safety_margin = clampf(float(data.get("autopilot_safety_margin", 0.10)), 0.0, 0.4)
	autopilot_transfer_direction = float(data.get("autopilot_transfer_direction", 1.0))
	autopilot_arrival_burn_vector = Vector2(float(data.get("autopilot_arrival_burn_x", 0.0)), float(data.get("autopilot_arrival_burn_y", 0.0)))
	manual_flight_plan.clear()
	var saved_manual_plan: Variant = data.get("manual_flight_plan", {})
	if saved_manual_plan is Dictionary and not saved_manual_plan.is_empty():
		var manual_plan_valid := str(saved_manual_plan.get("target_name", "")).length() > 0 and str(saved_manual_plan.get("phase", "")) in ["WAIT_DEPARTURE", "DEPARTURE_BURN", "TRANSFER_COAST", "ARRIVAL_BURN", "ARRIVAL_COAST", "ARRIVAL_CIRCULARISE", "LOCAL_BURN", "LOCAL_COAST", "LOCAL_CIRCULARISE", "COMPLETE", "FAILED"]
		for key in ["departure_time", "transfer_time", "departure_delta_v", "target_altitude", "burn_delta_v", "departure_direction_x", "departure_direction_y", "burn_vector_x", "burn_vector_y", "planned_position_x", "planned_position_y", "planned_velocity_x", "planned_velocity_y", "total_delta_v"]:
			var value: Variant = saved_manual_plan.get(key, 0.0)
			if not (value is float or value is int) or not is_finite(float(value)):
				manual_plan_valid = false
				break
		if manual_plan_valid:
			manual_flight_plan = saved_manual_plan.duplicate(true)
			manual_flight_plan["departure_direction"] = Vector2(float(saved_manual_plan.get("departure_direction_x", 0.0)), float(saved_manual_plan.get("departure_direction_y", 0.0)))
			manual_flight_plan["burn_vector"] = Vector2(float(saved_manual_plan.get("burn_vector_x", 0.0)), float(saved_manual_plan.get("burn_vector_y", 0.0)))
			manual_flight_plan["planned_position"] = Vector2(float(saved_manual_plan.get("planned_position_x", 0.0)), float(saved_manual_plan.get("planned_position_y", 0.0)))
			manual_flight_plan["planned_velocity"] = Vector2(float(saved_manual_plan.get("planned_velocity_x", 0.0)), float(saved_manual_plan.get("planned_velocity_y", 0.0)))
	manual_burn_tracking_enabled = bool(data.get("manual_burn_tracking_enabled", false)) and not manual_flight_plan.is_empty() and str(manual_flight_plan.get("phase", "")) in ["DEPARTURE_BURN", "ARRIVAL_BURN", "ARRIVAL_CIRCULARISE", "LOCAL_BURN", "LOCAL_CIRCULARISE"]
	manual_burn_target_vector = Vector2(float(data.get("manual_burn_target_x", 0.0)), float(data.get("manual_burn_target_y", 0.0)))
	manual_burn_accumulated_vector = Vector2(float(data.get("manual_burn_accumulated_x", 0.0)), float(data.get("manual_burn_accumulated_y", 0.0)))
	landed = bool(data.get("landed", false))
	crashed = bool(data.get("crashed", false))
	landed_body_name = str(data.get("landed_body_name", "Earth"))
	landed_surface_normal = Vector2(float(data.get("landed_surface_normal_x", 0.0)), float(data.get("landed_surface_normal_y", -1.0))).normalized()
	launch_pad_normal = Vector2(float(data.get("launch_pad_normal_x", 0.0)), float(data.get("launch_pad_normal_y", -1.0))).normalized()
	launch_pad_reference_time = float(data.get("launch_pad_reference_time", 0.0))
	autopilot_burn_direction = Vector2(float(data.get("autopilot_burn_direction_x", 0.0)), float(data.get("autopilot_burn_direction_y", 0.0)))
	autopilot_route_nodes.clear()
	var saved_route_nodes: Variant = data.get("autopilot_route_nodes", [])
	if saved_route_nodes is Array:
		for saved_node in saved_route_nodes:
			if saved_node is Dictionary:
				autopilot_route_nodes.append(saved_node.duplicate(true))
	autopilot_route_node_index = clampi(int(data.get("autopilot_route_node_index", 0)), 0, autopilot_route_nodes.size())
	autopilot_complete = bool(data.get("autopilot_complete", false))
	autopilot_phase = str(data.get("autopilot_phase", "IDLE"))
	heat_shield_temperature = float(data.get("heat_shield_temperature", 290.0))
	peak_heat_flux_mw = float(data.get("peak_heat_flux_mw", 0.0))
	max_dynamic_pressure_pa = float(data.get("max_dynamic_pressure_pa", 0.0))
	throttle = float(data.get("throttle", 0.0))
	thrust_key_down = false
	time_warp = float(data.get("time_warp", 1.0))
	paused = bool(data.get("paused", false))
	trail.clear()
	return true
