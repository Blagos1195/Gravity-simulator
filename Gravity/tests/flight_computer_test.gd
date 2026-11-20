extends SceneTree

const FlightComputer = preload("res://scripts/flight_computer.gd")

func _initialize() -> void:
	var radius := FlightComputer.EARTH_RADIUS + 200000.0
	var circular_speed := FlightComputer.circular_orbit_speed(radius)
	var state := FlightComputer.orbital_state(Vector2(radius, 0.0), Vector2(0.0, circular_speed))
	assert(bool(state.get("valid", false)))
	assert(bool(state.get("bound", false)))
	assert(absf(float(state.get("eccentricity", 1.0))) < 0.000001)
	assert(absf(float(state.get("apoapsis", 0.0)) - radius) < 1.0)
	assert(absf(float(state.get("periapsis", 0.0)) - radius) < 1.0)

	var burn := FlightComputer.circularisation_burn(Vector2(radius, 0.0), Vector2(0.0, circular_speed * 0.9))
	assert(float(burn.get("delta_v", 0.0)) > 0.0)

	var transfer := FlightComputer.hohmann_transfer(radius, FlightComputer.EARTH_RADIUS + 35786000.0)
	assert(bool(transfer.get("valid", false)))
	assert(float(transfer.get("total_delta_v", 0.0)) > 0.0)
	assert(float(transfer.get("transfer_time", 0.0)) > 0.0)

	print("Flight computer orbital calculation tests passed.")
	quit()
