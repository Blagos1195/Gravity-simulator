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

	var mars_transfer := FlightComputer.interplanetary_transfer(2, 200000.0)
	assert(bool(mars_transfer.get("valid", false)))
	assert(float(mars_transfer.get("departure_delta_v", 0.0)) > 0.0)
	assert(float(mars_transfer.get("arrival_delta_v", 0.0)) > 0.0)
	assert(float(mars_transfer.get("transfer_time", 0.0)) > 100.0 * 86400.0)
	var departure_wait := FlightComputer.departure_wait_time(2, 0.0)
	assert(departure_wait >= 0.0)
	assert(departure_wait < 900.0 * 86400.0)
	var mars_departure_direction := FlightComputer.departure_periapsis_direction(2, 0.0, radius)
	assert(absf(mars_departure_direction.length() - 1.0) < 0.000001)

	var moon_transfer := FlightComputer.interplanetary_transfer(-1, 200000.0)
	assert(bool(moon_transfer.get("valid", false)))
	assert(float(moon_transfer.get("departure_delta_v", 0.0)) > 0.0)
	assert(float(moon_transfer.get("arrival_delta_v", 0.0)) > 0.0)
	var moon_wait := FlightComputer.departure_wait_time(-1, 0.0, Vector2(radius, 0.0))
	assert(moon_wait >= 0.0)
	assert(moon_wait < 86400.0)
	var moon_departure_direction := FlightComputer.departure_periapsis_direction(-1, 0.0, radius)
	assert(absf(moon_departure_direction.length() - 1.0) < 0.000001)

	print("Flight computer orbital calculation tests passed.")
	quit()
