extends Control

const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")
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
var vehicle_name := "Vehicle 1"
var input_enabled := true
var docked_mass := 0.0
var docked_visuals: Array[Dictionary] = []

var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var infinite_weightless_fuel := false
var simulate_belt_collisions := false
var paused := false
var sim_time := 0.0
var launch_time := 0.0
var time_warp := 1.0
var simulation_time_backlog := 0.0
var ephemeris_cache_time := -INF
var ephemeris_cache: Dictionary = {}
var ephemeris_output_cache_time := -INF
var ephemeris_output_cache: Dictionary = {}
var rocket_position_precise := PackedFloat64Array([0.0, -EARTH_RADIUS - 2.0])
var _rocket_position_display := Vector2(0.0, -EARTH_RADIUS - 2.0)
var rocket_position: Vector2:
	get:
		return _rocket_position_display
	set(value):
		_rocket_position_display = value
		rocket_position_precise = PackedFloat64Array([value.x, value.y])
var velocity := Vector2(EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0)
var rotation_angle := 0.0
var fuel := 300000.0
var infinite_fuel_stage_remaining := 300000.0
var stage_index := 0
var discarded_stage_mass := 0.0
var discarded_propellant_mass := 0.0
var throttle := 0.0
var gimbal_angle := 0.0
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
var discovered_body_names: Dictionary = {"Earth": true, "Moon": true}
var visited_body_names: Dictionary = {"Earth": true}
var passive_orbit_active := false
var passive_orbit_forced := false
var passive_orbit_data: Dictionary = {}
var fleet_visuals: Array[Dictionary] = []

func _set_rocket_position_components(position_x: float, position_y: float) -> void:
	rocket_position_precise = PackedFloat64Array([position_x, position_y])
	_rocket_position_display = Vector2(position_x, position_y)

func set_rocket_design(design: Dictionary) -> void:
	rocket_stages = (design.get("stages", []) as Array).duplicate(true)
	if rocket_stages.is_empty():
		rocket_stages = RocketDesign.create_default()["stages"].duplicate(true)
	payload_mass = float(design.get("payload_mass", 500.0))
	payload_type = str(design.get("payload_type", "probe"))
	var visual_data: Variant = design.get("payload_visual", {})
	payload_visual = visual_data.duplicate(true) if visual_data is Dictionary else {}
	stage_index = 0
	stage_fuel_remaining.clear()
	for stage in rocket_stages:
		stage_fuel_remaining.append(RocketDesign.stage_total_fuel_capacity(stage))
	fuel = stage_fuel_remaining[0]
	infinite_fuel_stage_remaining = fuel

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
		mass += stage_fuel_remaining[i] if i < stage_fuel_remaining.size() else RocketDesign.stage_total_fuel_capacity(stage)
	return mass

func total_propellant_remaining() -> float:
	var total := 0.0
	for i in range(stage_index, rocket_stages.size()):
		total += fuel if i == stage_index else (stage_fuel_remaining[i] if i < stage_fuel_remaining.size() else RocketDesign.stage_total_fuel_capacity(rocket_stages[i]))
	return total

func total_propellant_capacity() -> float:
	var total := 0.0
	for i in range(stage_index, rocket_stages.size()):
		total += RocketDesign.stage_total_fuel_capacity(rocket_stages[i])
	return total

func remove_propellant(amount: float) -> float:
	var remaining := maxf(0.0, amount)
	var requested := remaining
	for i in range(stage_index, rocket_stages.size()):
		var available := fuel if i == stage_index else stage_fuel_remaining[i]
		var taken := minf(available, remaining)
		if i == stage_index:
			fuel = maxf(0.0, fuel - taken)
			stage_fuel_remaining[i] = fuel
		else:
			stage_fuel_remaining[i] = maxf(0.0, stage_fuel_remaining[i] - taken)
		remaining -= taken
		if remaining <= 0.000001:
			break
	return requested - remaining

