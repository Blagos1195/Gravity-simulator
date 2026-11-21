extends Control

const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const G := PlanetarySystem.G
const EARTH_MASS := PlanetarySystem.EARTH_MASS
const EARTH_RADIUS := PlanetarySystem.EARTH_RADIUS
const DRAG_AREA := 0.45
const LIFT_AREA := 1.8
const EARTH_ROTATION_RATE := 7.2921159e-5
const MAX_PHYSICS_BUDGET_USEC := 6000
const MAX_PHYSICS_STEPS_PER_FRAME := 4000

var rocket_stages: Array = []
var payload_mass := 500.0

var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var paused := false
var sim_time := 0.0
var time_warp := 1.0
var simulation_time_backlog := 0.0
var ephemeris_cache_time := -INF
var ephemeris_cache: Dictionary = {}
var ephemeris_output_cache_time := -INF
var ephemeris_output_cache: Dictionary = {}
var rocket_position := Vector2(0, -EARTH_RADIUS - 2.0)
var velocity := Vector2(EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0)
var rotation_angle := 0.0
var fuel := 300000.0
var stage_index := 0
var discarded_stage_mass := 0.0
var throttle := 0.0
var gimbal_angle := 0.0
var guidance_enabled := false
var autopilot_enabled := false
var autopilot_target_altitude := 200000.0
var autopilot_target_mode := "ORBIT"
var autopilot_planet_index := -1
var autopilot_burn_remaining := 0.0
var autopilot_throttle := 0.0
var autopilot_transfer_start_time := -1.0
var autopilot_transfer_duration := 0.0
var autopilot_transfer_corrections := 0
var autopilot_speed_priority := 0.35
var autopilot_safety_margin := 0.10
var autopilot_transfer_direction := 1.0
var autopilot_arrival_burn_vector := Vector2.ZERO
var autopilot_burn_direction := Vector2.ZERO
var autopilot_route_nodes: Array[Dictionary] = []
var autopilot_route_node_index := 0
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

func set_rocket_design(design: Dictionary) -> void:
	rocket_stages = (design.get("stages", []) as Array).duplicate(true)
	if rocket_stages.size() < 2:
		rocket_stages = RocketDesign.create_default()["stages"].duplicate(true)
	payload_mass = float(design.get("payload_mass", 500.0))
	stage_index = 0
	fuel = float(rocket_stages[0].get("fuel_capacity", 0.0))

func _active_stage_data() -> Dictionary:
	return rocket_stages[clampi(stage_index, 0, rocket_stages.size() - 1)]

