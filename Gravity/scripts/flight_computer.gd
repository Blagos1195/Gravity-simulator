extends RefCounted
class_name FlightComputer

const G := 6.67430e-11
const EARTH_MU := 3.986004418e14
const EARTH_RADIUS := 6.371e6
const MOON_ORBIT_RADIUS := 3.844e8
const SUN_MU := 1.32712440018e20
const EARTH_ORBIT_RADIUS := 1.495978707e11
const EARTH_ORBIT_PERIOD := 365.256363004 * 86400.0
const PLANET_TARGETS := [
	{"name": "Mercury", "radius": 5.7909e10, "period_days": 87.969},
	{"name": "Venus", "radius": 1.0821e11, "period_days": 224.701},
	{"name": "Mars", "radius": 2.2794e11, "period_days": 686.980},
	{"name": "Jupiter", "radius": 7.7857e11, "period_days": 4332.59},
	{"name": "Saturn", "radius": 1.4335e12, "period_days": 10759.22},
	{"name": "Uranus", "radius": 2.8725e12, "period_days": 30688.5},
	{"name": "Neptune", "radius": 4.4951e12, "period_days": 60182.0}
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
		return {
			"valid": true,
			"name": "Moon",
			"departure_delta_v": float(lunar.departure_delta_v),
			"arrival_delta_v": float(lunar.arrival_delta_v),
			"total_delta_v": float(lunar.total_delta_v),
			"transfer_time": float(lunar.transfer_time),
			"direction": 1.0,
			"phase_angle": 0.0,
			"arrival_excess_speed": 0.0
		}
	if target_index < 0 or target_index >= PLANET_TARGETS.size():
		return {"valid": false}
	var target: Dictionary = PLANET_TARGETS[target_index]
	var target_radius := float(target.radius)
	var transfer_axis := (EARTH_ORBIT_RADIUS + target_radius) * 0.5
	var earth_speed := sqrt(SUN_MU / EARTH_ORBIT_RADIUS)
	var target_speed := sqrt(SUN_MU / target_radius)
	var transfer_departure_speed := sqrt(SUN_MU * (2.0 / EARTH_ORBIT_RADIUS - 1.0 / transfer_axis))
	var transfer_arrival_speed := sqrt(SUN_MU * (2.0 / target_radius - 1.0 / transfer_axis))
	var departure_excess := absf(transfer_departure_speed - earth_speed)
	var arrival_excess := absf(target_speed - transfer_arrival_speed)
	var parking_radius := EARTH_RADIUS + maxf(70000.0, parking_altitude)
	var parking_speed := circular_orbit_speed(parking_radius)
	var escape_speed := sqrt(departure_excess * departure_excess + 2.0 * EARTH_MU / parking_radius)
	var injection_delta_v := escape_speed - parking_speed
	var transfer_time := PI * sqrt(pow(transfer_axis, 3.0) / SUN_MU)
	var target_mean_motion := TAU / (float(target.period_days) * 86400.0)
	var phase_angle := wrapf(PI - target_mean_motion * transfer_time, -PI, PI)
	return {
		"valid": true,
		"name": str(target.name),
		"departure_delta_v": injection_delta_v,
		"arrival_delta_v": arrival_excess,
		"total_delta_v": injection_delta_v + arrival_excess,
		"transfer_time": transfer_time,
		"departure_excess_speed": departure_excess,
		"arrival_excess_speed": arrival_excess,
		"direction": 1.0 if transfer_departure_speed >= earth_speed else -1.0,
		"phase_angle": phase_angle,
		"transfer_semi_major_axis": transfer_axis
	}

static func departure_wait_time(target_index: int, current_time: float, parking_position: Vector2 = Vector2.ZERO) -> float:
	if target_index == -1:
		if parking_position.length() <= EARTH_RADIUS:
			return 0.0
		var transfer := hohmann_transfer(parking_position.length(), EARTH_RADIUS + MOON_ORBIT_RADIUS)
		var moon_rate := TAU / (27.321661 * 86400.0)
		var parking_rate := sqrt(EARTH_MU / pow(parking_position.length(), 3.0))
		var current_phase := wrapf(moon_rate * current_time - parking_position.angle(), -PI, PI)
		var desired_phase := wrapf(PI - moon_rate * float(transfer.get("transfer_time", 0.0)), -PI, PI)
		var relative_rate := moon_rate - parking_rate
		var phase_difference := wrapf(desired_phase - current_phase, -PI, PI)
		var wait := phase_difference / relative_rate
		return fposmod(wait, TAU / absf(relative_rate))
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
	var transfer := interplanetary_transfer(target_index)
	var desired_phase := float(transfer.get("phase_angle", 0.0))
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
