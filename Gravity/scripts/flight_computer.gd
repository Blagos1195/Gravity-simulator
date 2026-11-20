extends RefCounted
class_name FlightComputer

const PlanetarySystem = preload("res://scripts/planetary_system.gd")

const G := 6.67430e-11
const EARTH_MU := 3.986004418e14
const EARTH_RADIUS := 6.371e6
const MOON_ORBIT_RADIUS := 3.844e8
const MOON_MASS := 7.342e22
const MOON_RADIUS := 1.7374e6
const MOON_MU := G * MOON_MASS
const SUN_MU := 1.32712440018e20
const EARTH_ORBIT_RADIUS := 1.495978707e11
const EARTH_ORBIT_PERIOD := 365.256363004 * 86400.0
const PLANET_TARGETS := [
	{"name": "Mercury", "radius": 5.7909e10, "planet_radius": 2.4397e6, "mass": 3.3011e23, "period_days": 87.969},
	{"name": "Venus", "radius": 1.0821e11, "planet_radius": 6.0518e6, "mass": 4.8675e24, "period_days": 224.701},
	{"name": "Mars", "radius": 2.2794e11, "planet_radius": 3.3895e6, "mass": 6.4171e23, "period_days": 686.980},
	{"name": "Jupiter", "radius": 7.7857e11, "planet_radius": 6.9911e7, "mass": 1.8982e27, "period_days": 4332.59},
	{"name": "Saturn", "radius": 1.4335e12, "planet_radius": 5.8232e7, "mass": 5.6834e26, "period_days": 10759.22},
	{"name": "Uranus", "radius": 2.8725e12, "planet_radius": 2.5362e7, "mass": 8.6810e25, "period_days": 30688.5},
	{"name": "Neptune", "radius": 4.4951e12, "planet_radius": 2.4622e7, "mass": 1.0241e26, "period_days": 60182.0}
]

static func orbital_state(position: Vector2, velocity: Vector2, mu: float = EARTH_MU) -> Dictionary:
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

static func circular_orbit_speed(radius: float, mu: float = EARTH_MU) -> float:
	if radius <= 0.0 or mu <= 0.0:
		return 0.0
	return sqrt(mu / radius)

static func circularisation_burn(position: Vector2, velocity: Vector2, prograde: bool = true, mu: float = EARTH_MU) -> Dictionary:
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

static func hohmann_transfer(origin_radius: float, target_radius: float, mu: float = EARTH_MU) -> Dictionary:
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
	if target_index == -1:
		if parking_position.length() <= EARTH_RADIUS:
			return 0.0
		var lunar_window_transfer := hohmann_transfer(parking_position.length(), EARTH_RADIUS + MOON_ORBIT_RADIUS)
		var lunar_rate := TAU / (27.321661 * 86400.0)
		var parking_rate := sqrt(EARTH_MU / pow(parking_position.length(), 3.0))
		var lunar_current_phase := wrapf(lunar_rate * current_time - parking_position.angle(), -PI, PI)
		var lunar_desired_phase := wrapf(PI - lunar_rate * float(lunar_window_transfer.get("transfer_time", 0.0)), -PI, PI)
		var lunar_relative_rate := lunar_rate - parking_rate
		var lunar_phase_difference := wrapf(lunar_desired_phase - lunar_current_phase, -PI, PI)
		var lunar_wait := lunar_phase_difference / lunar_relative_rate
		return fposmod(lunar_wait, TAU / absf(lunar_relative_rate))
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
	if target_index == -1:
		var transfer := hohmann_transfer(parking_radius, EARTH_RADIUS + MOON_ORBIT_RADIUS)
		var moon_rate := TAU / (27.321661 * 86400.0)
		var arrival_angle := moon_rate * (current_time + float(transfer.get("transfer_time", 0.0)))
		return -Vector2(cos(arrival_angle), sin(arrival_angle))
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


