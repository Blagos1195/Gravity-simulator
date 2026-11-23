extends RefCounted
class_name FlightComputer

const PlanetarySystem = preload("res://scripts/planetary_system.gd")

static var G := 6.67430e-11
static var EARTH_MU := 3.986004418e14
static var EARTH_RADIUS := 6.371e6
static var MOON_ORBIT_RADIUS := 3.844e8
static var MOON_MASS := 7.342e22
static var MOON_RADIUS := 1.7374e6
static var MOON_MU := G * MOON_MASS
static var SUN_MU := 1.32712440018e20
static var EARTH_ORBIT_RADIUS := 1.495978707e11
static var EARTH_ORBIT_PERIOD := 365.256363004 * 86400.0
const INFINITE_FUEL_PLANNING_DELTA_V := 100000.0
const BURN_COMPLETION_TOLERANCE := 0.05
const SATELLITE_TARGET_INDEX_BASE := 1000
static var PLANET_TARGETS: Array[Dictionary] = []
static var SATELLITE_TARGETS: Array[Dictionary] = []

static func _static_init() -> void:
	G = PlanetarySystem.G
	EARTH_MU = G * PlanetarySystem.EARTH_MASS
	EARTH_RADIUS = PlanetarySystem.EARTH_RADIUS
	MOON_ORBIT_RADIUS = PlanetarySystem.MOON_TRANSFER_ORBIT_RADIUS
	MOON_MASS = PlanetarySystem.MOON_MASS
	MOON_RADIUS = PlanetarySystem.MOON_RADIUS
	MOON_MU = G * MOON_MASS
	SUN_MU = G * PlanetarySystem.SUN_MASS
	for planet in PlanetarySystem.PLANETS:
		if str(planet.get("name", "")) == "Earth":
			EARTH_ORBIT_RADIUS = float(planet.get("a", EARTH_ORBIT_RADIUS / PlanetarySystem.ASTRONOMICAL_UNIT)) * PlanetarySystem.ASTRONOMICAL_UNIT
			EARTH_ORBIT_PERIOD = float(planet.get("orbital_period", 365.256)) * 86400.0
			continue
		PLANET_TARGETS.append({
			"name": str(planet.get("name", "")),
			"radius": float(planet.get("a", 0.0)) * PlanetarySystem.ASTRONOMICAL_UNIT,
			"planet_radius": float(planet.get("radius", 0.0)),
			"mass": float(planet.get("mass", 0.0)),
			"period_days": float(planet.get("orbital_period", 0.0))
		})
	for planet in PlanetarySystem.PLANETS:
		var host_name := str(planet.get("name", ""))
		if host_name == "Earth":
			continue
		var host_target_index := -1
		for planet_index in range(PLANET_TARGETS.size()):
			if str(PLANET_TARGETS[planet_index].get("name", "")) == host_name:
				host_target_index = planet_index
				break
		for satellite_variant in planet.get("satellites", []):
			var satellite: Dictionary = satellite_variant
			var satellite_name := str(satellite.get("name", ""))
			SATELLITE_TARGETS.append({
				"id": SATELLITE_TARGET_INDEX_BASE + SATELLITE_TARGETS.size(),
				"name": "%s %s" % [host_name, satellite_name],
				"display_name": "%s (%s)" % [satellite_name, host_name],
				"host_name": host_name,
				"host_target_index": host_target_index
			})

static func _satellite_target_data(target_index: int) -> Dictionary:
	var satellite_index := target_index - SATELLITE_TARGET_INDEX_BASE
	if satellite_index < 0 or satellite_index >= SATELLITE_TARGETS.size():
		return {}
	return SATELLITE_TARGETS[satellite_index]

