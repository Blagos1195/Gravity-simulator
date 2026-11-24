extends SceneTree

const SpaceObjectPhysics = preload("res://scripts/space_object_physics.gd")

func _initialize() -> void:
	var crossing := SpaceObjectPhysics.swept_circle_contact(
		Vector2(-10.0, 0.0),
		Vector2(10.0, 0.0),
		1.0,
		Vector2(10.0, 0.0),
		Vector2(-10.0, 0.0),
		1.0
	)
	assert(not crossing.is_empty(), "Fast crossing objects passed through each other")
	assert(is_equal_approx(float(crossing.time_fraction), 0.5))
	assert(is_equal_approx(float(crossing.penetration), 2.0))
	var miss := SpaceObjectPhysics.swept_circle_contact(
		Vector2(-10.0, 4.0),
		Vector2(10.0, 4.0),
		1.0,
		Vector2(10.0, 0.0),
		Vector2(-10.0, 0.0),
		1.0
	)
	assert(miss.is_empty(), "Objects outside their combined collision radii collided")
	var stationary_overlap := SpaceObjectPhysics.swept_circle_contact(
		Vector2.ZERO,
		Vector2.ZERO,
		2.0,
		Vector2(1.0, 0.0),
		Vector2(1.0, 0.0),
		2.0
	)
	assert(not stationary_overlap.is_empty(), "Stationary overlapping objects were not detected")
	print("Spacecraft collision geometry tests passed.")
	quit()