func add_propellant(amount: float) -> float:
	var remaining := maxf(0.0, amount)
	var requested := remaining
	for i in range(stage_index, rocket_stages.size()):
		var capacity := RocketDesign.stage_total_fuel_capacity(rocket_stages[i])
		var current := fuel if i == stage_index else stage_fuel_remaining[i]
		var added := minf(maxf(0.0, capacity - current), remaining)
		if i == stage_index:
			fuel += added
			stage_fuel_remaining[i] = fuel
		else:
			stage_fuel_remaining[i] += added
		remaining -= added
		if remaining <= 0.000001:
			break
	return requested - remaining

func _current_vehicle_mass(fuel_amount: float = -1.0) -> float:
	var active := _active_stage_data()
	var mass := float(active.get("dry_mass", 0.0)) + _remaining_stack_mass()
	mass += fuel if fuel_amount < 0.0 else fuel_amount
	mass += docked_mass
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
	if not paused and not crashed:
		var current_body := _nearest_body_state(rocket_position)
		var altitude: float = maxf(0.0, float(current_body.distance) - float(current_body.radius))
		var atmosphere_height: float = PlanetarySystem.planetary_atmosphere_height(str(current_body.get("name", "Earth")))
		var near_atmosphere: bool = float(current_body.distance) < float(current_body.soi) and altitude < atmosphere_height
		var effective_warp: float = minf(time_warp, 100.0) if near_atmosphere else time_warp
		simulation_time_backlog += effective_warp * delta
		var iterations := 0
		var physics_budget_start_usec: int = Time.get_ticks_usec()
		while simulation_time_backlog > 0.000001 and iterations < MAX_PHYSICS_STEPS_PER_FRAME and Time.get_ticks_usec() - physics_budget_start_usec < MAX_PHYSICS_BUDGET_USEC:
			var step_delta: float = minf(simulation_time_backlog, _adaptive_step_size())
			if step_delta <= 0.000001:
				break
			_physics_step(step_delta)
			simulation_time_backlog = maxf(0.0, simulation_time_backlog - step_delta)
			iterations += 1
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