func _remaining_stack_mass() -> float:
	var mass := payload_mass
	for i in range(stage_index + 1, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[i]
		mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
	return mass

func _current_vehicle_mass(fuel_amount: float = -1.0) -> float:
	var active := _active_stage_data()
	return float(active.get("dry_mass", 0.0)) + _remaining_stack_mass() + (fuel if fuel_amount < 0.0 else fuel_amount)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44219
	for i in range(500):
		star_points.append(Vector2(rng.randf_range(-12000, 12000), rng.randf_range(-8000, 8000)))
	set_process(true)

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
		if thrust_key_down and fuel > 0.0:
			var surface_state := _surface_body_state(landed_body_name)
			var normal: Vector2 = (rocket_position - surface_state.position).normalized()
			rotation_angle = normal.angle() - Vector2.UP.angle()
			rocket_position = surface_state.position + normal * (float(surface_state.radius) + 5.0)
			velocity = surface_state.velocity + Vector2(-normal.y, normal.x) * float(surface_state.radius) * float(surface_state.rotation_rate)
			landed = false
			status_message = "LAUNCHING FROM %s" % landed_body_name.to_upper()
		else:
			sim_time = end_time
			var landed_surface_state := _surface_body_state(landed_body_name)
			var landed_normal: Vector2 = (rocket_position - landed_surface_state.position).normalized()
			rocket_position = landed_surface_state.position + landed_normal * (float(landed_surface_state.radius) + 0.5)
			velocity = landed_surface_state.velocity + Vector2(-landed_normal.y, landed_normal.x) * float(landed_surface_state.radius) * float(landed_surface_state.rotation_rate)
			throttle = 0.0
			return
	if crashed:
		sim_time = end_time
		throttle = 0.0
		return
	var altitude := rocket_position.length() - EARTH_RADIUS
	if guidance_enabled:
		_update_guidance(dt)
	if autopilot_enabled and autopilot_phase in ["COAST", "WAIT_WINDOW", "ALIGN_DEPARTURE", "TRANSFER_COAST", "ARRIVAL_APPROACH", "ARRIVAL_PENDING", "ROUTE_COAST", "COMPLETE", "FAILED"]:
		thrust_key_down = false
	var active := _active_stage_data()
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	throttle = autopilot_throttle if autopilot_enabled and autopilot_phase == "LANDING_DESCENT" and fuel > 0.0 else (1.0 if thrust_key_down and fuel > 0.0 else 0.0)
	var fuel_used := minf(fuel, total_flow * throttle * dt)
	var mass_before := maxf(1.0, _current_vehicle_mass())
	var mass_after := maxf(1.0, mass_before - fuel_used)
	var mass_mid := (mass_before + mass_after) * 0.5
	var thrust_force: float = _engine_thrust(maxf(0.0, altitude)) * throttle if throttle > 0.0 else 0.0
	var thrust_delta_v := 0.0
	if fuel_used > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
		thrust_delta_v = thrust_force / total_flow * log(mass_before / mass_after)
	var thrust_direction := Vector2.UP.rotated(rotation_angle + gimbal_angle)
	var thrust_impulse := thrust_direction * thrust_delta_v
	if autopilot_enabled and autopilot_phase in ["TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"] and thrust_delta_v > 0.0:
		autopilot_burn_remaining = maxf(0.0, autopilot_burn_remaining - thrust_delta_v)
		if autopilot_burn_remaining <= 1.0:
			thrust_key_down = false
			if autopilot_phase == "TRANSFER_BURN":
				autopilot_transfer_start_time = sim_time
				autopilot_phase = "TRANSFER_COAST"
			elif autopilot_phase == "ARRIVAL_CAPTURE_BURN":
				var arrival_state := _autopilot_target_state()
				var arrival_position: Vector2 = rocket_position - arrival_state.position
				var arrival_velocity: Vector2 = velocity + thrust_impulse - arrival_state.velocity
				var arrival_orbit := FlightComputer.orbital_state(arrival_position, arrival_velocity, G * float(arrival_state.mass))
				if bool(arrival_orbit.get("bound", false)) and float(arrival_orbit.get("periapsis", 0.0)) > float(arrival_state.radius) + 50000.0:
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
				else:
					autopilot_phase = "FAILED"
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
	var gravity_states: Dictionary = _ephemeris_states_at(start_time + dt * 0.5)
	var initial_gravity: Vector2 = PlanetarySystem.gravity_acceleration_from_states(rocket_position, gravity_states)
	var initial_aero := _aerodynamic_acceleration(rocket_position, velocity, mass_mid, start_time)
	var half_velocity := velocity + (initial_gravity + initial_aero) * (0.5 * dt) + thrust_impulse * 0.5
	var next_position := rocket_position + half_velocity * dt
	var final_gravity: Vector2 = PlanetarySystem.gravity_acceleration_from_states(next_position, gravity_states)
	var final_aero := _aerodynamic_acceleration(next_position, half_velocity, mass_mid, end_time)
	velocity = half_velocity + (final_gravity + final_aero) * (0.5 * dt) + thrust_impulse * 0.5
	rocket_position = next_position
	sim_time = end_time
	fuel = maxf(0.0, fuel - fuel_used)
	var final_atmosphere: Dictionary = _atmosphere_at(rocket_position, velocity, end_time)
	_update_flight_environment(final_atmosphere)
	_update_heating(dt, final_atmosphere)
	if fuel <= 0.0001 and stage_index < rocket_stages.size() - 1:
		_separate_stage()
	_handle_body_contact()
	var final_altitude := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
	if not autopilot_enabled and not landed and not crashed:
		status_message = "STAGE %d  •  ENGINE FIRING" % (stage_index + 1) if throttle > 0.0 else "PAD READY  •  W TO IGNITE" if final_altitude < 100.0 else "FLIGHT ACTIVE"

func _adaptive_step_size() -> float:
	var body := _nearest_body_state(rocket_position)
	var radius: float = maxf(float(body.radius), float(body.distance))
	var altitude: float = maxf(0.0, float(body.distance) - float(body.radius))
	var gravity: float = G * float(body.mass) / (radius * radius)
	var orbital_limit: float = 0.015 * sqrt(radius / maxf(0.001, gravity))
	var speed: float = (velocity - Vector2(body.velocity)).length()
	var deep_space: bool = altitude > 1.0e8
	var atmosphere_height: float = PlanetarySystem.planetary_atmosphere_height(str(body.get("name", "Earth")))
	var in_atmosphere: bool = altitude < atmosphere_height
	var maximum_step: float = 0.25 if in_atmosphere else 1800.0
	var travel_distance_limit: float = 250.0 if in_atmosphere else maxf(100000.0, radius * 0.01)
	if deep_space:
		travel_distance_limit = maxf(50000000.0, radius * 0.01)
	var travel_limit: float = travel_distance_limit / maxf(100.0, speed)
	var drag_acceleration := _aerodynamic_acceleration(rocket_position, velocity, maxf(1.0, _current_vehicle_mass())).length()
	var drag_limit := 0.08 * speed / drag_acceleration if drag_acceleration > 0.01 else maximum_step
	var active := _active_stage_data()
	var engine_acceleration := _engine_thrust(altitude) / maxf(1.0, _current_vehicle_mass()) if thrust_key_down and fuel > 0.0 else 0.0
	var thrust_limit := 0.08 * maxf(100.0, speed) / engine_acceleration if engine_acceleration > 0.01 else maximum_step
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	var burnout_limit := fuel / total_flow if thrust_key_down and fuel > 0.0 and total_flow > 0.0 else maximum_step
	var physics_limit := clampf(minf(minf(orbital_limit, travel_limit), minf(drag_limit, thrust_limit)), 0.0005, maximum_step)
	var step_limit := minf(physics_limit, burnout_limit)
	if autopilot_enabled and autopilot_phase in ["TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"] and not thrust_key_down:
		step_limit = minf(step_limit, 0.1)
	if autopilot_enabled and autopilot_phase in ["TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN", "ROUTE_BURN"] and autopilot_burn_remaining > 0.0 and total_flow > 0.0:
		var current_mass := maxf(1.0, _current_vehicle_mass())
		var current_thrust := _engine_thrust(altitude)
		var effective_exhaust_velocity := current_thrust / total_flow
		if effective_exhaust_velocity > 0.0:
			var required_propellant := current_mass * (1.0 - exp(-autopilot_burn_remaining / effective_exhaust_velocity))
			step_limit = minf(step_limit, required_propellant / total_flow)
	if autopilot_enabled and autopilot_phase == "ROUTE_COAST" and autopilot_route_node_index < autopilot_route_nodes.size():
		var next_node: Dictionary = autopilot_route_nodes[autopilot_route_node_index]
		var time_until_node: float = maxf(0.0, float(next_node.get("time", sim_time)) - sim_time)
		if time_until_node > 0.0:
			step_limit = minf(step_limit, time_until_node)
	if autopilot_enabled and autopilot_phase in ["TRANSFER_COAST", "ARRIVAL_APPROACH"]:
		var destination_state := _autopilot_target_state()
		var relative_distance := rocket_position.distance_to(destination_state.position)
		var relative_speed: float = (velocity - Vector2(destination_state.velocity)).length()
		if relative_speed > 1.0:
			step_limit = minf(step_limit, 0.02 * relative_distance / relative_speed)
	return step_limit

func _atmosphere_at(position: Vector2, current_velocity: Vector2, time_seconds: float = -1.0) -> Dictionary:
	var sample_time := sim_time if time_seconds < 0.0 else time_seconds
	var best := {
		"body_name": "",
		"altitude": 0.0,
		"density": 0.0,
		"temperature": 250.0,
		"gas_constant": 287.05287,
		"gamma": 1.4,
		"relative_velocity": Vector2.ZERO
	}
	var earth_altitude := position.length() - EARTH_RADIUS
	var earth_density := PlanetarySystem.atmospheric_density(earth_altitude)
	if earth_density > 0.0:
		best = {
			"body_name": "Earth",
			"altitude": earth_altitude,
			"density": earth_density,
			"temperature": PlanetarySystem.atmospheric_temperature(earth_altitude),
			"gas_constant": 287.05287,
			"gamma": 1.4,
			"relative_velocity": current_velocity - Vector2(-position.y, position.x) * EARTH_ROTATION_RATE
		}
	if position.length() < 1.0e8:
		return best
	var ephemeris: Dictionary = _ephemeris_states_at(sample_time)
	for body in ephemeris.get("surface_bodies", []):
		var body_name: String = str(body.get("name", ""))
		if body_name == "Earth":
			continue
		var body_position: Vector2 = body.get("position", Vector2.ZERO)
		var body_velocity: Vector2 = body.get("velocity", Vector2.ZERO)
		var relative_position: Vector2 = position - body_position
		var body_altitude: float = relative_position.length() - float(body.get("radius", 0.0))
		var density: float = PlanetarySystem.planetary_atmosphere_density(body_name, body_altitude)
		if density <= float(best.get("density", 0.0)):
			continue
		var atmospheric_rotation: Vector2 = Vector2(-relative_position.y, relative_position.x) * float(body.get("rotation_rate", 0.0))
		var gas_constant: float = 188.9 if body_name in ["Venus", "Mars"] else 3500.0
		var gamma: float = 1.3 if body_name in ["Venus", "Mars"] else 1.4
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

func _engine_thrust(altitude: float) -> float:
	var active := _active_stage_data()
	var atmosphere := _atmosphere_at(rocket_position, velocity)
	var ambient_pressure_ratio := float(atmosphere.density) * float(atmosphere.gas_constant) * float(atmosphere.temperature) / 101325.0
	var sea_level_thrust := float(active.get("thrust", 0.0))
	var vacuum_thrust := float(active.get("vacuum_thrust", 0.0))
	return lerpf(vacuum_thrust, sea_level_thrust, clampf(ambient_pressure_ratio, 0.0, 1.0)) * float(active.get("engine_count", 1))

func _aerodynamic_acceleration(position: Vector2, current_velocity: Vector2, mass: float, time_seconds: float = -1.0) -> Vector2:
	if realism == "Arcade":
		return Vector2.ZERO
	var atmosphere := _atmosphere_at(position, current_velocity, time_seconds)
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
	discarded_stage_mass += float(_active_stage_data().get("dry_mass", 0.0)) + fuel
	velocity += Vector2.UP.rotated(rotation_angle) * 2.0
	stage_index += 1
	fuel = float(_active_stage_data().get("fuel_capacity", 0.0))
	thrust_key_down = false

func _autopilot_target_body_name() -> String:
	if autopilot_planet_index == -2:
		return "Earth"
	if autopilot_planet_index == -1:
		return "Moon"
	if autopilot_planet_index >= 0 and autopilot_planet_index < FlightComputer.PLANET_TARGETS.size():
		return str(FlightComputer.PLANET_TARGETS[autopilot_planet_index].get("name", ""))
	return ""

func _autopilot_target_state() -> Dictionary:
	var body_name: String = _autopilot_target_body_name()
	if body_name.is_empty():
		return {}
	return _surface_body_state(body_name)

func _begin_arrival_capture(target_state: Dictionary) -> void:
	var relative_position: Vector2 = rocket_position - target_state.position
	var relative_velocity: Vector2 = velocity - target_state.velocity
	var capture := FlightComputer.arrival_capture_burn(relative_position, relative_velocity, G * float(target_state.mass), float(target_state.radius))
	if not bool(capture.get("valid", false)):
		autopilot_phase = "FAILED"
		status_message = "ARRIVAL FAILED  •  TRAJECTORY INTERSECTS THE BODY"
		return
	autopilot_arrival_burn_vector = capture.burn_vector
	autopilot_burn_direction = autopilot_arrival_burn_vector.normalized()
	autopilot_burn_remaining = float(capture.delta_v)
	if autopilot_burn_remaining < 1.0:
		autopilot_phase = "COMPLETE"
		autopilot_complete = true
	else:
		autopilot_phase = "ARRIVAL_CAPTURE_BURN"

func _ephemeris_states_at(time_seconds: float) -> Dictionary:
	if ephemeris_cache.is_empty() or time_seconds < ephemeris_cache_time or time_seconds - ephemeris_cache_time >= 10.0:
		ephemeris_cache = PlanetarySystem.gravity_body_states(time_seconds)
		ephemeris_cache_time = time_seconds
		ephemeris_output_cache.clear()
		ephemeris_output_cache_time = -INF
	var offset: float = time_seconds - ephemeris_cache_time
	if absf(offset) < 0.000001:
		return ephemeris_cache
	if is_equal_approx(time_seconds, ephemeris_output_cache_time) and not ephemeris_output_cache.is_empty():
		return ephemeris_output_cache
	var adjusted_bodies: Array[Dictionary] = []
	for body in ephemeris_cache.get("bodies", []):
		var adjusted: Dictionary = body.duplicate()
		adjusted["position"] = Vector2(body.get("position", Vector2.ZERO)) + Vector2(body.get("velocity", Vector2.ZERO)) * offset
		adjusted_bodies.append(adjusted)
	var adjusted_surface: Array[Dictionary] = []
	for body in ephemeris_cache.get("surface_bodies", []):
		var adjusted: Dictionary = body.duplicate()
		adjusted["position"] = Vector2(body.get("position", Vector2.ZERO)) + Vector2(body.get("velocity", Vector2.ZERO)) * offset
		adjusted_surface.append(adjusted)
	ephemeris_output_cache = {"bodies": adjusted_bodies, "surface_bodies": adjusted_surface}
	ephemeris_output_cache_time = time_seconds
	return ephemeris_output_cache

func _surface_body_state(body_name: String) -> Dictionary:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	for body in states.get("surface_bodies", []):
		if str(body.get("name", "")) == body_name:
			return body.duplicate()
	return {}
func _nearest_body_state(position: Vector2) -> Dictionary:
	var states: Dictionary = _ephemeris_states_at(sim_time)
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for body in states.get("surface_bodies", []):
		var candidate: Dictionary = body.duplicate()
		var candidate_distance: float = position.distance_to(Vector2(candidate.get("position", Vector2.ZERO)))
		if candidate_distance < nearest_distance:
			nearest = candidate
			nearest_distance = candidate_distance
	if nearest.is_empty():
		return {}
	if nearest_distance > float(nearest.get("soi", 0.0)):
		nearest = _surface_body_state("Earth")
		nearest_distance = position.length()
	nearest["distance"] = nearest_distance
	return nearest
func _handle_body_contact() -> void:
	var bodies: Array[Dictionary] = [
		_surface_body_state("Earth"),
		_surface_body_state("Moon")
	]
	for body in PlanetarySystem.PLANETS:
		if str(body.name) != "Earth":
			bodies.append(_surface_body_state(str(body.name)))
	for body in bodies:
		var body_position: Vector2 = body.position
		var relative_position := rocket_position - body_position
		var body_radius := float(body.radius)
		if relative_position.length() > body_radius + 0.5:
			continue
		var normal := relative_position.normalized()
		var body_velocity: Vector2 = body.velocity
		var surface_velocity := body_velocity + Vector2(-relative_position.y, relative_position.x) * float(body.rotation_rate)
		var relative_speed := (velocity - surface_velocity).length()
		rocket_position = body_position + normal * (body_radius + 0.5)
		if not bool(body.solid):
			crashed = true
			status_message = "LOST IN %s  •  ATMOSPHERIC LIMIT REACHED" % str(body.name).to_upper()
		elif relative_speed <= 35.0:
			landed = true
			crashed = false
			landed_body_name = str(body.name)
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
	var guidance_body := _nearest_body_state(rocket_position)
	var guidance_position: Vector2 = rocket_position - guidance_body.position
	var guidance_velocity: Vector2 = velocity - guidance_body.velocity
	var radial := guidance_position.normalized()
	var altitude := maxf(0.0, float(guidance_body.distance) - float(guidance_body.radius))
	var tangent := Vector2(-radial.y, radial.x)
	var pitch_above_horizon := lerpf(90.0, 5.0, clampf(altitude / 100000.0, 0.0, 1.0))
	if autopilot_enabled:
		gimbal_angle = 0.0
		var orbit := FlightComputer.orbital_state(guidance_position, guidance_velocity, G * float(guidance_body.mass))
		var target_radius := float(guidance_body.radius) + autopilot_target_altitude
		var prograde := guidance_velocity.normalized() if guidance_velocity.length() > 1.0 else tangent
		match autopilot_phase:
			"ASCENT":
				status_message = "AUTOPILOT  •  ASCENT TO %.0F KM" % (autopilot_target_altitude / 1000.0)
				var ascent_orbit_periapsis := float(orbit.get("periapsis", 0.0))
				var ascent_orbit_radial_speed := absf(float(orbit.get("radial_speed", 0.0)))
				var already_in_stable_orbit := bool(orbit.get("bound", false)) and ascent_orbit_periapsis > float(guidance_body.radius) + 70000.0 and ascent_orbit_radial_speed < 100.0
				if (autopilot_target_mode == "PLANET" or (autopilot_planet_index == -2 and str(guidance_body.name) != "Earth")) and already_in_stable_orbit:
					thrust_key_down = false
					autopilot_phase = "PLAN_TRANSFER"
				elif bool(orbit.get("bound", false)) and float(orbit.get("apoapsis", 0.0)) >= target_radius:
					thrust_key_down = false
					autopilot_phase = "COAST"
				else:
					var ascent_tangential_speed: float = absf(float(orbit.get("tangential_speed", 0.0)))
					var surface_rotation_speed: float = absf(float(guidance_body.get("rotation_rate", 0.0))) * float(guidance_body.radius)
					var ascent_speed_gain: float = maxf(0.0, ascent_tangential_speed - surface_rotation_speed)
					var ascent_altitude_fraction: float = clampf((altitude - 1000.0) / 59000.0, 0.0, 1.0)
					var ascent_speed_fraction: float = clampf(ascent_speed_gain / 7200.0, 0.0, 1.0)
					var altitude_pitch: float = lerpf(88.0, 4.0, ascent_altitude_fraction)
					var speed_pitch: float = lerpf(88.0, 4.0, ascent_speed_fraction)
					pitch_above_horizon = minf(altitude_pitch, speed_pitch)
					status_message = "AUTOPILOT  •  ASCENT  •  ALT %.0F KM  •  Vt %.2F KM/S  •  PITCH %.0F°" % [altitude / 1000.0, ascent_tangential_speed / 1000.0, pitch_above_horizon]
					thrust_key_down = fuel > 0.0
			"COAST":
				status_message = "AUTOPILOT  •  COASTING TO APOAPSIS"
				thrust_key_down = false
				var coast_radial_speed: float = float(orbit.get("radial_speed", 0.0))
				if coast_radial_speed <= 30.0 and altitude > 70000.0:
					autopilot_phase = "CIRCULARISE"
			"CIRCULARISE":
				status_message = "AUTOPILOT  •  ORBITAL CIRCULARISATION"
				var circular_plan: Dictionary = FlightComputer.circularisation_burn(guidance_position, guidance_velocity, true, G * float(guidance_body.mass))
				var circular_burn_vector: Vector2 = circular_plan.get("burn_vector", Vector2.ZERO)
				autopilot_burn_direction = circular_burn_vector.normalized()
				var circular_burn_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				var circular_alignment_error := absf(angle_difference(rotation_angle, circular_burn_rotation))
				if not bool(circular_plan.get("valid", false)) or float(circular_plan.get("delta_v", INF)) <= 2.0:
					thrust_key_down = false
					if autopilot_target_mode == "PLANET" or (autopilot_planet_index == -2 and str(guidance_body.name) != "Earth"):
						autopilot_phase = "PLAN_TRANSFER"
					else:
						autopilot_phase = "COMPLETE"
						autopilot_complete = true
				else:
					thrust_key_down = fuel > 0.0 and circular_alignment_error < deg_to_rad(2.0)

			"PLAN_TRANSFER":
				status_message = "AUTOPILOT  •  SIMULATING TRANSFER TRAJECTORIES"
				thrust_key_down = false
				var vehicle_design := {"payload_mass": payload_mass, "stages": rocket_stages}
				var available_transfer_delta_v := FlightComputer.available_delta_v(vehicle_design, stage_index, fuel) * (1.0 - clampf(autopilot_safety_margin, 0.0, 0.4))
				var transfer_plan := FlightComputer.simulated_transfer_search(rocket_position, velocity, sim_time, autopilot_planet_index, available_transfer_delta_v, autopilot_speed_priority)
				if not bool(transfer_plan.get("valid", false)):
					autopilot_phase = "FAILED"
					status_message = "TRANSFER PLANNING FAILED  •  " + str(transfer_plan.get("reason", "NO FEASIBLE TRAJECTORY"))
				else:
					var planned_burn_direction: Vector2 = transfer_plan.get("departure_direction", Vector2.ZERO)
					autopilot_burn_direction = planned_burn_direction.normalized()
					autopilot_burn_remaining = float(transfer_plan.get("departure_delta_v", 0.0))
					autopilot_transfer_duration = float(transfer_plan.get("transfer_time", 0.0))
					autopilot_transfer_start_time = -1.0
					if autopilot_burn_remaining <= 1.0:
						autopilot_transfer_start_time = sim_time
						autopilot_phase = "TRANSFER_COAST"
					else:
						autopilot_phase = "TRANSFER_BURN"
					status_message = "AUTOPILOT  •  SIMULATED TRANSFER  •  %.2F KM/S" % (autopilot_burn_remaining / 1000.0)
			"WAIT_WINDOW":
				var remaining_window := FlightComputer.departure_wait_time(autopilot_planet_index, sim_time, rocket_position)
				status_message = "AUTOPILOT  •  WAITING FOR TRANSFER WINDOW  %.1f DAYS" % (remaining_window / 86400.0)
				thrust_key_down = false
				if remaining_window <= 3600.0:
					autopilot_phase = "ALIGN_DEPARTURE"
			"ALIGN_DEPARTURE":
				status_message = "AUTOPILOT  •  ALIGNING DEPARTURE ORBIT"
				thrust_key_down = false
				var desired_radial := FlightComputer.departure_periapsis_direction(autopilot_planet_index, sim_time, rocket_position.length())
				if desired_radial.length_squared() > 0.5 and rocket_position.normalized().dot(desired_radial) >= cos(deg_to_rad(1.5)):
					autopilot_burn_direction = tangent * autopilot_transfer_direction
					autopilot_phase = "TRANSFER_BURN"
			"MANEUVER_BURN":
				status_message = "AUTOPILOT  •  PLANNED MANOEUVRE  %.0F M/S" % autopilot_burn_remaining
				var manoeuvre_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, manoeuvre_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = fuel > 0.0 and autopilot_burn_remaining > 1.0 and absf(angle_difference(rotation_angle, manoeuvre_rotation)) < deg_to_rad(1.0)
				if fuel <= 0.0 and stage_index >= rocket_stages.size() - 1:
					autopilot_phase = "FAILED"
			"ROUTE_COAST":
				thrust_key_down = false
				if autopilot_route_node_index >= autopilot_route_nodes.size():
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
				else:
					var route_node: Dictionary = autopilot_route_nodes[autopilot_route_node_index]
					var node_time: float = float(route_node.get("time", sim_time))
					status_message = "AUTOPILOT  •  COAST TO NODE %d  •  T+ %.1F MIN" % [autopilot_route_node_index + 1, maxf(0.0, node_time - sim_time) / 60.0]
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
				status_message = "AUTOPILOT  •  EXECUTING NODE %d  •  %.0F M/S" % [autopilot_route_node_index + 1, autopilot_burn_remaining]
				var route_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, route_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = fuel > 0.0 and autopilot_burn_remaining > 0.1 and absf(angle_difference(rotation_angle, route_rotation)) < deg_to_rad(1.0)
				if fuel <= 0.0 and stage_index >= rocket_stages.size() - 1:
					autopilot_phase = "FAILED"
			"TRANSFER_BURN":
				status_message = "AUTOPILOT  •  INTERPLANETARY INJECTION  %.0F M/S" % autopilot_burn_remaining
				var injection_direction := autopilot_burn_direction if autopilot_burn_direction.length_squared() > 0.5 else tangent * autopilot_transfer_direction
				var injection_rotation := injection_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, injection_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = fuel > 0.0 and autopilot_burn_remaining > 1.0 and absf(angle_difference(rotation_angle, injection_rotation)) < deg_to_rad(1.0)
				if fuel <= 0.0 and stage_index >= rocket_stages.size() - 1:
					autopilot_phase = "FAILED"
			"TRANSFER_COAST":
				thrust_key_down = false
				var transfer_elapsed := maxf(0.0, sim_time - autopilot_transfer_start_time)
				var transfer_remaining := maxf(0.0, autopilot_transfer_duration - transfer_elapsed)
				var transfer_destination_state := _autopilot_target_state()
				var destination_distance := rocket_position.distance_to(transfer_destination_state.position)
				var encounter_radius := float(transfer_destination_state.soi)
				status_message = "AUTOPILOT  •  TRANSFER TO %s  •  %.1F DAYS REMAINING" % [str(transfer_destination_state.name).to_upper(), transfer_remaining / 86400.0]
				if destination_distance <= encounter_radius:
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
				var approach_relative_position: Vector2 = rocket_position - approach_target_state.position
				var approach_relative_velocity: Vector2 = velocity - approach_target_state.velocity
				var arrival_orbit := FlightComputer.orbital_state(approach_relative_position, approach_relative_velocity, G * float(approach_target_state.mass))
				var approach_radial_speed := float(arrival_orbit.get("radial_speed", 0.0))
				status_message = "AUTOPILOT  •  ARRIVAL AT %s  •  ALT %.0F KM" % [str(approach_target_state.name).to_upper(), (approach_relative_position.length() - float(approach_target_state.radius)) / 1000.0]
				if approach_radial_speed >= -10.0:
					_begin_arrival_capture(approach_target_state)
			"ARRIVAL_CAPTURE_BURN":
				status_message = "AUTOPILOT  •  CAPTURING AT %s  •  %.0F M/S" % [_autopilot_target_body_name().to_upper(), autopilot_burn_remaining]
				var capture_rotation := autopilot_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, capture_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = fuel > 0.0 and autopilot_burn_remaining > 1.0 and absf(angle_difference(rotation_angle, capture_rotation)) < deg_to_rad(1.0)
				if fuel <= 0.0 and stage_index >= rocket_stages.size() - 1:
					autopilot_phase = "FAILED"
			"LANDING_DESCENT":
				var landing_target_state := _autopilot_target_state()
				var landing_relative_position: Vector2 = rocket_position - landing_target_state.position
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
				status_message = "LANDING GUIDANCE  •  %s  •  ALT %.1F KM  •  V/S %.1F M/S" % [str(landing_target_state.name).to_upper(), landing_altitude / 1000.0, landing_radial_speed]
				if fuel <= 0.0 and stage_index >= rocket_stages.size() - 1:
					autopilot_phase = "FAILED"
					thrust_key_down = false
			"ARRIVAL_PENDING":
				status_message = "ARRIVAL WINDOW MISSED  •  TARGET OUTSIDE CAPTURE REGION"
				thrust_key_down = false
			"COMPLETE":
				status_message = "AUTOPILOT  •  TARGET ORBIT ACHIEVED"
				thrust_key_down = false
				autopilot_complete = true
			"FAILED":
				status_message = "LANDING ABORTED  •  INSUFFICIENT FUEL OR THRUST" if autopilot_target_mode == "LAND" else "AUTOPILOT  •  BURN INCOMPLETE"
				thrust_key_down = false
		var autopilot_direction := prograde
		if autopilot_phase == "ASCENT":
			autopilot_direction = radial * sin(deg_to_rad(pitch_above_horizon)) + tangent * cos(deg_to_rad(pitch_above_horizon))
		elif autopilot_phase == "CIRCULARISE":
			autopilot_direction = autopilot_burn_direction if autopilot_burn_direction.length_squared() > 0.5 else tangent
		elif autopilot_phase in ["WAIT_WINDOW", "ALIGN_DEPARTURE"]:
			autopilot_direction = tangent * autopilot_transfer_direction
		elif autopilot_phase in ["TRANSFER_BURN", "ARRIVAL_CAPTURE_BURN", "MANEUVER_BURN"]:
			autopilot_direction = autopilot_burn_direction if autopilot_burn_direction.length_squared() > 0.5 else tangent * autopilot_transfer_direction
		elif autopilot_phase == "LANDING_DESCENT":
			var landing_direction_state := _autopilot_target_state()
			var landing_direction_position: Vector2 = rocket_position - landing_direction_state.position
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
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var ignite_pressed: bool = event.is_action_pressed("engine_toggle") or event.keycode == KEY_W or event.physical_keycode == KEY_W
	var cutoff_pressed: bool = event.is_action_pressed("throttle_cutoff") or event.keycode == KEY_S or event.physical_keycode == KEY_S
	if ignite_pressed:
		if autopilot_enabled:
			autopilot_enabled = false
			guidance_enabled = false
		if landed and fuel > 0.0:
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
				camera_zoom = minf(0.0025, camera_zoom * 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if show_solar_system:
				solar_map_zoom = maxf(0.25, solar_map_zoom / 1.2)
			else:
				camera_zoom = maxf(0.0000005, camera_zoom / 1.2)

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


func _planet_atmosphere_visual(name: String) -> Dictionary:
	match name:
		"Earth":
			return {"height": 100000.0, "color": Color(0.22, 0.62, 1.0)}
		"Venus":
			return {"height": 250000.0, "color": Color(0.96, 0.72, 0.36)}
		"Mars":
			return {"height": 125000.0, "color": Color(0.91, 0.48, 0.31)}
		"Jupiter":
			return {"height": 1000000.0, "color": Color(0.86, 0.67, 0.48)}
		"Saturn":
			return {"height": 1500000.0, "color": Color(0.91, 0.79, 0.56)}
		"Uranus":
			return {"height": 1000000.0, "color": Color(0.46, 0.81, 0.86)}
		"Neptune":
			return {"height": 1500000.0, "color": Color(0.36, 0.53, 1.0)}
	return {"height": 0.0, "color": Color.TRANSPARENT}


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
		_draw_hud()
		return

	if show_grid:
		_draw_grid(view_center)

	_draw_atmosphere(earth_screen, radius_px, 100000.0, Color(0.22, 0.62, 1.0))
	draw_circle(earth_screen, radius_px + 7, Color(0.15, 0.35, 0.58, 0.12))
	draw_circle(earth_screen, radius_px, Color(0.10, 0.28, 0.53))
	draw_arc(earth_screen, radius_px, 0, TAU, 120, Color(0.28, 0.64, 0.95), 2.0)
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
		draw_circle(moon_screen, moon_radius_px + 3.0, Color(0.55, 0.58, 0.66, 0.16))
		draw_circle(moon_screen, moon_radius_px, Color(0.48, 0.49, 0.52))
		draw_arc(moon_screen, moon_radius_px, 0.0, TAU, 64, Color(0.72, 0.74, 0.78), 1.0)
		draw_string(ThemeDB.fallback_font, moon_screen + Vector2(moon_radius_px + 8.0, 4.0), "MOON", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.84))

	var destination := _nearest_body_state(rocket_position)
	if str(destination.name) not in ["Earth", "Moon"] and float(destination.distance) < float(destination.soi):
		var destination_screen: Vector2 = rocket_screen + (Vector2(destination.position) - rocket_position) * altitude_visual_scale
		var destination_radius := clampf(float(destination.radius) * altitude_visual_scale, 3.0, 72.0)
		if destination_screen.x > -destination_radius - 30.0 and destination_screen.x < size.x + destination_radius + 30.0 and destination_screen.y > -destination_radius - 30.0 and destination_screen.y < size.y + destination_radius + 30.0:
			var destination_color := Color(0.82, 0.38, 0.25)
			match str(destination.name):
				"Mercury":
					destination_color = Color(0.62, 0.58, 0.52)
				"Venus":
					destination_color = Color(0.88, 0.72, 0.42)
				"Jupiter":
					destination_color = Color(0.78, 0.62, 0.46)
				"Saturn":
					destination_color = Color(0.82, 0.75, 0.55)
				"Uranus":
					destination_color = Color(0.48, 0.78, 0.82)
				"Neptune":
					destination_color = Color(0.28, 0.42, 0.88)
			var atmosphere_visual: Dictionary = _planet_atmosphere_visual(str(destination.name))
			_draw_atmosphere(destination_screen, destination_radius, float(atmosphere_visual.get("height", 0.0)), atmosphere_visual.get("color", Color.TRANSPARENT))
			draw_circle(destination_screen, destination_radius + 5.0, Color(0.45, 0.7, 1.0, 0.12))
			draw_circle(destination_screen, destination_radius, destination_color)
			draw_arc(destination_screen, destination_radius, 0.0, TAU, 80, Color(0.9, 0.92, 1.0, 0.8), 1.0)
			draw_string(ThemeDB.fallback_font, destination_screen + Vector2(destination_radius + 8.0, 4.0), str(destination.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.88, 1.0))
		var soi_pixels := float(destination.soi) * altitude_visual_scale
		if soi_pixels > destination_radius and soi_pixels < 1200.0:
			draw_arc(destination_screen, soi_pixels, 0.0, TAU, 100, Color(0.35, 0.72, 1.0, 0.22), 1.0)

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
	_draw_rocket(rocket_screen + Vector2.UP.rotated(rotation_angle) * 14.0 * object_scale, object_scale)
	if show_vectors:
		var velocity_end := rocket_screen + velocity.normalized() * 65.0
		draw_line(rocket_screen, velocity_end, Color(0.25, 0.9, 0.55), 2.0)
		draw_string(ThemeDB.fallback_font, velocity_end + Vector2(6, 0), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.9, 0.55))

	_draw_hud()

