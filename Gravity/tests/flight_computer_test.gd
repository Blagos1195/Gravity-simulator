extends SceneTree

const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")

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
	for target_index in range(7):
		var destination := FlightComputer.interplanetary_transfer(target_index, 200000.0)
		assert(bool(destination.get("valid", false)))
		assert(float(destination.get("departure_delta_v", 0.0)) > 0.0)
		assert(float(destination.get("arrival_delta_v", 0.0)) > 0.0)
		var target_wait := FlightComputer.departure_wait_time(target_index, 0.0)
		assert(target_wait >= 0.0 and target_wait < 900.0 * 86400.0)
		var target_direction := FlightComputer.departure_periapsis_direction(target_index, 0.0, radius)
		assert(absf(target_direction.length() - 1.0) < 0.000001)

	var mars_position := PlanetarySystem.planet_position_relative_to_earth("Mars", 86400.0 * 100.0)
	var mars_velocity := PlanetarySystem.planet_velocity_relative_to_earth("Mars", 86400.0 * 100.0)
	assert(mars_position.length() > 1.0e11)
	assert(mars_velocity.length() > 1000.0)
	assert(PlanetarySystem.planet_soi_radius("Mars") > 1.0e8)
	assert(PlanetarySystem.moon_soi_radius() > 1.0e7)
	assert(absf(PlanetarySystem.planetary_atmosphere_density("Mars", 0.0) - 0.020) < 0.000001)
	assert(absf(PlanetarySystem.planetary_atmosphere_density("Venus", 0.0) - 65.0) < 0.000001)
	assert(PlanetarySystem.planetary_atmosphere_density("Jupiter", 0.0) > 0.1)
	assert(PlanetarySystem.planetary_atmosphere_density("Mercury", 0.0) == 0.0)
	assert(PlanetarySystem.planetary_atmosphere_density("Mars", 200000.0) == 0.0)
	var simulation: Variant = SimulationView.new()
	simulation.sim_time = 86400.0 * 100.0
	var mars_surface_position_for_view := mars_position + Vector2(3.3895e6 + 150000.0, 0.0)
	var mars_local_body: Dictionary = simulation._nearest_body_state(mars_surface_position_for_view)
	assert(str(mars_local_body.get("name", "")) == "Mars")
	assert(absf(float(mars_local_body.get("distance", 0.0)) - (3.3895e6 + 150000.0)) < 1.0)
	var moon_surface_position := PlanetarySystem.moon_position(simulation.sim_time) + Vector2(PlanetarySystem.MOON_RADIUS + 100000.0, 0.0)
	var moon_local_body: Dictionary = simulation._nearest_body_state(moon_surface_position)
	assert(str(moon_local_body.get("name", "")) == "Moon")
	var earth_local_body: Dictionary = simulation._nearest_body_state(Vector2(0.0, -FlightComputer.EARTH_RADIUS - 2.0))
	assert(str(earth_local_body.get("name", "")) == "Earth")

	var mars_surface_position := mars_position + Vector2(3.3895e6, 0.0)
	var mars_surface_gravity := PlanetarySystem.gravity_acceleration(mars_surface_position, 86400.0 * 100.0)
	assert(mars_surface_gravity.length() > 1.0)

	var mars_mu := FlightComputer.G * 6.4171e23
	var arrival_position := Vector2(1.0e7, 0.0)
	var arrival_velocity := Vector2(500.0, 7000.0)
	var capture := FlightComputer.arrival_capture_burn(arrival_position, arrival_velocity, mars_mu, 3.3895e6)
	assert(bool(capture.get("valid", false)))
	assert(float(capture.get("delta_v", 0.0)) > 0.0)
	var captured_orbit := FlightComputer.orbital_state(arrival_position, capture.desired_velocity, mars_mu)
	assert(bool(captured_orbit.get("bound", false)))
	assert(float(captured_orbit.get("eccentricity", 1.0)) < 0.000001)
	assert(absf(float(captured_orbit.get("apoapsis", 0.0)) - arrival_position.length()) < 1.0)
	assert(float(captured_orbit.get("periapsis", 0.0)) > 3.3895e6 + 50000.0)
	assert(not bool(FlightComputer.arrival_capture_burn(Vector2(3.4e6, 0.0), Vector2.ZERO, mars_mu, 3.3895e6).get("valid", true)))

	var moon_transfer := FlightComputer.interplanetary_transfer(-1, 200000.0)
	assert(bool(moon_transfer.get("valid", false)))
	assert(float(moon_transfer.get("departure_delta_v", 0.0)) > 0.0)
	assert(float(moon_transfer.get("arrival_delta_v", 0.0)) > 0.0)
	var moon_wait := FlightComputer.departure_wait_time(-1, 0.0, Vector2(radius, 0.0))
	assert(moon_wait >= 0.0)
	assert(moon_wait < 86400.0)
	var moon_departure_direction := FlightComputer.departure_periapsis_direction(-1, 0.0, radius)
	assert(absf(moon_departure_direction.length() - 1.0) < 0.000001)


	var sample_design := {
		"payload_mass": 1000.0,
		"stages": [
			{"dry_mass": 1000.0, "fuel_capacity": 9000.0, "vacuum_thrust": 100000.0, "flow": 10.0},
			{"dry_mass": 500.0, "fuel_capacity": 4000.0, "vacuum_thrust": 50000.0, "flow": 5.0}
		]
	}
	var full_vehicle_delta_v := FlightComputer.available_delta_v(sample_design)
	var partial_vehicle_delta_v := FlightComputer.available_delta_v(sample_design, 0, 4500.0)
	var upper_stage_delta_v := FlightComputer.available_delta_v(sample_design, 1, 4000.0)
	assert(full_vehicle_delta_v > partial_vehicle_delta_v)
	assert(partial_vehicle_delta_v > 0.0)
	assert(upper_stage_delta_v > 0.0)
	assert(upper_stage_delta_v < full_vehicle_delta_v)

	print("Flight computer orbital calculation tests passed.")
	quit()