func _physics_step(dt: float) -> void:
	var start_time := sim_time
	var end_time := sim_time + dt
	if landed:
		if thrust_key_down and (infinite_weightless_fuel or fuel > 0.0):
			var surface_state := _surface_body_state(landed_body_name)
			var normal := landed_surface_normal.normalized()
			rotation_angle = normal.angle() - Vector2.UP.angle()
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
	if crashed:
		sim_time = end_time
		throttle = 0.0
		return
	var initial_rocket_position_components: PackedFloat64Array = rocket_position_precise.duplicate()
	var local_body := _nearest_body_state(rocket_position)
	var altitude := maxf(0.0, float(local_body.get("distance", EARTH_RADIUS)) - float(local_body.get("radius", EARTH_RADIUS)))
	if guidance_enabled:
		_update_guidance(dt)
	if autopilot_enabled and autopilot_phase in ["COAST", "COAST_TO_TARGET", "WAIT_WINDOW", "ALIGN_DEPARTURE", "TRANSFER_COAST", "ARRIVAL_APPROACH", "ARRIVAL_PENDING", "ROUTE_COAST", "COMPLETE", "FAILED"]:
		thrust_key_down = false
	var active := _active_stage_data()
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	var propellant_available := infinite_weightless_fuel or fuel > 0.0
	throttle = autopilot_throttle if autopilot_enabled and autopilot_phase == "LANDING_DESCENT" and propellant_available else (1.0 if thrust_key_down and propellant_available else 0.0)
	var fuel_used := minf(infinite_fuel_stage_remaining, total_flow * throttle * dt) if infinite_weightless_fuel and total_flow > 0.0 else (minf(fuel, total_flow * throttle * dt) if total_flow > 0.0 else 0.0)
	var effective_fuel := infinite_fuel_stage_remaining if infinite_weightless_fuel else -1.0
	var mass_before := maxf(1.0, _current_vehicle_mass(effective_fuel))
	var mass_after := maxf(1.0, mass_before - fuel_used)
	var mass_mid := (mass_before + mass_after) * 0.5
	var initial_atmosphere: Dictionary = {}
	if realism != "Arcade" or throttle > 0.0:
		initial_atmosphere = _atmosphere_at(rocket_position, velocity, start_time, rocket_position_precise)
	var thrust_force: float = _engine_thrust(maxf(0.0, altitude), initial_atmosphere) * throttle if throttle > 0.0 else 0.0
	var thrust_delta_v := 0.0
	if fuel_used > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
		thrust_delta_v = thrust_force / total_flow * log(mass_before / mass_after)
	elif infinite_weightless_fuel and throttle > 0.0 and thrust_force > 0.0:
		thrust_delta_v = thrust_force / mass_before * dt
	if infinite_weightless_fuel:
		infinite_fuel_stage_remaining = maxf(0.0, infinite_fuel_stage_remaining - fuel_used)
	var thrust_direction := Vector2.UP.rotated(rotation_angle + gimbal_angle)
	var thrust_impulse := thrust_direction * thrust_delta_v
	if manual_burn_tracking_enabled and not autopilot_enabled and thrust_delta_v > 0.0:
		manual_burn_accumulated_vector += thrust_impulse
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
	if infinite_weightless_fuel and infinite_fuel_stage_remaining <= 0.0001 and stage_index < rocket_stages.size() - 1:
		_separate_stage()
	elif not infinite_weightless_fuel and fuel <= 0.0001 and stage_index < rocket_stages.size() - 1:
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
	discarded_stage_mass += float(_active_stage_data().get("dry_mass", 0.0))
	discarded_propellant_mass += fuel
	if stage_index < stage_fuel_remaining.size():
		stage_fuel_remaining[stage_index] = 0.0
	velocity += Vector2.UP.rotated(rotation_angle) * 2.0
	stage_index += 1
	fuel = stage_fuel_remaining[stage_index]
	infinite_fuel_stage_remaining = fuel
	thrust_key_down = false

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
	var pitch_reference_altitude := maxf(maxf(5000.0, float(guidance_body.radius) * 0.01), atmosphere_height * 0.6)
	var pitch_above_horizon := lerpf(90.0, 5.0, clampf(altitude / pitch_reference_altitude, 0.0, 1.0))
	if autopilot_enabled and autopilot_phase == "ASCENT" and not destination_is_local and maximum_stable_altitude <= minimum_safe_altitude:
		_fail_autopilot("NO SAFE PARKING ORBIT EXISTS AROUND %s" % guidance_body_name.to_upper())
	if autopilot_enabled:
		gimbal_angle = 0.0
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
					var ascent_speed_fraction: float = clampf(ascent_speed_gain / maxf(1.0, target_orbit_speed), 0.0, 1.0)
					var altitude_pitch: float = lerpf(88.0, 4.0, ascent_altitude_fraction)
					var speed_pitch: float = lerpf(88.0, 4.0, ascent_speed_fraction)
					pitch_above_horizon = minf(altitude_pitch, speed_pitch)
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
						var circular_burn_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
						rotation_angle = lerp_angle(rotation_angle, circular_burn_rotation, clampf(dt * 1.5, 0.0, 1.0))
						thrust_key_down = propellant_available and absf(angle_difference(rotation_angle, circular_burn_rotation)) < deg_to_rad(1.0)
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
				var manoeuvre_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, manoeuvre_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE and absf(angle_difference(rotation_angle, manoeuvre_rotation)) < deg_to_rad(1.0)
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
				var route_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, route_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE and absf(angle_difference(rotation_angle, route_rotation)) < deg_to_rad(1.0)
				if not propellant_available and stage_index >= rocket_stages.size() - 1:
					_fail_autopilot("OUT OF PROPELLANT DURING ROUTE BURN")
			"TRANSFER_BURN":
				status_message = "AUTOPILOT  •  INTERPLANETARY INJECTION  %.0f M/S" % autopilot_burn_remaining
				var injection_direction := autopilot_burn_direction if autopilot_burn_direction.length_squared() > 0.5 else tangent * autopilot_transfer_direction
				var injection_rotation := injection_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, injection_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE and absf(angle_difference(rotation_angle, injection_rotation)) < deg_to_rad(1.0)
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
				var capture_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, capture_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = propellant_available and autopilot_burn_remaining > FlightComputer.BURN_COMPLETION_TOLERANCE and absf(angle_difference(rotation_angle, capture_rotation)) < deg_to_rad(1.0)
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
		elif autopilot_phase in ["TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN"]:
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
		var autopilot_target_rotation := autopilot_direction.angle() - Vector2.UP.angle()
		rotation_angle = lerp_angle(rotation_angle, autopilot_target_rotation, clampf(dt * 1.2, 0.0, 1.0))
		return
	elif guidance_velocity.length() > 1500.0:
		pitch_above_horizon = minf(pitch_above_horizon, 12.0)
	var manual_target_direction := radial * sin(deg_to_rad(pitch_above_horizon)) + tangent * cos(deg_to_rad(pitch_above_horizon))
	var manual_target_rotation := manual_target_direction.angle() - Vector2.UP.angle()
	rotation_angle = lerp_angle(rotation_angle, manual_target_rotation, clampf(dt * 0.08, 0.0, 1.0))