static func arrival_capture_burn(position: Vector2, velocity: Vector2, body_mu: float, body_radius: float) -> Dictionary:
	var radius := position.length()
	var safe_periapsis := body_radius + 100000.0
	if radius <= safe_periapsis or body_mu <= 0.0:
		return {"valid": false}
	var angular_momentum := position.cross(velocity)
	var tangent := Vector2(-position.y, position.x).normalized()
	var direction := 1.0 if angular_momentum >= 0.0 else -1.0
	var desired_apoapsis := radius
	var desired_speed := sqrt(body_mu / radius)
	var desired_velocity := tangent * direction * desired_speed
	var burn_vector := desired_velocity - velocity
	return {
		"valid": true,
		"burn_vector": burn_vector,
		"delta_v": burn_vector.length(),
		"desired_velocity": desired_velocity,
		"periapsis": radius,
		"apoapsis": desired_apoapsis,
		"safe_periapsis": safe_periapsis
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


static func _simulated_target_state(target_index: int, time_seconds: float) -> Dictionary:
	if target_index == -1:
		return {
			"position": PlanetarySystem.moon_position(time_seconds),
			"velocity": PlanetarySystem.moon_velocity(time_seconds),
			"mass": PlanetarySystem.MOON_MASS,
			"radius": PlanetarySystem.MOON_RADIUS,
			"soi": PlanetarySystem.moon_soi_radius()
		}
	if target_index < 0 or target_index >= PLANET_TARGETS.size():
		return {}
	var target: Dictionary = PLANET_TARGETS[target_index]
	var target_name := str(target.get("name", ""))
	return {
		"position": PlanetarySystem.planet_position_relative_to_earth(target_name, time_seconds),
		"velocity": PlanetarySystem.planet_velocity_relative_to_earth(target_name, time_seconds),
		"mass": float(target.get("mass", 0.0)),
		"radius": float(target.get("planet_radius", 0.0)),
		"soi": PlanetarySystem.planet_soi_radius(target_name)
	}


static func simulated_transfer_search(start_position: Vector2, start_velocity: Vector2, start_time: float, target_index: int, maximum_delta_v: float) -> Dictionary:
	if target_index < -1 or target_index >= PLANET_TARGETS.size() or maximum_delta_v <= 0.0:
		return {"valid": false, "reason": "Invalid target or no remaining manoeuvre capability."}
	var initial_target := _simulated_target_state(target_index, start_time)
	if initial_target.is_empty():
		return {"valid": false, "reason": "Destination state unavailable."}
	var initial_distance := start_position.distance_to(Vector2(initial_target.position))
	var rough_speed := maxf(1500.0, minf(18000.0, start_velocity.length() + 5000.0))
	var nominal_time := clampf(maxf(initial_distance / rough_speed, 3.0 * 86400.0 if target_index == -1 else 0.0), 3600.0, 30.0 * 365.25 * 86400.0)
	var durations := [nominal_time * 0.65, nominal_time, nominal_time * 1.5, nominal_time * 2.5]
	var magnitudes := [0.0, maximum_delta_v * 0.1, maximum_delta_v * 0.2, maximum_delta_v * 0.35, maximum_delta_v * 0.5, maximum_delta_v * 0.65, maximum_delta_v * 0.8, maximum_delta_v]
	var direction_count := 24
	var integration_steps := 720
	var best_score := INF
	var best_plan: Dictionary = {}
	for duration_value in durations:
		var flight_duration: float = float(duration_value)
		for direction_index in range(direction_count):
			var angle := TAU * float(direction_index) / float(direction_count)
			var burn_direction := Vector2(cos(angle), sin(angle))
			for magnitude_value in magnitudes:
				var departure_delta_v: float = float(magnitude_value)
				var position := start_position
				var velocity := start_velocity + burn_direction * departure_delta_v
				var step_size := flight_duration / float(integration_steps)
				var closest_distance := INF
				var closest_relative_position := Vector2.ZERO
				var closest_relative_velocity := Vector2.ZERO
				var closest_time := flight_duration
				for step_index in range(integration_steps):
					var current_time := start_time + float(step_index) * step_size
					var initial_acceleration := PlanetarySystem.gravity_acceleration(position, current_time)
					var half_velocity := velocity + initial_acceleration * (step_size * 0.5)
					var next_position := position + half_velocity * step_size
					var final_acceleration := PlanetarySystem.gravity_acceleration(next_position, current_time + step_size)
					velocity = half_velocity + final_acceleration * (step_size * 0.5)
					position = next_position
					var target_state := _simulated_target_state(target_index, current_time + step_size)
					var target_position: Vector2 = target_state.get("position", Vector2.ZERO)
					var target_velocity: Vector2 = target_state.get("velocity", Vector2.ZERO)
					var relative_position: Vector2 = position - target_position
					var distance := relative_position.length()
					if distance < closest_distance:
						closest_distance = distance
						closest_relative_position = relative_position
						closest_relative_velocity = velocity - target_velocity
						closest_time = float(step_index + 1) * step_size
				var target_soi := float(initial_target.soi)
				if closest_distance > target_soi:
					continue
				var target_mu := G * float(initial_target.mass)
				var capture := arrival_capture_burn(closest_relative_position, closest_relative_velocity, target_mu, float(initial_target.radius))
				if not bool(capture.get("valid", false)):
					continue
				var capture_delta_v := float(capture.get("delta_v", INF))
				var total_delta_v := departure_delta_v + capture_delta_v
				if total_delta_v > maximum_delta_v or total_delta_v >= best_score:
					continue
				best_score = total_delta_v
				best_plan = {
					"valid": true,
					"departure_delta_v": departure_delta_v,
					"departure_direction": burn_direction,
					"capture_delta_v": capture_delta_v,
					"capture_direction": capture.get("direction", Vector2.ZERO),
					"total_delta_v": total_delta_v,
					"transfer_time": closest_time,
					"closest_approach": closest_distance,
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