static func satellite_targets_for_host(host_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for satellite in SATELLITE_TARGETS:
		if str(satellite.get("host_name", "")) == host_name:
			result.append(satellite.duplicate(true))
	return result


static func _is_satellite_target(target_index: int) -> bool:
	return not _satellite_target_data(target_index).is_empty()

static func _is_valid_target_index(target_index: int) -> bool:
	return target_index == -2 or target_index == -1 or (target_index >= 0 and target_index < PLANET_TARGETS.size()) or _is_satellite_target(target_index)

static func target_body_name(target_index: int) -> String:
	if target_index == -2:
		return "Earth"
	if target_index == -1:
		return "Moon"
	if target_index >= 0 and target_index < PLANET_TARGETS.size():
		return str(PLANET_TARGETS[target_index].get("name", ""))
	var satellite: Dictionary = _satellite_target_data(target_index)
	if not satellite.is_empty():
		return str(satellite.get("name", ""))
	return ""

static func minimum_safe_orbit_altitude(body_name: String, body_radius: float) -> float:
	var atmosphere_height := maxf(0.0, PlanetarySystem.planetary_atmosphere_height(body_name))
	var atmosphere_margin := maxf(1000.0, atmosphere_height * 0.1) if atmosphere_height > 0.0 else 0.0
	return maxf(maxf(1000.0, body_radius * 0.001), atmosphere_height + atmosphere_margin)


static func maximum_stable_orbit_altitude(body_radius: float, sphere_of_influence: float) -> float:
	if body_radius <= 0.0 or sphere_of_influence <= body_radius:
		return 0.0
	return maxf(0.0, sphere_of_influence * 0.45 - body_radius)


static func orbit_radius_tolerance(target_radius: float) -> float:
	return maxf(500.0, minf(4000.0, target_radius * 0.0008))


static func orbital_state(position: Vector2, velocity: Vector2, mu: float = -1.0) -> Dictionary:
	if mu < 0.0:
		mu = EARTH_MU
	var radius := position.length()
	if radius <= 0.0 or mu <= 0.0:
		return {"valid": false}
	var speed_squared := velocity.length_squared()
	var specific_energy := speed_squared * 0.5 - mu / radius
	var angular_momentum := position.cross(velocity)
	var eccentricity_vector := Vector2(velocity.y * angular_momentum, -velocity.x * angular_momentum) / mu - position / radius
	var eccentricity := eccentricity_vector.length()
	var semi_major_axis := -mu / (2.0 * specific_energy) if absf(specific_energy) > 0.000001 else INF
	var periapsis := semi_major_axis * (1.0 - eccentricity) if semi_major_axis > 0.0 else -semi_major_axis * (eccentricity - 1.0)
	var apoapsis := semi_major_axis * (1.0 + eccentricity) if eccentricity < 1.0 and semi_major_axis > 0.0 else INF
	var radial_speed := velocity.dot(position / radius)
	var tangential_speed := absf(angular_momentum) / radius
	return {
		"valid": true,
		"specific_energy": specific_energy,
		"angular_momentum": angular_momentum,
		"eccentricity": eccentricity,
		"semi_major_axis": semi_major_axis,
		"periapsis": periapsis,
		"apoapsis": apoapsis,
		"radial_speed": radial_speed,
		"tangential_speed": tangential_speed,
		"bound": specific_energy < 0.0
	}

static func circular_orbit_speed(radius: float, mu: float = -1.0) -> float:
	if mu < 0.0:
		mu = EARTH_MU
	if radius <= 0.0 or mu <= 0.0:
		return 0.0
	return sqrt(mu / radius)

static func circularisation_burn(position: Vector2, velocity: Vector2, prograde: bool = true, mu: float = -1.0) -> Dictionary:
	if mu < 0.0:
		mu = EARTH_MU
	var radius := position.length()
	if radius <= 0.0:
		return {"valid": false}
	var tangent := Vector2(-position.y, position.x).normalized()
	var direction := 1.0 if velocity.dot(tangent) >= 0.0 else -1.0
	if not prograde:
		direction *= -1.0
	var desired_velocity := tangent * direction * circular_orbit_speed(radius, mu)
	var burn_vector := desired_velocity - velocity
	return {
		"valid": true,
		"delta_v": burn_vector.length(),
		"burn_vector": burn_vector,
		"desired_velocity": desired_velocity,
		"direction": burn_vector.normalized() if burn_vector.length() > 0.001 else Vector2.ZERO
	}

static func target_radius_burn(position: Vector2, velocity: Vector2, target_radius: float, mu: float = -1.0) -> Dictionary:
	if mu < 0.0:
		mu = EARTH_MU
	var radius := position.length()
	if radius <= 0.0 or target_radius <= 0.0 or mu <= 0.0:
		return {"valid": false}
	var tangent := Vector2(-position.y, position.x).normalized()
	var direction := 1.0 if velocity.dot(tangent) >= 0.0 else -1.0
	var transfer_semi_major_axis := (radius + target_radius) * 0.5
	var desired_speed := sqrt(mu * (2.0 / radius - 1.0 / transfer_semi_major_axis))
	var desired_velocity := tangent * direction * desired_speed
	var burn_vector := desired_velocity - velocity
	var resulting_orbit := orbital_state(position, desired_velocity, mu)
	var safe_periapsis := target_radius
	return {
		"valid": bool(resulting_orbit.get("bound", false)) and target_radius > 0.0,
		"delta_v": burn_vector.length(),
		"burn_vector": burn_vector,
		"desired_velocity": desired_velocity,
		"direction": burn_vector.normalized() if burn_vector.length() > 0.001 else Vector2.ZERO,
		"target_radius": target_radius,
		"periapsis": float(resulting_orbit.get("periapsis", 0.0)),
		"apoapsis": float(resulting_orbit.get("apoapsis", INF)),
		"safe_periapsis": safe_periapsis
	}

static func hohmann_transfer(origin_radius: float, target_radius: float, mu: float = -1.0) -> Dictionary:
	if mu < 0.0:
		mu = EARTH_MU
	if origin_radius <= 0.0 or target_radius <= 0.0 or is_equal_approx(origin_radius, target_radius):
		return {"valid": false}
	var transfer_axis := (origin_radius + target_radius) * 0.5
	var origin_speed := sqrt(mu / origin_radius)
	var target_speed := sqrt(mu / target_radius)
	var transfer_origin_speed := sqrt(mu * (2.0 / origin_radius - 1.0 / transfer_axis))
	var transfer_target_speed := sqrt(mu * (2.0 / target_radius - 1.0 / transfer_axis))
	var first_burn := absf(transfer_origin_speed - origin_speed)
	var second_burn := absf(target_speed - transfer_target_speed)
	var transfer_time := PI * sqrt(pow(transfer_axis, 3.0) / mu)
	return {
		"valid": true,
		"departure_delta_v": first_burn,
		"arrival_delta_v": second_burn,
		"total_delta_v": first_burn + second_burn,
		"transfer_time": transfer_time,
		"transfer_semi_major_axis": transfer_axis
	}

static func interplanetary_transfer(target_index: int, parking_altitude: float = 200000.0) -> Dictionary:
	if target_index == -1:
		var lunar := hohmann_transfer(EARTH_RADIUS + parking_altitude, EARTH_RADIUS + MOON_ORBIT_RADIUS)
		if not bool(lunar.get("valid", false)):
			return {"valid": false}
		var lunar_transfer_axis := (EARTH_RADIUS + parking_altitude + EARTH_RADIUS + MOON_ORBIT_RADIUS) * 0.5
		var lunar_arrival_speed := sqrt(EARTH_MU * (2.0 / (EARTH_RADIUS + MOON_ORBIT_RADIUS) - 1.0 / lunar_transfer_axis))
		var moon_orbital_speed := sqrt(EARTH_MU / (EARTH_RADIUS + MOON_ORBIT_RADIUS))
		var lunar_arrival_excess := absf(lunar_arrival_speed - moon_orbital_speed)
		var lunar_parking_radius := MOON_RADIUS + 100000.0
		var lunar_circular_speed := sqrt(MOON_MU / lunar_parking_radius)
		var lunar_capture_speed := sqrt(lunar_arrival_excess * lunar_arrival_excess + 2.0 * MOON_MU / lunar_parking_radius)
		var lunar_capture_delta_v := lunar_capture_speed - lunar_circular_speed
		return {
			"valid": true,
			"name": "Moon",
			"departure_delta_v": float(lunar.departure_delta_v),
			"arrival_delta_v": lunar_capture_delta_v,
			"total_delta_v": float(lunar.departure_delta_v) + lunar_capture_delta_v,
			"transfer_time": float(lunar.transfer_time),
			"direction": 1.0,
			"phase_angle": 0.0,
			"arrival_excess_speed": lunar_arrival_excess
		}
	if target_index < 0 or target_index >= PLANET_TARGETS.size():
		return {"valid": false}
	var target: Dictionary = PLANET_TARGETS[target_index]
	var target_radius := float(target.radius)
	var planet_transfer_axis := (EARTH_ORBIT_RADIUS + target_radius) * 0.5
	var earth_speed := sqrt(SUN_MU / EARTH_ORBIT_RADIUS)
	var target_speed := sqrt(SUN_MU / target_radius)
	var transfer_departure_speed := sqrt(SUN_MU * (2.0 / EARTH_ORBIT_RADIUS - 1.0 / planet_transfer_axis))
	var transfer_arrival_speed := sqrt(SUN_MU * (2.0 / target_radius - 1.0 / planet_transfer_axis))
	var departure_excess := absf(transfer_departure_speed - earth_speed)
	var arrival_excess := absf(target_speed - transfer_arrival_speed)
	var target_parking_radius := maxf(float(target.planet_radius) + 200000.0, float(target.planet_radius) * 1.1)
	var target_mu := G * float(target.mass)
	var target_circular_speed := sqrt(target_mu / target_parking_radius)
	var target_capture_speed := sqrt(arrival_excess * arrival_excess + 2.0 * target_mu / target_parking_radius)
	var arrival_capture_delta_v := target_capture_speed - target_circular_speed
	var parking_radius := EARTH_RADIUS + maxf(70000.0, parking_altitude)
	var parking_speed := circular_orbit_speed(parking_radius)
	var escape_speed := sqrt(departure_excess * departure_excess + 2.0 * EARTH_MU / parking_radius)
	var injection_delta_v := escape_speed - parking_speed
	var transfer_time := PI * sqrt(pow(planet_transfer_axis, 3.0) / SUN_MU)
	var target_mean_motion := TAU / (float(target.period_days) * 86400.0)
	var phase_angle := wrapf(PI - target_mean_motion * transfer_time, -PI, PI)
	return {
		"valid": true,
		"name": str(target.name),
		"departure_delta_v": injection_delta_v,
		"arrival_delta_v": arrival_capture_delta_v,
		"total_delta_v": injection_delta_v + arrival_capture_delta_v,
		"transfer_time": transfer_time,
		"departure_excess_speed": departure_excess,
		"arrival_excess_speed": arrival_excess,
		"direction": 1.0 if transfer_departure_speed >= earth_speed else -1.0,
		"phase_angle": phase_angle,
		"transfer_semi_major_axis": planet_transfer_axis
	}

static func departure_wait_time(target_index: int, current_time: float, parking_position: Vector2 = Vector2.ZERO) -> float:
	if _is_satellite_target(target_index):
		target_index = int(_satellite_target_data(target_index).get("host_target_index", -1))
	if target_index == -1:
		if parking_position.length() <= EARTH_RADIUS:
			return 0.0
		var lunar_window_transfer := hohmann_transfer(parking_position.length(), EARTH_RADIUS + MOON_ORBIT_RADIUS)
		var transfer_time := float(lunar_window_transfer.get("transfer_time", 0.0))
		var moon_future_position := PlanetarySystem.moon_position(current_time + transfer_time)
		var phase_error := wrapf(moon_future_position.angle() - parking_position.angle() - PI, -PI, PI)
		var moon_now := PlanetarySystem.moon_position(current_time)
		var moon_next := PlanetarySystem.moon_position(current_time + 1.0)
		var lunar_rate := angle_difference(moon_now.angle(), moon_next.angle())
		var parking_rate := sqrt(EARTH_MU / pow(parking_position.length(), 3.0))
		var relative_rate := lunar_rate - parking_rate
		if absf(relative_rate) < 0.000000000001:
			return 0.0
		return fposmod(-phase_error / relative_rate, TAU / absf(relative_rate))
	if target_index < 0 or target_index >= PLANET_TARGETS.size():
		return 0.0
	var target: Dictionary = PLANET_TARGETS[target_index]
	var earth_rate := TAU / EARTH_ORBIT_PERIOD
	var target_rate := TAU / (float(target.period_days) * 86400.0)
	var relative_rate := target_rate - earth_rate
	if absf(relative_rate) < 0.000000000001:
		return 0.0
	var earth_angle := earth_rate * current_time
	var target_angle := target_rate * current_time
	var current_phase := wrapf(target_angle - earth_angle, -PI, PI)
	var planetary_window_transfer := interplanetary_transfer(target_index)
	var desired_phase := float(planetary_window_transfer.get("phase_angle", 0.0))
	var phase_difference := wrapf(desired_phase - current_phase, -PI, PI)
	var wait := phase_difference / relative_rate
	var synodic_period := TAU / absf(relative_rate)
	return fposmod(wait, synodic_period)

static func departure_periapsis_direction(target_index: int, current_time: float, parking_radius: float) -> Vector2:
	if _is_satellite_target(target_index):
		target_index = int(_satellite_target_data(target_index).get("host_target_index", -1))
	if target_index == -1:
		var transfer := hohmann_transfer(parking_radius, EARTH_RADIUS + MOON_ORBIT_RADIUS)
		var arrival_position := PlanetarySystem.moon_position(current_time + float(transfer.get("transfer_time", 0.0)))
		return -arrival_position.normalized()
	if target_index < 0 or target_index >= PLANET_TARGETS.size():
		return Vector2.ZERO
	var transfer_data := interplanetary_transfer(target_index, parking_radius - EARTH_RADIUS)
	var direction_sign := float(transfer_data.get("direction", 1.0))
	var excess_speed := float(transfer_data.get("departure_excess_speed", 0.0))
	var eccentricity := 1.0 + parking_radius * excess_speed * excess_speed / EARTH_MU
	var bend_angle := atan(1.0 / sqrt(maxf(0.000001, eccentricity * eccentricity - 1.0)))
	var earth_rate := TAU / EARTH_ORBIT_PERIOD
	var earth_angle := earth_rate * current_time
	var earth_tangent := Vector2(-sin(earth_angle), cos(earth_angle))
	var asymptote_direction := earth_tangent * direction_sign
	var periapsis_tangent := asymptote_direction.rotated(direction_sign * bend_angle)
	return periapsis_tangent.rotated(-direction_sign * PI * 0.5).normalized()


static func arrival_capture_burn(position: Vector2, velocity: Vector2, body_mu: float, body_radius: float, target_altitude: float = 100000.0, minimum_safe_altitude: float = 1000.0) -> Dictionary:
	var radius := position.length()
	var target_radius := body_radius + maxf(minimum_safe_altitude, target_altitude)
	if radius < target_radius or body_mu <= 0.0:
		return {"valid": false}
	var capture := target_radius_burn(position, velocity, target_radius, body_mu)
	if not bool(capture.get("valid", false)) or float(capture.get("periapsis", 0.0)) < target_radius * 0.999:
		return {"valid": false}
	var transfer_axis := (radius + target_radius) * 0.5
	var transfer_speed_at_periapsis := sqrt(body_mu * (2.0 / target_radius - 1.0 / transfer_axis))
	var circular_speed := sqrt(body_mu / target_radius)
	var circularisation_delta_v := absf(circular_speed - transfer_speed_at_periapsis)
	var burn_vector: Vector2 = capture.burn_vector
	var desired_velocity: Vector2 = capture.desired_velocity
	return {
		"valid": true,
		"burn_vector": burn_vector,
		"delta_v": burn_vector.length(),
		"desired_velocity": desired_velocity,
		"periapsis": float(capture.periapsis),
		"apoapsis": float(capture.apoapsis),
		"safe_periapsis": target_radius,
		"target_radius": target_radius,
		"circularisation_delta_v": circularisation_delta_v,
		"total_delta_v": burn_vector.length() + circularisation_delta_v
	}

static func available_delta_v(design: Dictionary, active_stage_index: int = 0, active_fuel: float = -1.0) -> float:
	var stages: Array = design.get("stages", [])
	if stages.is_empty():
		return 0.0
	var stage_start := clampi(active_stage_index, 0, stages.size() - 1)
	var mass := float(design.get("payload_mass", 0.0))
	for i in range(stage_start, stages.size()):
		var stage: Dictionary = stages[i]
		var stage_fuel := float(stage.get("fuel_capacity", 0.0))
		if i == stage_start and active_fuel >= 0.0:
			stage_fuel = minf(stage_fuel, active_fuel)
		mass += float(stage.get("dry_mass", 0.0)) + stage_fuel
	var delta_v := 0.0
	for i in range(stage_start, stages.size()):
		var stage: Dictionary = stages[i]
		var stage_fuel := float(stage.get("fuel_capacity", 0.0))
		if i == stage_start and active_fuel >= 0.0:
			stage_fuel = minf(stage_fuel, active_fuel)
		var dry_mass := float(stage.get("dry_mass", 0.0))
		var flow := float(stage.get("flow", 0.0))
		var thrust := float(stage.get("vacuum_thrust", 0.0))
		var final_mass := mass - stage_fuel
		if stage_fuel > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > 0.0:
			delta_v += thrust / flow * log(mass / final_mass)
		mass = final_mass - dry_mass
	return delta_v


static func _simulated_target_state(target_index: int, time_seconds: float, body_states: Dictionary = {}) -> Dictionary:
	if not _is_valid_target_index(target_index):
		return {}
	var states := body_states if not body_states.is_empty() else PlanetarySystem.gravity_body_states(time_seconds)
	var target_name := target_body_name(target_index)
	for body_variant in states.get("surface_bodies", []):
		var body: Dictionary = body_variant
		if str(body.get("name", "")) == target_name:
			return body.duplicate()
	return {}


static func _segment_intersects_circle(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> bool:
	var segment := finish - start
	var length_squared := segment.length_squared()
	var fraction := 0.0
	if length_squared > 0.0:
		fraction = clampf((center - start).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start + segment * fraction
	return closest.distance_squared_to(center) <= radius * radius


static func _segment_intersects_circle_precise(start: PackedFloat64Array, finish: PackedFloat64Array, center: PackedFloat64Array, radius: float) -> bool:
	if start.size() < 2 or finish.size() < 2 or center.size() < 2:
		return false
	var segment_x: float = finish[0] - start[0]
	var segment_y: float = finish[1] - start[1]
	var length_squared := segment_x * segment_x + segment_y * segment_y
	var fraction := 0.0
	if length_squared > 0.0:
		fraction = clampf(((center[0] - start[0]) * segment_x + (center[1] - start[1]) * segment_y) / length_squared, 0.0, 1.0)
	var closest_x := start[0] + segment_x * fraction
	var closest_y := start[1] + segment_y * fraction
	var offset_x := closest_x - center[0]
	var offset_y := closest_y - center[1]
	return offset_x * offset_x + offset_y * offset_y <= radius * radius


static func simulated_transfer_search(start_position: Vector2, start_velocity: Vector2, start_time: float, target_index: int, maximum_delta_v: float, speed_priority: float = 0.0, coarse_search: bool = false, target_orbit_altitude: float = 100000.0) -> Dictionary:
	return simulated_transfer_search_precise(PackedFloat64Array([start_position.x, start_position.y]), start_velocity, start_time, target_index, maximum_delta_v, speed_priority, coarse_search, target_orbit_altitude)


static func simulated_transfer_search_precise(start_position_components: PackedFloat64Array, start_velocity: Vector2, start_time: float, target_index: int, maximum_delta_v: float, speed_priority: float = 0.0, coarse_search: bool = false, target_orbit_altitude: float = 100000.0) -> Dictionary:
	if start_position_components.size() < 2 or not _is_valid_target_index(target_index) or maximum_delta_v <= 0.0:
		return {"valid": false, "reason": "Invalid target, position or manoeuvre capability."}
	var initial_target := _simulated_target_state(target_index, start_time)
	if initial_target.is_empty():
		return {"valid": false, "reason": "Destination state unavailable."}
	var initial_target_components: PackedFloat64Array = initial_target.position_components
	var initial_dx: float = start_position_components[0] - initial_target_components[0]
	var initial_dy: float = start_position_components[1] - initial_target_components[1]
	var initial_distance := sqrt(initial_dx * initial_dx + initial_dy * initial_dy)
	var rough_speed := maxf(1500.0, minf(18000.0, start_velocity.length() + 5000.0))
	var nominal_time := clampf(maxf(initial_distance / rough_speed, 3.0 * 86400.0 if target_index <= -1 else 0.0), 3600.0, 30.0 * 365.25 * 86400.0)
	var durations: Array
	var magnitudes: Array
	var direction_count: int
	if target_index == -1:
		var lunar_transfer_time := float(hohmann_transfer(Vector2(start_position_components[0], start_position_components[1]).length(), EARTH_RADIUS + MOON_ORBIT_RADIUS).get("transfer_time", 5.0 * 86400.0))
		durations = [lunar_transfer_time * 0.8, lunar_transfer_time * 0.9, lunar_transfer_time, lunar_transfer_time * 1.1, lunar_transfer_time * 1.2]
		var lunar_reference_delta_v := float(hohmann_transfer(Vector2(start_position_components[0], start_position_components[1]).length(), EARTH_RADIUS + MOON_ORBIT_RADIUS).get("departure_delta_v", 0.0))
		magnitudes = [0.0]
		for offset in range(-150, 151, 10):
			var candidate_delta_v := maxf(0.0, lunar_reference_delta_v + float(offset))
			if candidate_delta_v <= maximum_delta_v:
				magnitudes.append(candidate_delta_v)
		direction_count = 1
	else:
		durations = [nominal_time * 0.75, nominal_time * 1.25, nominal_time * 2.5]
		magnitudes = [0.0, maximum_delta_v * 0.25, maximum_delta_v * 0.5, maximum_delta_v * 0.75, maximum_delta_v] if coarse_search else [0.0, maximum_delta_v * 0.2, maximum_delta_v * 0.4, maximum_delta_v * 0.6, maximum_delta_v]
		direction_count = 12 if coarse_search else 16
	var best_score := INF
	var best_plan: Dictionary = {}
	var fuel_weight := 1.0 - clampf(speed_priority, 0.0, 1.0)
	var time_weight := 1.0 - fuel_weight
	var maximum_flight_duration := 0.0
	for duration_value in durations:
		maximum_flight_duration = maxf(maximum_flight_duration, float(duration_value))
	for duration_value in durations:
		var flight_duration: float = float(duration_value)
		var minimum_steps := 360
		var maximum_steps := 1200 if coarse_search else 720
		var integration_steps := clampi(int(ceil(flight_duration / 21600.0)), minimum_steps, maximum_steps)
		var step_size := flight_duration / float(integration_steps)
		var gravity_states: Array[Dictionary] = []
		var target_states: Array[Dictionary] = []
		for step_index in range(integration_steps + 1):
			var sample_time := start_time + float(step_index) * step_size
			var sample_states: Dictionary = PlanetarySystem.gravity_body_states(sample_time)
			gravity_states.append(sample_states)
			target_states.append(_simulated_target_state(target_index, sample_time, sample_states))
		for direction_index in range(direction_count):
			var angle := start_velocity.angle() + TAU * float(direction_index) / float(direction_count)
			var burn_direction := Vector2(cos(angle), sin(angle))
			for magnitude_value in magnitudes:
				var departure_delta_v: float = float(magnitude_value)
				var position := start_position_components.duplicate()
				var velocity := start_velocity + burn_direction * departure_delta_v
				var closest_distance := INF
				var closest_relative_position := Vector2.ZERO
				var closest_relative_velocity := Vector2.ZERO
				var closest_target_position := PackedFloat64Array()
				var closest_time := flight_duration
				var closest_trajectory_index := 0
				var candidate_trajectory := PackedVector2Array([Vector2(position[0], position[1])])
				var collided := false
				for step_index in range(integration_steps):
					var initial_acceleration := PlanetarySystem.gravity_acceleration_from_precise_states(position, gravity_states[step_index])
					var half_velocity := velocity + initial_acceleration * (step_size * 0.5)
					var next_position := PackedFloat64Array([
						position[0] + half_velocity.x * step_size,
						position[1] + half_velocity.y * step_size
					])
					var final_acceleration := PlanetarySystem.gravity_acceleration_from_precise_states(next_position, gravity_states[step_index + 1])
					velocity = half_velocity + final_acceleration * (step_size * 0.5)
					var previous_position := position
					position = next_position
					candidate_trajectory.append(Vector2(position[0], position[1]))
					if _segment_intersects_circle_precise(previous_position, position, PackedFloat64Array([0.0, 0.0]), EARTH_RADIUS):
						collided = true
						break
					var bodies: Array = gravity_states[step_index + 1].get("bodies", [])
					for body in bodies:
						var body_position: Vector2 = body.get("position", Vector2.ZERO)
						var body_components: PackedFloat64Array = body.get("position_components", PackedFloat64Array([body_position.x, body_position.y]))
						if _segment_intersects_circle_precise(previous_position, position, body_components, float(body.get("radius", 0.0))):
							collided = true
							break
					if collided:
						break
					var target_state: Dictionary = target_states[step_index + 1]
					var target_position: PackedFloat64Array = target_state.position_components
					var relative_x: float = position[0] - target_position[0]
					var relative_y: float = position[1] - target_position[1]
					var distance_squared := relative_x * relative_x + relative_y * relative_y
					if distance_squared < closest_distance * closest_distance:
						closest_distance = sqrt(distance_squared)
						closest_relative_position = Vector2(relative_x, relative_y)
						closest_relative_velocity = velocity - Vector2(target_state.velocity)
						closest_target_position = target_position.duplicate()
						closest_time = float(step_index + 1) * step_size
						closest_trajectory_index = candidate_trajectory.size() - 1
				if collided:
					continue
				var target_soi := float(initial_target.soi)
				if closest_distance > target_soi:
					continue
				var target_mu := G * float(initial_target.mass)
				var target_safe_altitude := minimum_safe_orbit_altitude(str(initial_target.get("name", "")), float(initial_target.radius))
				var capture := arrival_capture_burn(closest_relative_position, closest_relative_velocity, target_mu, float(initial_target.radius), target_orbit_altitude, target_safe_altitude)
				if not bool(capture.get("valid", false)):
					continue
				var capture_delta_v := float(capture.get("total_delta_v", INF))
				var total_delta_v := departure_delta_v + capture_delta_v
				if total_delta_v > maximum_delta_v:
					continue
				var fuel_cost := total_delta_v / maxf(1.0, maximum_delta_v)
				var time_cost := closest_time / maxf(1.0, maximum_flight_duration)
				var candidate_score := fuel_cost * fuel_weight + time_cost * time_weight
				if candidate_score >= best_score:
					continue
				best_score = candidate_score
				var arrival_trajectory := PackedVector2Array()
				for trajectory_index in range(closest_trajectory_index + 1):
					arrival_trajectory.append(candidate_trajectory[trajectory_index])
				best_plan = {
					"valid": true,
					"departure_delta_v": departure_delta_v,
					"departure_direction": burn_direction,
					"capture_delta_v": capture_delta_v,
					"capture_direction": Vector2(capture.get("burn_vector", Vector2.ZERO)).normalized(),
					"total_delta_v": total_delta_v,
					"transfer_time": closest_time,
					"closest_approach": closest_distance,
					"arrival_speed": closest_relative_velocity.length(),
					"target_position": closest_target_position,
					"trajectory": arrival_trajectory,
					"target_soi": target_soi,
					"simulated_steps": integration_steps,
					"search_candidates": direction_count * magnitudes.size() * durations.size()
				}
	if best_plan.is_empty():
		return {
			"valid": false,
			"reason": "No sampled trajectory reached the destination sphere of influence within the available delta-v.",
			"search_candidates": direction_count * magnitudes.size() * durations.size()
		}
	return best_plan


static func scan_launch_windows(start_position: Vector2, start_velocity: Vector2, start_time: float, target_index: int, maximum_delta_v: float, speed_priority: float = 0.0, scan_days: int = 540, interval_days: int = 30, target_orbit_altitude: float = 100000.0) -> Dictionary:
	if target_index == -2 or not _is_valid_target_index(target_index) or maximum_delta_v <= 0.0:
		return {"valid": false, "reason": "Select a destination other than Earth and provide a positive manoeuvre budget."}
	var radius := start_position.length()
	var earth_minimum_orbit_altitude := minimum_safe_orbit_altitude("Earth", EARTH_RADIUS)
	if radius < EARTH_RADIUS + earth_minimum_orbit_altitude:
		return {"valid": false, "reason": "A stable Earth departure orbit is required."}
	var mu := G * PlanetarySystem.EARTH_MASS
	var initial_orbit := orbital_state(start_position, start_velocity, mu)
	if float(initial_orbit.get("eccentricity", 1.0)) > 0.05:
		return {"valid": false, "reason": "Launch-window scanning currently requires a near-circular Earth parking orbit."}
	var orbital_rate := sqrt(mu / pow(radius, 3.0))
	var best_window: Dictionary = {}
	var best_score := INF
	var dates_checked := 0
	var coarse_windows: Array[Dictionary] = []
	var samples := maxi(2, int(ceil(float(scan_days) / float(interval_days))) + 1)
	for sample_index in range(samples):
		var wait_days := mini(scan_days, sample_index * interval_days)
		var wait_seconds := float(wait_days) * 86400.0
		var rotation := orbital_rate * wait_seconds
		var future_position := start_position.rotated(rotation)
		var future_velocity := start_velocity.rotated(rotation)
		var plan := simulated_transfer_search(future_position, future_velocity, start_time + wait_seconds, target_index, maximum_delta_v, speed_priority, true, target_orbit_altitude)
		dates_checked += 1
		if not bool(plan.get("valid", false)):
			continue
		plan["departure_wait_days"] = wait_days
		plan["departure_time_seconds"] = start_time + wait_seconds
		coarse_windows.append(plan)
		var score := float(plan.get("total_delta_v", INF)) / maxf(1.0, maximum_delta_v) * (1.0 - clampf(speed_priority, 0.0, 1.0)) + float(plan.get("transfer_time", 0.0)) / (30.0 * 365.25 * 86400.0) * clampf(speed_priority, 0.0, 1.0)
		if score < best_score:
			best_score = score
			best_window = plan
	if best_window.is_empty():
		return {"valid": false, "reason": "No sampled departure date produced a feasible simulated transfer.", "dates_checked": dates_checked}
	var coarse_best_day := float(best_window.departure_wait_days)
	var refinement_spacing := maxf(1.0, float(interval_days) / 4.0)
	for refinement_index in range(-2, 3):
		var wait_days := clampf(coarse_best_day + float(refinement_index) * refinement_spacing, 0.0, float(scan_days))
		if absf(wait_days - coarse_best_day) < 0.01:
			continue
		var wait_seconds := wait_days * 86400.0
		var rotation := orbital_rate * wait_seconds
		var plan := simulated_transfer_search(start_position.rotated(rotation), start_velocity.rotated(rotation), start_time + wait_seconds, target_index, maximum_delta_v, speed_priority, true, target_orbit_altitude)
		dates_checked += 1
		if not bool(plan.get("valid", false)):
			continue
		plan["departure_wait_days"] = wait_days
		plan["departure_time_seconds"] = start_time + wait_seconds
		var score := float(plan.get("total_delta_v", INF)) / maxf(1.0, maximum_delta_v) * (1.0 - clampf(speed_priority, 0.0, 1.0)) + float(plan.get("transfer_time", 0.0)) / (30.0 * 365.25 * 86400.0) * clampf(speed_priority, 0.0, 1.0)
		if score < best_score:
			best_score = score
			best_window = plan
	var refined_best_day := float(best_window.departure_wait_days)
	for refinement_index in range(-2, 3):
		var wait_days := clampf(refined_best_day + float(refinement_index), 0.0, float(scan_days))
		if absf(wait_days - refined_best_day) < 0.01:
			continue
		var wait_seconds := wait_days * 86400.0
		var rotation := orbital_rate * wait_seconds
		var plan := simulated_transfer_search(start_position.rotated(rotation), start_velocity.rotated(rotation), start_time + wait_seconds, target_index, maximum_delta_v, speed_priority, true, target_orbit_altitude)
		dates_checked += 1
		if not bool(plan.get("valid", false)):
			continue
		plan["departure_wait_days"] = wait_days
		plan["departure_time_seconds"] = start_time + wait_seconds
		var score := float(plan.get("total_delta_v", INF)) / maxf(1.0, maximum_delta_v) * (1.0 - clampf(speed_priority, 0.0, 1.0)) + float(plan.get("transfer_time", 0.0)) / (30.0 * 365.25 * 86400.0) * clampf(speed_priority, 0.0, 1.0)
		if score < best_score:
			best_score = score
			best_window = plan
	var final_wait_days := float(best_window.departure_wait_days)
	var final_wait_seconds := final_wait_days * 86400.0
	var final_rotation := orbital_rate * final_wait_seconds
	var final_plan := simulated_transfer_search(start_position.rotated(final_rotation), start_velocity.rotated(final_rotation), start_time + final_wait_seconds, target_index, maximum_delta_v, speed_priority, false, target_orbit_altitude)
	if bool(final_plan.get("valid", false)):
		final_plan["departure_wait_days"] = final_wait_days
		final_plan["departure_time_seconds"] = start_time + final_wait_seconds
		best_window = final_plan
	return {"valid": true, "best": best_window, "windows": coarse_windows, "dates_checked": dates_checked, "refined": true}

static func target_orbit_report(position: Vector2, velocity: Vector2, altitude: float) -> Dictionary:
	var target_radius := EARTH_RADIUS + maxf(0.0, altitude)
	var state := orbital_state(position, velocity)
	var circular_burn := circularisation_burn(position, velocity)
	var transfer := hohmann_transfer(maxf(EARTH_RADIUS + 100000.0, position.length()), target_radius)
	return {
		"state": state,
		"target_radius": target_radius,
		"target_speed": circular_orbit_speed(target_radius),
		"circularisation": circular_burn,
		"transfer": transfer
	}