func _input(event: InputEvent) -> void:
	if not input_enabled or not event is InputEventKey or not event.pressed or event.echo:
		return
	var ignite_pressed: bool = event.is_action_pressed("engine_toggle") or event.keycode == KEY_W or event.physical_keycode == KEY_W
	var cutoff_pressed: bool = event.is_action_pressed("throttle_cutoff") or event.keycode == KEY_S or event.physical_keycode == KEY_S
	if ignite_pressed:
		if autopilot_enabled:
			autopilot_enabled = false
			guidance_enabled = false
		if landed and (infinite_weightless_fuel or fuel > 0.0):
			thrust_key_down = true
		else:
			thrust_key_down = not thrust_key_down
	elif cutoff_pressed:
		if autopilot_enabled:
			autopilot_enabled = false
			guidance_enabled = false
		thrust_key_down = false
		throttle_cutoff_key_down = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		thrust_key_down = false
		throttle_cutoff_key_down = false

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("rotate_left"):
			rotation_angle -= 0.12
		elif event.is_action_pressed("rotate_right"):
			rotation_angle += 0.12
		elif event.is_action_pressed("pause_game"):
			paused = not paused
		elif event.is_action_pressed("stage_separation"):
			_separate_stage()
		elif event.is_action_pressed("guidance_toggle"):
			guidance_enabled = not guidance_enabled
			if not guidance_enabled:
				autopilot_enabled = false
				thrust_key_down = false
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
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if show_solar_system:
				solar_map_zoom = minf(8.0, solar_map_zoom * 1.2)
			else:
				camera_zoom = minf(0.02, camera_zoom * 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if show_solar_system:
				solar_map_zoom = maxf(0.25, solar_map_zoom / 1.2)
			else:
				camera_zoom = maxf(0.00000000002, camera_zoom / 1.2)

func _draw_atmosphere(center: Vector2, planet_radius: float, atmosphere_height: float, atmosphere_color: Color) -> void:
	if atmosphere_height <= 0.0:
		return
	var physical_thickness := atmosphere_height * camera_zoom * _visual_scale()
	var visible_thickness := clampf(physical_thickness, 3.0, 34.0)
	var rings := 5
	for ring in range(rings):
		var fraction := float(ring + 1) / float(rings)
		var ring_radius := planet_radius + visible_thickness * fraction
		var alpha := 0.035 + 0.13 * (1.0 - fraction)
		draw_arc(center, ring_radius, 0.0, TAU, 96, Color(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, alpha), maxf(1.0, visible_thickness / float(rings) * 1.5))
	draw_arc(center, planet_radius + visible_thickness, 0.0, TAU, 96, Color(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, 0.5), 1.0)

func _draw_planet_rings(center: Vector2, planet_radius: float, visual_data: Dictionary, opacity_scale: float = 1.0) -> void:
	if not bool(visual_data.get("has_rings", false)):
		return
	var inner_radius := planet_radius * float(visual_data.get("ring_inner_ratio", 1.2))
	var outer_radius := planet_radius * float(visual_data.get("ring_outer_ratio", 2.0))
	var ring_color: Color = visual_data.get("ring_color", Color.WHITE)
	var alpha := float(visual_data.get("ring_opacity", 0.5)) * opacity_scale
	var line_width := maxf(1.0, (outer_radius - inner_radius) * 0.16)
	for ring_radius in [inner_radius, (inner_radius + outer_radius) * 0.5, outer_radius]:
		draw_arc(center, ring_radius, 0.0, TAU, 64, Color(ring_color.r, ring_color.g, ring_color.b, alpha), line_width)

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
		var satellite_state := _surface_body_state("%s %s" % [host_name, str(satellite.get("name", "Moon"))])
		if satellite_state.is_empty():
			continue
		var host_position: Vector2 = host_state.get("position", Vector2.ZERO)
		var satellite_position: Vector2 = satellite_state.get("position", Vector2.ZERO)
		var world_offset := satellite_position - host_position
		var direction := Vector2(world_offset.x, -world_offset.y).normalized()
		var orbit_ratio := maxf(1.0, float(satellite.get("semi_major_axis_m", 0.0)) / float(host_planet.get("radius", 1.0)))
		var orbit_radius_px := host_radius_px + 4.0 + log(orbit_ratio) * maxf(1.5, host_radius_px * 0.08)
		var satellite_color := PlanetarySystem.color_from_rgb(satellite.get("color_rgb", []), Color(0.75, 0.78, 0.82))
		draw_arc(host_screen, orbit_radius_px, 0.0, TAU, 48, Color(satellite_color.r, satellite_color.g, satellite_color.b, 0.3), 1.0)
		var satellite_screen := host_screen + direction * orbit_radius_px
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
		_draw_docked_visuals(view_center, clampf(camera_zoom * world_scale_factor / 0.000045, 0.12, 5.0))
		_draw_hud()
		return
	if camera_zoom <= 0.0000000002:
		_draw_full_system_zoom(view_center)
		_draw_docked_visuals(view_center, clampf(camera_zoom * world_scale_factor / 0.000045, 0.12, 5.0))
		_draw_offscreen_body_indicators(view_center, altitude_visual_scale)
		_draw_hud()
		return

	if show_grid:
		_draw_grid(view_center)

	var earth_visual := PlanetarySystem.planet_visual_data("Earth")
	_draw_atmosphere(earth_screen, radius_px, float(earth_visual.get("atmosphere_height", 100000.0)), earth_visual.get("atmosphere_color", Color(0.22, 0.62, 1.0)))
	draw_circle(earth_screen, radius_px + 7, Color(0.15, 0.35, 0.58, 0.12))
	var earth_color: Color = earth_visual.get("surface_color", Color(0.10, 0.28, 0.53))
	draw_circle(earth_screen, radius_px, earth_color)
	draw_arc(earth_screen, radius_px, 0, TAU, 120, earth_color.lightened(0.25), 2.0)
	draw_arc(earth_screen, radius_px * 0.76, -0.4, 2.4, 48, Color(0.18, 0.43, 0.48, 0.45), 2.0)
	draw_arc(earth_screen, radius_px * 0.53, 2.2, 5.4, 48, Color(0.18, 0.43, 0.48, 0.35), 2.0)
	var object_scale := clampf(camera_zoom * world_scale_factor / 0.000045, 0.12, 5.0)
	var pad_width := clampf(34.0 * object_scale, 9.0, 85.0)
	var pad_height := clampf(7.0 * object_scale, 3.0, 18.0)
	var pad_y := earth_screen.y - radius_px - 2.0 * object_scale
	draw_line(Vector2(earth_screen.x - pad_width, pad_y), Vector2(earth_screen.x + pad_width, pad_y), Color(0.65, 0.72, 0.82), 3.0 * object_scale)
	draw_line(Vector2(earth_screen.x - 20.0 * object_scale, pad_y), Vector2(earth_screen.x - 20.0 * object_scale, pad_y + pad_height), Color(0.65, 0.72, 0.82), 2.0 * object_scale)
	draw_line(Vector2(earth_screen.x + 20.0 * object_scale, pad_y), Vector2(earth_screen.x + 20.0 * object_scale, pad_y + pad_height), Color(0.65, 0.72, 0.82), 2.0 * object_scale)
	draw_string(ThemeDB.fallback_font, earth_screen + Vector2(radius_px + 12, 4), "EARTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.78, 1.0))

	var moon_world := PlanetarySystem.moon_position(sim_time)
	var moon_screen := rocket_screen + (moon_world - rocket_position) * camera_zoom * world_scale_factor
	var moon_radius_px := maxf(2.0, PlanetarySystem.MOON_RADIUS * camera_zoom * world_scale_factor)
	if moon_screen.x > -moon_radius_px and moon_screen.x < size.x + moon_radius_px and moon_screen.y > -moon_radius_px and moon_screen.y < size.y + moon_radius_px:
		var moon_color: Color = PlanetarySystem.planet_visual_data("Moon").get("color", Color(0.72, 0.74, 0.78))
		draw_circle(moon_screen, moon_radius_px + 3.0, Color(0.55, 0.58, 0.66, 0.16))
		draw_circle(moon_screen, moon_radius_px, moon_color.darkened(0.35))
		draw_arc(moon_screen, moon_radius_px, 0.0, TAU, 64, moon_color, 1.0)
		draw_string(ThemeDB.fallback_font, moon_screen + Vector2(moon_radius_px + 8.0, 4.0), "MOON", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.84))

	var destination := _nearest_body_state(rocket_position)
	if str(destination.name) not in ["Earth", "Moon"] and float(destination.distance) < float(destination.soi):
		var destination_screen: Vector2 = rocket_screen + (Vector2(destination.position) - rocket_position) * altitude_visual_scale
		var destination_radius := clampf(float(destination.radius) * altitude_visual_scale, 3.0, 72.0)
		if destination_screen.x > -destination_radius - 30.0 and destination_screen.x < size.x + destination_radius + 30.0 and destination_screen.y > -destination_radius - 30.0 and destination_screen.y < size.y + destination_radius + 30.0:
			var destination_visual := PlanetarySystem.planet_visual_data(str(destination.name))
			var destination_color: Color = destination_visual.get("color", Color(0.82, 0.38, 0.25))
			var atmosphere_visual: Dictionary = _planet_atmosphere_visual(str(destination.name))
			_draw_atmosphere(destination_screen, destination_radius, float(atmosphere_visual.get("height", 0.0)), atmosphere_visual.get("color", Color.TRANSPARENT))
			draw_circle(destination_screen, destination_radius + 5.0, Color(0.45, 0.7, 1.0, 0.12))
			_draw_planet_rings(destination_screen, destination_radius, destination_visual)
			draw_circle(destination_screen, destination_radius, destination_color)
			draw_arc(destination_screen, destination_radius, 0.0, TAU, 80, Color(0.9, 0.92, 1.0, 0.8), 1.0)
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
		var fleet_screen := rocket_screen + (fleet_position - rocket_position) * altitude_visual_scale
		if fleet_screen.x < -40.0 or fleet_screen.x > size.x + 40.0 or fleet_screen.y < -40.0 or fleet_screen.y > size.y + 40.0:
			continue
		var fleet_design: Dictionary = fleet_entry.get("design", {})
		var fleet_stage := int(fleet_entry.get("stage_index", 0))
		RocketVisual.draw_vehicle(self, fleet_design, fleet_screen, float(fleet_entry.get("rotation", 0.0)), object_scale * 0.72, fleet_stage, 0.0, false)
	_draw_rocket(rocket_screen, object_scale)
	_draw_docked_visuals(rocket_screen, object_scale)
	if show_vectors:
		var velocity_end := rocket_screen + velocity.normalized() * 65.0
		draw_line(rocket_screen, velocity_end, Color(0.25, 0.9, 0.55), 2.0)
		draw_string(ThemeDB.fallback_font, velocity_end + Vector2(6, 0), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.9, 0.55))

	_draw_hud()


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
		var orbit_radius := float(planet.a) * PlanetarySystem.ASTRONOMICAL_UNIT * scale
		if orbit_radius > 2.0 and orbit_radius < maxf(size.x, size.y) * 1.5:
			draw_arc(sun_screen, orbit_radius, 0.0, TAU, 160, Color(0.28, 0.43, 0.58, 0.28), 1.0)
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
		draw_circle(screen_position, body_radius, body_color)
		if body_radius >= 2.0 or body_name in ["Sun", "Earth", "Moon"]:
			var label_position := screen_position + Vector2(body_radius + 4.0, 3.0)
			draw_string(ThemeDB.fallback_font, label_position, body_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, body_color.lightened(0.2))
	var earth_screen := view_center - rocket_position * scale
	var earth_radius := clampf(PlanetarySystem.EARTH_RADIUS * scale, 1.5, 9.0)
	var earth_color: Color = PlanetarySystem.planet_visual_data("Earth").get("color", Color(0.25, 0.55, 0.82))
	draw_circle(earth_screen, earth_radius, earth_color)
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
		var orbit_radius: float = float(planet.a) * PlanetarySystem.ASTRONOMICAL_UNIT
		draw_arc(center, orbit_radius * map_scale, 0.0, TAU, 180, Color(0.28, 0.43, 0.58, 0.34), 1.0)
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
		_draw_planet_rings(planet_screen, planet_radius, planet_visual, 0.85)
		draw_circle(planet_screen, planet_radius, planet_color)
		_draw_solar_label(planet_name.to_upper(), planet_screen, 10, Color(0.82, 0.88, 0.96), occupied)
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
			draw_arc(host_screen, orbit_radius_px, 0.0, TAU, 32, Color(satellite_color.r, satellite_color.g, satellite_color.b, 0.22), 1.0)
			var satellite_screen := host_screen + relative_direction * orbit_radius_px
			draw_circle(satellite_screen, maxf(1.3, host_radius * 0.45), satellite_color)
			if solar_map_zoom >= 2.0:
				_draw_solar_label(str(satellite.get("name", "MOON")).to_upper(), satellite_screen, 8, satellite_color, occupied)
	var earth_position: Vector2 = Vector2(positions.get("Earth", Vector2.ZERO))
	var earth_screen: Vector2 = center + Vector2(earth_position.x, -earth_position.y) * map_scale
	var moon_position: Vector2 = Vector2(positions.get("Moon", earth_position))
	var moon_offset := Vector2(moon_position.x - earth_position.x, -(moon_position.y - earth_position.y)).normalized()
	var earth_marker_radius := clampf(pow(PlanetarySystem.EARTH_RADIUS / EARTH_RADIUS, 0.45) * 3.0, 2.0, 8.0)
	var moon_orbit_display_radius := earth_marker_radius + 2.0 + log(PlanetarySystem.MOON_ORBIT_RADIUS / PlanetarySystem.EARTH_RADIUS) * 1.6
	draw_arc(earth_screen, moon_orbit_display_radius, 0.0, TAU, 32, Color(0.65, 0.69, 0.77, 0.22), 1.0)
	var moon_screen := earth_screen + moon_offset * moon_orbit_display_radius
	draw_circle(moon_screen, 2.5, PlanetarySystem.planet_visual_data("Moon").get("color", Color(0.72, 0.74, 0.78)))
	_draw_solar_label("MOON", moon_screen, 9, Color(0.78, 0.82, 0.9), occupied)
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