func _draw_solar_system(center: Vector2) -> void:
	var map_scale := minf(size.x, size.y) * 0.43 / 4.4951e12 * solar_map_zoom
	draw_circle(center, 5.0, Color(1.0, 0.78, 0.28))
	draw_string(ThemeDB.fallback_font, center + Vector2(10, 4), "SUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.82, 0.48))
	for planet in PlanetarySystem.PLANETS:
		var orbit_radius := float(planet.semi_major_axis) * map_scale
		draw_arc(center, orbit_radius, 0.0, TAU, 180, Color(0.28, 0.43, 0.58, 0.42), 1.0)
		var period := float(planet.orbital_period) * 86400.0
		var angle := TAU * sim_time / period
		var planet_position := center + Vector2(cos(angle), sin(angle)) * orbit_radius
		var planet_radius := clampf(pow(float(planet.radius) / EARTH_RADIUS, 0.45) * 3.0, 2.0, 8.0)
		var planet_color := Color(0.32, 0.62, 0.88)
		if planet.name == "Earth":
			planet_color = Color(0.22, 0.68, 1.0)
		elif planet.name == "Mars":
			planet_color = Color(0.88, 0.39, 0.24)
		elif planet.name == "Jupiter":
			planet_color = Color(0.82, 0.66, 0.48)
		elif planet.name == "Saturn":
			planet_color = Color(0.82, 0.75, 0.53)
		draw_circle(planet_position, planet_radius, planet_color)
		draw_string(ThemeDB.fallback_font, planet_position + Vector2(planet_radius + 5.0, 4.0), str(planet.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.82, 0.92))
	draw_string(ThemeDB.fallback_font, Vector2(24, size.y - 420.0 * clampf(minf(size.x / 1440.0, size.y / 900.0), 0.7, 1.0)), "SOLAR SYSTEM OVERVIEW  •  ALL PLANETARY ORBITS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.8, 1.0))

func _calculate_predicted_trajectory() -> void:
	predicted_path.clear()
	var position := rocket_position
	var predicted_velocity := velocity
	var predicted_fuel := fuel
	var predicted_stage := stage_index
	var dt := 5.0
	for i in range(360):
		var step_time := sim_time + float(i) * dt
		var mass := payload_mass
		var active: Dictionary = {}
		var total_flow := 0.0
		var thrust_force := 0.0
		var burn := 0.0
		if predicted_stage < rocket_stages.size():
			active = rocket_stages[predicted_stage]
			mass += float(active.get("dry_mass", 0.0)) + predicted_fuel
			for j in range(predicted_stage + 1, rocket_stages.size()):
				var upper: Dictionary = rocket_stages[j]
				mass += float(upper.get("dry_mass", 0.0)) + float(upper.get("fuel_capacity", 0.0))
			total_flow = float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
			burn = minf(predicted_fuel, total_flow * throttle * dt)
			var atmosphere := _atmosphere_at(position, predicted_velocity, step_time)
			var pressure_ratio := float(atmosphere.density) * float(atmosphere.gas_constant) * float(atmosphere.temperature) / 101325.0
			thrust_force = lerpf(float(active.get("vacuum_thrust", 0.0)), float(active.get("thrust", 0.0)), clampf(pressure_ratio, 0.0, 1.0)) * float(active.get("engine_count", 1)) * throttle
		var mass_after := maxf(1.0, mass - burn)
		var mass_mid := (mass + mass_after) * 0.5
		var thrust_delta_v := 0.0
		if burn > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
			thrust_delta_v = thrust_force / total_flow * log(mass / mass_after)
		var thrust_impulse := Vector2.UP.rotated(rotation_angle + gimbal_angle) * thrust_delta_v
		var initial_gravity := PlanetarySystem.gravity_acceleration(position, step_time)
		var initial_aero := _aerodynamic_acceleration(position, predicted_velocity, mass_mid, step_time)
		var half_velocity := predicted_velocity + (initial_gravity + initial_aero) * (0.5 * dt) + thrust_impulse * 0.5
		var next_position := position + half_velocity * dt
		var final_gravity := PlanetarySystem.gravity_acceleration(next_position, step_time + dt)
		var final_aero := _aerodynamic_acceleration(next_position, half_velocity, mass_mid, step_time + dt)
		predicted_velocity = half_velocity + (final_gravity + final_aero) * (0.5 * dt) + thrust_impulse * 0.5
		position = next_position
		predicted_fuel = maxf(0.0, predicted_fuel - burn)
		if predicted_fuel <= 0.0001 and predicted_stage < rocket_stages.size() - 1:
			predicted_stage += 1
			predicted_fuel = float(rocket_stages[predicted_stage].get("fuel_capacity", 0.0))
		predicted_path.append(position)
		if position.length() < EARTH_RADIUS:
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
	var relative_position: Vector2 = rocket_position - body.position
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

func _draw_rocket(p: Vector2, object_scale: float) -> void:
	var forward := Vector2.UP.rotated(rotation_angle)
	var side := Vector2.RIGHT.rotated(rotation_angle)
	var tip := p + forward * 17.0 * object_scale
	var left := p - forward * 12.0 * object_scale - side * 6.0 * object_scale
	var right := p - forward * 12.0 * object_scale + side * 6.0 * object_scale
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.82, 0.88, 0.94))
	draw_line(left, right, Color(0.25, 0.55, 0.78), 1.5)
	if throttle > 0.0 and fuel > 0.0:
		var flame_base := p - forward * 12.0 * object_scale
		var flame_tip := p - forward * (28.0 + randf_range(0, 8)) * object_scale
		draw_colored_polygon(PackedVector2Array([flame_base - side * 3 * object_scale, flame_tip, flame_base + side * 3 * object_scale]), Color(1.0, 0.48, 0.12, 0.9))

