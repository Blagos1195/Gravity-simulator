extends SceneTree

const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RoutePlanner = preload("res://scripts/route_planner.gd")

func _initialize() -> void:
	var radius := FlightComputer.EARTH_RADIUS + 200000.0
	var circular_speed := FlightComputer.circular_orbit_speed(radius)
	var state := FlightComputer.orbital_state(Vector2(radius, 0.0), Vector2(0.0, circular_speed))
	assert(bool(state.get("valid", false)))
	assert(bool(state.get("bound", false)))
	assert(absf(float(state.get("eccentricity", 1.0))) < 0.000001)
	assert(absf(float(state.get("apoapsis", 0.0)) - radius) < 1.0)
	assert(absf(float(state.get("periapsis", 0.0)) - radius) < 1.0)

	var burn := FlightComputer.circularisation_burn(Vector2(radius, 0.0), Vector2(120.0, circular_speed * 0.9))
	assert(float(burn.get("delta_v", 0.0)) > 0.0)
	var corrected_orbit := FlightComputer.orbital_state(Vector2(radius, 0.0), Vector2(120.0, circular_speed * 0.9) + Vector2(burn.get("burn_vector", Vector2.ZERO)))
	assert(bool(corrected_orbit.get("bound", false)))
	assert(absf(float(corrected_orbit.get("eccentricity", 1.0))) < 0.000001)
	assert(float(corrected_orbit.get("periapsis", 0.0)) > FlightComputer.EARTH_RADIUS + 70000.0)
	assert(FlightComputer._segment_intersects_circle(Vector2(-10.0, 0.0), Vector2(10.0, 0.0), Vector2.ZERO, 2.0))
	assert(FlightComputer._segment_intersects_circle(Vector2(0.0, 0.0), Vector2(0.0, 0.0), Vector2.ZERO, 2.0))
	assert(not FlightComputer._segment_intersects_circle(Vector2(-10.0, 3.0), Vector2(10.0, 3.0), Vector2.ZERO, 2.0))
	var gravity_snapshot := PlanetarySystem.gravity_body_states(0.0)
	assert(gravity_snapshot.get("bodies", []).size() == 9)
	var snapshot_gravity := PlanetarySystem.gravity_acceleration_from_states(Vector2(0.0, -radius), gravity_snapshot)
	assert(snapshot_gravity.is_finite())

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

	var mars_surface_state: Dictionary = simulation._surface_body_state("Mars")
	simulation.rocket_position = mars_surface_state.position + Vector2(float(mars_surface_state.radius) + 0.1, 0.0)
	simulation.velocity = mars_surface_state.velocity + Vector2(0.0, float(mars_surface_state.radius) * float(mars_surface_state.rotation_rate))
	simulation.throttle = 0.0
	simulation._handle_body_contact()
	assert(simulation.landed)
	assert(simulation.landed_body_name == "Mars")

	var crash_sim: Variant = SimulationView.new()
	crash_sim.sim_time = simulation.sim_time
	var crash_body: Dictionary = crash_sim._surface_body_state("Mars")
	crash_sim.rocket_position = crash_body.position + Vector2(float(crash_body.radius) + 0.1, 0.0)
	crash_sim.velocity = crash_body.velocity + Vector2(1000.0, 0.0)
	crash_sim._handle_body_contact()
	assert(crash_sim.crashed)
	assert(not crash_sim.landed)

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

	var earth_destination := FlightComputer._simulated_target_state(-2, 0.0)
	var earth_destination_position: Vector2 = earth_destination.get("position", Vector2.ONE)
	assert(is_equal_approx(earth_destination_position.length(), 0.0))
	assert(is_equal_approx(float(earth_destination.get("mass", 0.0)), PlanetarySystem.EARTH_MASS))
	var earth_orbit_radius := PlanetarySystem.EARTH_RADIUS + 3000000.0
	var earth_orbit_speed := FlightComputer.circular_orbit_speed(earth_orbit_radius)
	var local_transfer_plan := FlightComputer.simulated_transfer_search(Vector2(0.0, -earth_orbit_radius), Vector2(earth_orbit_speed, 0.0), 0.0, -2, 5000.0)
	assert(bool(local_transfer_plan.get("valid", false)))
	assert(float(local_transfer_plan.get("total_delta_v", INF)) < 100.0)
	var invalid_transfer_plan := FlightComputer.simulated_transfer_search(Vector2.ZERO, Vector2.ZERO, 0.0, -3, 5000.0)
	assert(not bool(invalid_transfer_plan.get("valid", true)))

	var manoeuvre_sim: Variant = SimulationView.new()
	manoeuvre_sim.set_rocket_design(RocketDesign.create_default())
	var manoeuvre_radius: float = FlightComputer.EARTH_RADIUS + 200000.0
	var manoeuvre_speed: float = FlightComputer.circular_orbit_speed(manoeuvre_radius)
	manoeuvre_sim.landed = false
	manoeuvre_sim.rocket_position = Vector2(0.0, -manoeuvre_radius)
	manoeuvre_sim.velocity = Vector2(manoeuvre_speed, 0.0)
	manoeuvre_sim.rotation_angle = PI * 0.5
	manoeuvre_sim.autopilot_enabled = true
	manoeuvre_sim.guidance_enabled = true
	manoeuvre_sim.autopilot_phase = "MANEUVER_BURN"
	manoeuvre_sim.autopilot_burn_direction = Vector2.RIGHT
	manoeuvre_sim.autopilot_burn_remaining = 0.000001
	manoeuvre_sim._update_guidance(0.01)
	assert(manoeuvre_sim.thrust_key_down)
	manoeuvre_sim._physics_step(0.01)
	assert(manoeuvre_sim.autopilot_phase == "COMPLETE")
	assert(manoeuvre_sim.autopilot_complete)
	var route_sim: Variant = SimulationView.new()
	route_sim.set_rocket_design(RocketDesign.create_default())
	route_sim.landed = false
	route_sim.rocket_position = Vector2(0.0, -manoeuvre_radius)
	route_sim.velocity = Vector2(manoeuvre_speed, 0.0)
	route_sim.rotation_angle = PI * 0.5
	route_sim.autopilot_enabled = true
	route_sim.guidance_enabled = true
	route_sim.autopilot_route_nodes = [
		{"time": 10.0, "prograde": 5.0, "radial": 0.0},
		{"time": 20.0, "prograde": 5.0, "radial": 0.0}
	]
	route_sim.autopilot_phase = "ROUTE_COAST"
	route_sim._update_guidance(0.01)
	assert(route_sim.autopilot_phase == "ROUTE_COAST")
	route_sim.sim_time = 10.0
	route_sim._update_guidance(0.01)
	assert(route_sim.autopilot_phase == "ROUTE_BURN")
	route_sim._physics_step(2.0)
	assert(route_sim.autopilot_phase == "ROUTE_COAST")
	assert(route_sim.autopilot_route_node_index == 1)
	route_sim.sim_time = 20.0
	route_sim._update_guidance(0.01)
	assert(route_sim.autopilot_phase == "ROUTE_BURN")
	route_sim.free()

	var planner_sim: Variant = SimulationView.new()
	planner_sim.set_rocket_design(RocketDesign.create_default())
	planner_sim.landed = false
	planner_sim.rocket_position = Vector2(0.0, -manoeuvre_radius)
	planner_sim.velocity = Vector2(manoeuvre_speed, 0.0)
	var route_planner_window: Window = RoutePlanner.new()
	root.add_child(route_planner_window)
	route_planner_window.configure(planner_sim, RocketDesign.create_default())
	route_planner_window._add_node()
	route_planner_window.prograde_input.value = 5.0
	assert(route_planner_window.nodes.size() == 1)
	assert(route_planner_window.orbit_plot.planned_path.size() > 1)
	route_planner_window._send_to_autopilot()
	assert(planner_sim.autopilot_phase == "ROUTE_COAST")
	assert(planner_sim.autopilot_route_nodes.size() == 1)
	route_planner_window.free()
	planner_sim.free()

	var moon_velocity_time := 86400.0 * 123.0
	var analytical_moon_velocity: Vector2 = PlanetarySystem.moon_velocity(moon_velocity_time)
	var numerical_moon_velocity: Vector2 = (PlanetarySystem.moon_position(moon_velocity_time + 1.0) - PlanetarySystem.moon_position(moon_velocity_time - 1.0)) / 2.0
	assert(analytical_moon_velocity.distance_to(numerical_moon_velocity) < 0.001)
	assert(gravity_snapshot.get("surface_bodies", []).size() == 9)
	var cached_simulation: Variant = SimulationView.new()
	var cached_moon: Dictionary = cached_simulation._surface_body_state("Moon")
	var interpolated_states: Dictionary = cached_simulation._ephemeris_states_at(5.0)
	var interpolated_moon: Dictionary = interpolated_states.get("surface_bodies", [])[1]
	var expected_moon_position: Vector2 = cached_moon.position + cached_moon.velocity * 5.0
	assert(Vector2(interpolated_moon.position).distance_to(expected_moon_position) < 0.001)
	cached_simulation.set_rocket_design(RocketDesign.create_default())
	cached_simulation.landed = false
	cached_simulation.rocket_position = Vector2(0.0, -FlightComputer.EARTH_RADIUS - 200000.0)
	cached_simulation.velocity = Vector2(7800.0, 0.0)
	var orbital_step: float = cached_simulation._adaptive_step_size()
	assert(orbital_step > 5.0 and orbital_step <= 180.0)
	cached_simulation.rocket_position = Vector2(0.0, -FlightComputer.EARTH_RADIUS - 1000.0)
	var atmospheric_step: float = cached_simulation._adaptive_step_size()
	assert(atmospheric_step <= 0.25)
	cached_simulation.rocket_position = Vector2(1.495978707e11, 0.0)
	cached_simulation.velocity = Vector2(30000.0, 0.0)
	var deep_space_step: float = cached_simulation._adaptive_step_size()
	assert(deep_space_step >= 1000.0)
	cached_simulation.rocket_position = Vector2(0.0, -FlightComputer.EARTH_RADIUS - 200000.0)
	cached_simulation.velocity = Vector2(7800.0, 0.0)
	cached_simulation.autopilot_enabled = true
	cached_simulation.autopilot_phase = "MANEUVER_BURN"
	cached_simulation.autopilot_burn_remaining = 100.0
	var alignment_step: float = cached_simulation._adaptive_step_size()
	assert(alignment_step <= 0.1)
	cached_simulation.autopilot_enabled = false
	cached_simulation.autopilot_phase = "IDLE"
	cached_simulation.autopilot_burn_remaining = 0.0
	cached_simulation.time_warp = 1000.0
	cached_simulation.landed = false
	cached_simulation.sim_time = 0.0
	cached_simulation._process(0.016)
	assert(absf(cached_simulation.sim_time + cached_simulation.simulation_time_backlog - 16.0) < 0.01)
	cached_simulation.free()

	print("Flight computer orbital calculation tests passed.")
	quit()