func get_save_data() -> Dictionary:
	return {
		"sim_time": sim_time,
		"launch_time": launch_time,
		"position": [rocket_position.x, rocket_position.y],
		"position_precise": [rocket_position_precise[0], rocket_position_precise[1]],
		"velocity": [velocity.x, velocity.y],
		"rotation_angle": rotation_angle,
		"fuel": fuel,
		"stage_fuel_remaining": stage_fuel_remaining.duplicate(),
		"infinite_fuel_stage_remaining": infinite_fuel_stage_remaining,
		"stage_index": stage_index,
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
		"rocket_design": {"payload_mass": payload_mass, "payload_type": payload_type, "payload_visual": payload_visual.duplicate(true), "stages": rocket_stages.duplicate(true)},
		"vehicle_name": vehicle_name,
		"passive_orbit_active": passive_orbit_active,
		"passive_orbit_forced": passive_orbit_forced,
		"passive_orbit_data": passive_orbit_data.duplicate(true)
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
	for key in ["sim_time", "rotation_angle", "fuel", "gimbal_angle", "autopilot_burn_remaining", "heat_shield_temperature", "peak_heat_flux_mw", "max_dynamic_pressure_pa"]:
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
	vehicle_name = str(data.get("vehicle_name", vehicle_name))
	passive_orbit_active = bool(data.get("passive_orbit_active", false))
	passive_orbit_forced = bool(data.get("passive_orbit_forced", false))
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
	fuel = float(data.get("fuel", _active_stage_data().get("fuel_capacity", 0.0)))
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
