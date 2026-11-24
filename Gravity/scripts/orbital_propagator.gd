extends RefCounted
class_name OrbitalPropagator

static func elements_from_state(position: Vector2, velocity: Vector2, mu: float, epoch: float = 0.0) -> Dictionary:
	var radius := position.length()
	if radius <= 0.0 or mu <= 0.0 or not is_finite(radius) or not is_finite(mu):
		return {}
	var speed_squared := velocity.length_squared()
	var specific_energy := speed_squared * 0.5 - mu / radius
	if specific_energy >= 0.0:
		return {}
	var semi_major_axis := -mu / (2.0 * specific_energy)
	var angular_momentum := position.cross(velocity)
	if absf(angular_momentum) <= 0.000001:
		return {}
	var eccentricity_vector := ((speed_squared - mu / radius) * position - position.dot(velocity) * velocity) / mu
	var eccentricity := eccentricity_vector.length()
	if eccentricity >= 1.0:
		return {}
	var periapsis := semi_major_axis * (1.0 - eccentricity)
	var apoapsis := semi_major_axis * (1.0 + eccentricity)
	var periapsis_direction := position.normalized()
	var mean_anomaly := 0.0
	if eccentricity > 0.000001:
		periapsis_direction = eccentricity_vector / eccentricity
		var cos_eccentric := clampf((1.0 - radius / semi_major_axis) / eccentricity, -1.0, 1.0)
		var sin_eccentric := position.dot(velocity) / (eccentricity * sqrt(mu * semi_major_axis))
		var eccentric_anomaly := atan2(sin_eccentric, cos_eccentric)
		mean_anomaly = eccentric_anomaly - eccentricity * sin(eccentric_anomaly)
	return {
		"semi_major_axis": semi_major_axis,
		"eccentricity": eccentricity,
		"periapsis": periapsis,
		"apoapsis": apoapsis,
		"periapsis_angle": periapsis_direction.angle(),
		"mean_anomaly_at_epoch": mean_anomaly,
		"mean_motion": sqrt(mu / pow(semi_major_axis, 3.0)),
		"epoch": epoch,
		"direction": 1.0 if angular_momentum > 0.0 else -1.0,
		"mu": mu
	}

static func propagate(elements: Dictionary, time_seconds: float) -> Dictionary:
	for key in ["semi_major_axis", "eccentricity", "periapsis_angle", "mean_anomaly_at_epoch", "mean_motion", "epoch", "direction", "mu"]:
		if not elements.has(key):
			return {}
	var semi_major_axis := float(elements.semi_major_axis)
	var eccentricity := float(elements.eccentricity)
	var mu := float(elements.mu)
	if semi_major_axis <= 0.0 or eccentricity < 0.0 or eccentricity >= 1.0 or mu <= 0.0:
		return {}
	var mean_anomaly := wrapf(float(elements.mean_anomaly_at_epoch) + float(elements.direction) * float(elements.mean_motion) * (time_seconds - float(elements.epoch)), -PI, PI)
	var eccentric_anomaly := mean_anomaly
	for _iteration in range(12):
		var residual := eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - mean_anomaly
		var derivative := 1.0 - eccentricity * cos(eccentric_anomaly)
		if absf(derivative) < 0.000000001:
			return {}
		var correction := residual / derivative
		eccentric_anomaly -= correction
		if absf(correction) < 0.0000000001:
			break
	var minor_factor := sqrt(1.0 - eccentricity * eccentricity)
	var local_position := Vector2(
		semi_major_axis * (cos(eccentric_anomaly) - eccentricity),
		semi_major_axis * minor_factor * sin(eccentric_anomaly)
	)
	var radius := local_position.length()
	if radius <= 0.0:
		return {}
	var velocity_scale := sqrt(mu * semi_major_axis) / radius
	var local_velocity := Vector2(
		-velocity_scale * sin(eccentric_anomaly),
		velocity_scale * minor_factor * cos(eccentric_anomaly)
	) * float(elements.direction)
	var rotation := float(elements.periapsis_angle)
	return {
		"position": local_position.rotated(rotation),
		"velocity": local_velocity.rotated(rotation)
	}

static func is_safe(elements: Dictionary, body_radius: float, minimum_altitude: float, maximum_radius: float) -> bool:
	if elements.is_empty():
		return false
	var periapsis := float(elements.get("periapsis", 0.0))
	var apoapsis := float(elements.get("apoapsis", INF))
	return periapsis > body_radius + minimum_altitude and apoapsis < maximum_radius
