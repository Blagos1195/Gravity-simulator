extends RefCounted
class_name FlightComputer

const G := 6.67430e-11
const EARTH_MU := 3.986004418e14
const EARTH_RADIUS := 6.371e6
const MOON_ORBIT_RADIUS := 3.844e8

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
