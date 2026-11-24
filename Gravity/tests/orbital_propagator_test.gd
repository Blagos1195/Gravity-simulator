extends SceneTree

const OrbitalPropagator = preload("res://scripts/orbital_propagator.gd")

func _initialize() -> void:
	_validate_circular_orbit()
	_validate_eccentric_orbit()
	print("Orbital propagator tests passed.")
	quit()

func _validate_circular_orbit() -> void:
	var mu := 3.986004418e14
	var radius := 7.0e6
	var speed := sqrt(mu / radius)
	var elements := OrbitalPropagator.elements_from_state(Vector2(radius, 0.0), Vector2(0.0, speed), mu, 120.0)
	assert(not elements.is_empty())
	var period := TAU * sqrt(pow(radius, 3.0) / mu)
	var initial := OrbitalPropagator.propagate(elements, 120.0)
	var after_period := OrbitalPropagator.propagate(elements, 120.0 + period)
	assert(Vector2(initial.position).distance_to(Vector2(radius, 0.0)) < 0.01)
	print("CIRCULAR ", elements, " initial=", initial, " after=", after_period)
	assert(Vector2(after_period.position).distance_to(Vector2(radius, 0.0)) < 0.1)
	assert(Vector2(after_period.velocity).distance_to(Vector2(0.0, speed)) < 0.0001)

func _validate_eccentric_orbit() -> void:
	var mu := 3.986004418e14
	var position := Vector2(7.0e6, 0.0)
	var velocity := Vector2(0.0, sqrt(mu / position.x) * 0.8)
	var elements := OrbitalPropagator.elements_from_state(position, velocity, mu, 0.0)
	assert(not elements.is_empty())
	assert(float(elements.eccentricity) > 0.0 and float(elements.eccentricity) < 1.0)
	var propagated := OrbitalPropagator.propagate(elements, 3600.0)
	assert(not propagated.is_empty())
	var recovered := OrbitalPropagator.elements_from_state(propagated.position, propagated.velocity, mu, 3600.0)
	print("ECCENTRIC ", elements, " propagated=", propagated, " recovered=", recovered)
	assert(not recovered.is_empty())
	assert(absf(float(recovered.semi_major_axis) - float(elements.semi_major_axis)) < 0.1)
	assert(absf(float(recovered.eccentricity) - float(elements.eccentricity)) < 0.00000001)