func _draw_hud() -> void:
	var ui_scale := clampf(minf(size.x / 1440.0, size.y / 900.0), 0.7, 1.0)
	var local_body := _nearest_body_state(rocket_position)
	var local_position: Vector2 = rocket_position - local_body.position
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
		"FUEL           %s%%" % str(roundi(100.0 * fuel / maxf(1.0, active_fuel_capacity))),
		"THROTTLE       %s%%" % str(roundi(throttle * 100.0)),
		"THRUST / WEIGHT %.2f" % thrust_to_weight,
		"IDEAL ΔV EST.  %.2f km/s" % (remaining_delta_v / 1000.0),
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
		"TIME WARP      x%s" % str(snappedf(time_warp, 0.01))
	]
	if autopilot_target_mode in ["PLANET", "LAND"] and autopilot_enabled:
		var target_state: Dictionary = _autopilot_target_state()
		var target_range: float = rocket_position.distance_to(target_state["position"])
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
	var total := 0.0
	var mass := current_mass
	for i in range(stage_index, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[i]
		var propellant := fuel if i == stage_index else float(stage.get("fuel_capacity", 0.0))
		var dry := float(stage.get("dry_mass", 0.0))
		var engines := float(stage.get("engine_count", 1))
		var thrust := float(stage.get("vacuum_thrust", 0.0)) * engines
		var flow := float(stage.get("flow", 0.0)) * engines
		var final_mass := mass - propellant
		if propellant > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > dry:
			total += thrust / flow * log(mass / final_mass)
		mass = final_mass - dry
	return total

func _apsis(apo: bool) -> float:
	var body := _nearest_body_state(rocket_position)
	var relative_position: Vector2 = rocket_position - body.position
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

func get_save_data() -> Dictionary:
	return {
		"sim_time": sim_time,
		"position": [rocket_position.x, rocket_position.y],
		"velocity": [velocity.x, velocity.y],
		"rotation_angle": rotation_angle,
		"fuel": fuel,
		"stage_index": stage_index,
		"discarded_stage_mass": discarded_stage_mass,
		"gimbal_angle": gimbal_angle,
		"guidance_enabled": guidance_enabled,
		"autopilot_enabled": autopilot_enabled,
		"autopilot_target_altitude": autopilot_target_altitude,
		"autopilot_target_mode": autopilot_target_mode,
		"autopilot_planet_index": autopilot_planet_index,
		"autopilot_burn_remaining": autopilot_burn_remaining,
		"autopilot_throttle": autopilot_throttle,
		"autopilot_transfer_start_time": autopilot_transfer_start_time,
		"autopilot_transfer_duration": autopilot_transfer_duration,
		"autopilot_speed_priority": autopilot_speed_priority,
		"autopilot_safety_margin": autopilot_safety_margin,
		"autopilot_transfer_direction": autopilot_transfer_direction,
		"autopilot_arrival_burn_x": autopilot_arrival_burn_vector.x,
		"autopilot_arrival_burn_y": autopilot_arrival_burn_vector.y,
		"landed": landed,
		"crashed": crashed,
		"landed_body_name": landed_body_name,
		"autopilot_burn_direction_x": autopilot_burn_direction.x,
		"autopilot_burn_direction_y": autopilot_burn_direction.y,
		"autopilot_route_nodes": autopilot_route_nodes.duplicate(true),
		"autopilot_route_node_index": autopilot_route_node_index,
		"autopilot_complete": autopilot_complete,
		"autopilot_phase": autopilot_phase,
		"heat_shield_temperature": heat_shield_temperature,
		"peak_heat_flux_mw": peak_heat_flux_mw,
		"max_dynamic_pressure_pa": max_dynamic_pressure_pa,
		"throttle": throttle,
		"time_warp": time_warp,
		"paused": paused,
		"rocket_design": {"payload_mass": payload_mass, "stages": rocket_stages.duplicate(true)}
	}

func load_save_data(data: Dictionary) -> void:
	var saved_design: Variant = data.get("rocket_design", null)
	if saved_design is Dictionary:
		set_rocket_design(saved_design)
	stage_index = clampi(int(data.get("stage_index", 0)), 0, maxi(0, rocket_stages.size() - 1))
	sim_time = float(data.get("sim_time", 0.0))
	var p: Array = data.get("position", [0.0, -EARTH_RADIUS - 2.0])
	var v: Array = data.get("velocity", [EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0])
	rocket_position = Vector2(float(p[0]), float(p[1]))
	velocity = Vector2(float(v[0]), float(v[1]))
	rotation_angle = float(data.get("rotation_angle", 0.0))
	fuel = float(data.get("fuel", _active_stage_data().get("fuel_capacity", 0.0)))
	discarded_stage_mass = float(data.get("discarded_stage_mass", 0.0))
	gimbal_angle = float(data.get("gimbal_angle", 0.0))
	guidance_enabled = bool(data.get("guidance_enabled", false))
	autopilot_enabled = bool(data.get("autopilot_enabled", false))
	autopilot_target_altitude = float(data.get("autopilot_target_altitude", 200000.0))
	autopilot_target_mode = str(data.get("autopilot_target_mode", "ORBIT"))
	autopilot_planet_index = int(data.get("autopilot_planet_index", -1))
	autopilot_burn_remaining = float(data.get("autopilot_burn_remaining", 0.0))
	autopilot_throttle = float(data.get("autopilot_throttle", 0.0))
	autopilot_transfer_start_time = float(data.get("autopilot_transfer_start_time", sim_time if str(data.get("autopilot_phase", "IDLE")) == "TRANSFER_COAST" else -1.0))
	autopilot_transfer_duration = float(data.get("autopilot_transfer_duration", 0.0))
	autopilot_speed_priority = clampf(float(data.get("autopilot_speed_priority", 0.35)), 0.0, 1.0)
	autopilot_safety_margin = clampf(float(data.get("autopilot_safety_margin", 0.10)), 0.0, 0.4)
	autopilot_transfer_direction = float(data.get("autopilot_transfer_direction", 1.0))
	autopilot_arrival_burn_vector = Vector2(float(data.get("autopilot_arrival_burn_x", 0.0)), float(data.get("autopilot_arrival_burn_y", 0.0)))
	landed = bool(data.get("landed", false))
	crashed = bool(data.get("crashed", false))
	landed_body_name = str(data.get("landed_body_name", "Earth"))
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
