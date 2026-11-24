extends RefCounted
class_name SpaceObjectPhysics

static func swept_circle_contact(
	start_a: Vector2,
	end_a: Vector2,
	radius_a: float,
	start_b: Vector2,
	end_b: Vector2,
	radius_b: float
) -> Dictionary:
	var relative_start := start_a - start_b
	var relative_motion := (end_a - start_a) - (end_b - start_b)
	var motion_length_squared := relative_motion.length_squared()
	var time_fraction := 0.0
	if motion_length_squared > 0.000000001:
		time_fraction = clampf(-relative_start.dot(relative_motion) / motion_length_squared, 0.0, 1.0)
	var separation := relative_start + relative_motion * time_fraction
	var combined_radius := maxf(0.0, radius_a) + maxf(0.0, radius_b)
	if separation.length_squared() > combined_radius * combined_radius:
		return {}
	var normal := separation.normalized()
	if normal.length_squared() < 0.5:
		normal = relative_motion.normalized()
	if normal.length_squared() < 0.5:
		normal = Vector2.RIGHT
	var position_a := start_a.lerp(end_a, time_fraction)
	var position_b := start_b.lerp(end_b, time_fraction)
	return {
		"time_fraction": time_fraction,
		"normal": normal,
		"position_a": position_a,
		"position_b": position_b,
		"impact_point": (position_a + position_b) * 0.5,
		"separation": separation.length(),
		"penetration": maxf(0.0, combined_radius - separation.length())
	}
