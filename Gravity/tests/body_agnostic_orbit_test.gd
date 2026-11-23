extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	_validate_catalogue_orbits()
	_validate_earth_to_moon_transfer()
	_validate_moon_arrival_capture()
	_validate_local_orbit_autopilot("Moon")
	_validate_local_orbit_autopilot("Mars")
	_validate_unbound_recovery_to_orbit()
	print("Body-agnostic orbital guidance tests passed.")
	quit()


func _validate_catalogue_orbits() -> void:
	var simulation: Variant = SimulationView.new()
	var states: Dictionary = simulation._ephemeris_states_at(0.0)
	var body_lookup: Dictionary = {}
	var feasible_orbit_count := 0
	for body_variant in states.get("surface_bodies", []):
		var body: Dictionary = body_variant
		var body_name := str(body.get("name", ""))
		body_lookup[body_name] = body
		var body_radius := float(body.get("radius", 0.0))
		var body_mass := float(body.get("mass", 0.0))
		var safe_altitude := FlightComputer.minimum_safe_orbit_altitude(body_name, body_radius)
		var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body.get("soi", 0.0)))
		assert(safe_altitude > 0.0, "%s has no calculated minimum safe orbit altitude" % body_name)
		assert(safe_altitude >= PlanetarySystem.planetary_atmosphere_height(body_name), "%s safe orbit is below its atmosphere" % body_name)
		if maximum_altitude < safe_altitude or body_mass <= 0.0:
			continue
		var target_altitude := safe_altitude + minf(50000.0, (maximum_altitude - safe_altitude) * 0.2)
		var apoapsis_offset := minf(25000.0, (maximum_altitude - target_altitude) * 0.5)
		if apoapsis_offset <= 1.0:
			continue
		var target_radius := body_radius + target_altitude
		var start_radius := target_radius + apoapsis_offset
		var body_mu := FlightComputer.G * body_mass
		var start_position := Vector2(start_radius, 0.0)
		var start_velocity := Vector2(0.0, FlightComputer.circular_orbit_speed(start_radius, body_mu))
		var transfer := FlightComputer.target_radius_burn(start_position, start_velocity, target_radius, body_mu)
		assert(bool(transfer.get("valid", false)), "%s rejected a feasible target orbit" % body_name)
		var resulting_orbit := FlightComputer.orbital_state(start_position, Vector2(transfer.get("desired_velocity", Vector2.ZERO)), body_mu)
		assert(bool(resulting_orbit.get("bound", false)), "%s target-orbit burn produced an unbound trajectory" % body_name)
		assert(absf(float(resulting_orbit.get("periapsis", 0.0)) - target_radius) < FlightComputer.orbit_radius_tolerance(target_radius), "%s target-orbit burn missed its periapsis" % body_name)
		feasible_orbit_count += 1
	assert(feasible_orbit_count >= 2, "Fewer than two catalogue bodies expose a usable stable-orbit region")
	assert(body_lookup.has("Earth"))
	assert(body_lookup.has("Moon"))

	var target_indices: Array[int] = [-2, -1]
	for planet_index in range(FlightComputer.PLANET_TARGETS.size()):
		target_indices.append(planet_index)
	for satellite in FlightComputer.SATELLITE_TARGETS:
		target_indices.append(int(satellite.get("id", -1)))
	for target_index in target_indices:
		var target_name := FlightComputer.target_body_name(target_index)
		assert(not target_name.is_empty(), "A destination dropdown entry has no body name")
		assert(body_lookup.has(target_name), "Destination %s is missing from the simulation ephemeris" % target_name)

	for planet in PlanetarySystem.PLANETS:
		var host_name := str(planet.get("name", ""))
		for satellite in FlightComputer.satellite_targets_for_host(host_name):
			var satellite_id := int(satellite.get("id", -1))
			assert(satellite_id >= FlightComputer.SATELLITE_TARGET_INDEX_BASE)
			assert(FlightComputer.target_body_name(satellite_id) == str(satellite.get("name", "")))
			assert(body_lookup.has(FlightComputer.target_body_name(satellite_id)), "Moon dropdown entry is not a simulated body")
			assert(str(satellite.get("host_name", "")) == host_name)
	simulation.free()


func _validate_earth_to_moon_transfer() -> void:
	var parking_radius := PlanetarySystem.EARTH_RADIUS + 200000.0
	var parking_speed := FlightComputer.circular_orbit_speed(parking_radius)
	var departure_time := 20.0 * 86400.0
	var plan := FlightComputer.simulated_transfer_search_precise(PackedFloat64Array([0.0, -parking_radius]), Vector2(parking_speed, 0.0), departure_time, -1, 15000.0, 0.0, false, 300000.0)
	assert(bool(plan.get("valid", false)), "Earth-to-Moon transfer search failed: %s" % str(plan))
	assert(float(plan.get("total_delta_v", INF)) <= 15000.0)
	var moon_state := FlightComputer._simulated_target_state(-1, departure_time + float(plan.get("transfer_time", 0.0)))
	var target_radius := float(moon_state.get("radius", 0.0)) + 300000.0
	assert(float(plan.get("closest_approach", INF)) <= float(plan.get("target_soi", 0.0)))
	assert(absf(float(plan.get("capture_periapsis", 0.0)) - target_radius) <= FlightComputer.orbit_radius_tolerance(target_radius), "Moon capture periapsis missed the requested altitude: %s" % str(plan))
	assert(plan.get("arrival_relative_position", Vector2.ZERO).length() > target_radius)
	var impossible_plan := FlightComputer.simulated_transfer_search_precise(PackedFloat64Array([0.0, -parking_radius]), Vector2(parking_speed, 0.0), departure_time, -1, 1.0, 0.0, true, 300000.0)
	assert(not bool(impossible_plan.get("valid", false)), "Transfer search accepted an impossible one-metre-per-second budget")
	var impossible_window := FlightComputer.scan_launch_windows(Vector2(0.0, -parking_radius), Vector2(parking_speed, 0.0), departure_time, -1, 1.0, 0.0, 1, 1, 300000.0, PackedFloat64Array([0.0, -parking_radius]))
	assert(not bool(impossible_window.get("valid", false)), "Launch-window search accepted an impossible delta-v budget")


func _validate_moon_arrival_capture() -> void:
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.infinite_weightless_fuel = true
	simulation.landed = false
	simulation.autopilot_enabled = true
	simulation.guidance_enabled = true
	simulation.autopilot_target_mode = "ORBIT"
	simulation.autopilot_target_altitude = 200000.0
	simulation.autopilot_planet_index = -1
	simulation.autopilot_phase = "ARRIVAL_APPROACH"
	var moon_state: Dictionary = simulation._surface_body_state("Moon")
	var moon_radius := float(moon_state.get("radius", 0.0))
	var moon_mu := FlightComputer.G * float(moon_state.get("mass", 0.0))
	var moon_soi := float(moon_state.get("soi", 0.0))
	var relative_position := Vector2(moon_soi * 0.8, 0.0)
	var relative_velocity := Vector2(-1500.0, 200.0)
	simulation._set_rocket_position_relative_to_body(moon_state, relative_position)
	simulation.velocity = Vector2(moon_state.get("velocity", Vector2.ZERO)) + relative_velocity
	simulation._update_guidance(0.1)
	assert(simulation.autopilot_phase == "ARRIVAL_CAPTURE_BURN", "Inbound Moon arrival did not start capture before periapsis: %s" % simulation.status_message)
	var safe_altitude := FlightComputer.minimum_safe_orbit_altitude("Moon", moon_radius)
	var capture := FlightComputer.arrival_capture_burn(relative_position, relative_velocity, moon_mu, moon_radius, 200000.0, safe_altitude)
	assert(bool(capture.get("valid", false)), "Moon SOI arrival did not produce a valid capture burn")
	var captured_orbit := FlightComputer.orbital_state(relative_position, relative_velocity + Vector2(capture.get("burn_vector", Vector2.ZERO)), moon_mu)
	var target_radius := moon_radius + maxf(safe_altitude, 200000.0)
	assert(bool(captured_orbit.get("bound", false)), "Moon arrival capture did not produce a bound orbit")
	assert(absf(float(captured_orbit.get("periapsis", 0.0)) - target_radius) < FlightComputer.orbit_radius_tolerance(target_radius), "Moon arrival capture missed the requested periapsis")

	simulation.free()

	var missed_simulation: Variant = SimulationView.new()
	missed_simulation.set_rocket_design(RocketDesign.create_default())
	missed_simulation.landed = false
	missed_simulation.autopilot_enabled = true
	missed_simulation.guidance_enabled = true
	missed_simulation.autopilot_target_mode = "ORBIT"
	missed_simulation.autopilot_target_altitude = 200000.0
	missed_simulation.autopilot_planet_index = -1
	missed_simulation.autopilot_phase = "ARRIVAL_APPROACH"
	var missed_moon_state: Dictionary = missed_simulation._surface_body_state("Moon")
	missed_simulation._set_rocket_position_relative_to_body(missed_moon_state, relative_position)
	missed_simulation.velocity = Vector2(missed_moon_state.get("velocity", Vector2.ZERO)) + Vector2(1500.0, 200.0)
	missed_simulation._update_guidance(0.1)
	assert(missed_simulation.autopilot_phase == "FAILED", "Outbound Moon flyby was not identified as a missed capture")
	missed_simulation.autopilot_phase = "ARRIVAL_PENDING"
	missed_simulation._update_guidance(0.1)
	assert(missed_simulation.autopilot_phase == "FAILED", "Missed arrival window did not terminate autopilot cleanly")
	missed_simulation.free()


func _validate_local_orbit_autopilot(body_name: String) -> void:
	var target_index := _target_index_for_body(body_name)
	assert(target_index != -999999, "%s has no autopilot target identifier" % body_name)
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.infinite_weightless_fuel = true
	simulation.landed = false
	simulation.sim_time = 0.0
	var body_state: Dictionary = simulation._surface_body_state(body_name)
	assert(not body_state.is_empty(), "%s is missing from the surface-body ephemeris" % body_name)
	var body_radius := float(body_state.get("radius", 0.0))
	var body_mu := FlightComputer.G * float(body_state.get("mass", 0.0))
	var safe_altitude := FlightComputer.minimum_safe_orbit_altitude(body_name, body_radius)
	var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body_state.get("soi", 0.0)))
	assert(maximum_altitude > safe_altitude + 30000.0, "%s has insufficient room for the autopilot mission test" % body_name)
	var target_altitude := safe_altitude + 20000.0
	var initial_altitude := target_altitude + 15000.0
	assert(initial_altitude < maximum_altitude, "%s initial test orbit exceeds its stable region" % body_name)
	var target_radius := body_radius + target_altitude
	var initial_radius := body_radius + initial_altitude
	var orbital_period := TAU * sqrt(pow(initial_radius, 3.0) / body_mu)
	simulation._set_rocket_position_relative_to_body(body_state, Vector2(initial_radius, 0.0))
	simulation.velocity = Vector2(body_state.get("velocity", Vector2.ZERO)) + Vector2(0.0, FlightComputer.circular_orbit_speed(initial_radius, body_mu))
	simulation.autopilot_enabled = true
	simulation.autopilot_complete = false
	simulation.guidance_enabled = true
	simulation.autopilot_target_mode = "ORBIT"
	simulation.autopilot_target_altitude = target_altitude
	simulation.autopilot_planet_index = target_index
	simulation.autopilot_burn_remaining = 0.0
	simulation.autopilot_phase = "CIRCULARISE"
	var elapsed := 0.0
	var iterations := 0
	var previous_phase: String = str(simulation.autopilot_phase)
	var phase_transitions: Array[String] = []
	while elapsed < orbital_period * 2.0 and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = simulation._adaptive_step_size()
		assert(step > 0.000001, "%s autopilot produced a zero physics step" % body_name)
		step = minf(step, orbital_period * 2.0 - elapsed)
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		if simulation.autopilot_phase != previous_phase:
			if phase_transitions.size() < 30:
				var phase_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
				var phase_position: Vector2 = phase_body.relative_position
				var phase_velocity: Vector2 = simulation.velocity - Vector2(phase_body.velocity)
				var phase_orbit := FlightComputer.orbital_state(phase_position, phase_velocity, body_mu)
				phase_transitions.append("%.1f %s>%s alt=%.1f radial=%.3f peri=%.1f apo=%.1f burn=%.3f" % [elapsed, previous_phase, simulation.autopilot_phase, float(phase_body.distance) - body_radius, float(phase_orbit.get("radial_speed", INF)), float(phase_orbit.get("periapsis", 0.0)) - body_radius, float(phase_orbit.get("apoapsis", INF)) - body_radius, simulation.autopilot_burn_remaining])
			elif phase_transitions.size() == 30:
				phase_transitions.append("Further phase transitions omitted")
			previous_phase = simulation.autopilot_phase
		assert(iterations < 300000, "%s autopilot exceeded its step budget" % body_name)
	var diagnostic_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	var diagnostic_position: Vector2 = diagnostic_body.relative_position
	var diagnostic_velocity: Vector2 = simulation.velocity - Vector2(diagnostic_body.velocity)
	var diagnostic_orbit := FlightComputer.orbital_state(diagnostic_position, diagnostic_velocity, body_mu)
	print("%s autopilot trace: phase=%s elapsed=%.1f alt=%.1f radial=%.3f peri=%.1f apo=%.1f burn=%.3f transitions=%s" % [body_name, simulation.autopilot_phase, elapsed, float(diagnostic_body.distance) - body_radius, float(diagnostic_orbit.get("radial_speed", INF)), float(diagnostic_orbit.get("periapsis", 0.0)) - body_radius, float(diagnostic_orbit.get("apoapsis", INF)) - body_radius, simulation.autopilot_burn_remaining, "; ".join(PackedStringArray(phase_transitions))])
	assert(simulation.autopilot_complete, "%s local orbit autopilot failed: phase=%s status=%s altitude=%.1f fuel=%.1f" % [body_name, simulation.autopilot_phase, simulation.status_message, float(simulation._nearest_body_state(simulation.rocket_position).get("distance", 0.0)) - body_radius, simulation.fuel])
	var final_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	assert(str(final_body.get("name", "")) == body_name, "%s autopilot left its local reference body" % body_name)
	var final_position: Vector2 = final_body.relative_position
	var final_velocity: Vector2 = simulation.velocity - Vector2(final_body.velocity)
	var final_orbit := FlightComputer.orbital_state(final_position, final_velocity, body_mu)
	assert(bool(final_orbit.get("bound", false)), "%s final orbit is unbound" % body_name)
	assert(absf(float(final_orbit.get("periapsis", 0.0)) - target_radius) < maxf(5000.0, FlightComputer.orbit_radius_tolerance(target_radius) * 2.0), "%s periapsis missed its target" % body_name)
	assert(absf(float(final_orbit.get("apoapsis", 0.0)) - target_radius) < maxf(5000.0, FlightComputer.orbit_radius_tolerance(target_radius) * 2.0), "%s apoapsis missed its target" % body_name)

	simulation.free()


func _validate_unbound_recovery_to_orbit() -> void:
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.infinite_weightless_fuel = true
	simulation.landed = false
	var body_state: Dictionary = simulation._surface_body_state("Earth")
	var body_radius := float(body_state.get("radius", 0.0))
	var body_mu := FlightComputer.G * float(body_state.get("mass", 0.0))
	var initial_radius := body_radius + 200000.0
	var target_radius := body_radius + 300000.0
	var initial_speed := FlightComputer.circular_orbit_speed(initial_radius, body_mu) * 1.5
	simulation._set_rocket_position_relative_to_body(body_state, Vector2.UP * initial_radius)
	simulation.velocity = Vector2(body_state.get("velocity", Vector2.ZERO)) + Vector2.RIGHT * initial_speed
	var initial_orbit := FlightComputer.orbital_state(Vector2.UP * initial_radius, Vector2.RIGHT * initial_speed, body_mu)
	assert(not bool(initial_orbit.get("bound", true)), "Recovery mission did not start on an unbound trajectory")
	var planner: Window = RoutePlanner.new()
	root.add_child(planner)
	planner.configure(simulation, RocketDesign.create_default())
	planner.navigation_planet_dropdown.select(0)
	planner._rebuild_navigation_moons(-2)
	planner.navigation_moon_dropdown.select(0)
	planner.navigation_altitude_input.value = 300.0
	planner._calculate_destination_plan()
	assert(planner.navigation_plan_valid, "Unbound-to-Earth-orbit planning failed: %s" % planner.navigation_report.text)
	assert(bool(planner.navigation_plan.get("needs_parking_orbit", false)), "Unbound local trajectory did not request recovery")
	planner._send_destination_to_autopilot()
	assert(simulation.autopilot_enabled)
	assert(simulation.autopilot_phase == "CIRCULARISE")
	var elapsed := 0.0
	var iterations := 0
	var orbital_period := TAU * sqrt(pow(target_radius, 3.0) / body_mu)
	while elapsed < orbital_period * 3.0 and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = minf(simulation._adaptive_step_size(), orbital_period * 3.0 - elapsed)
		assert(step > 0.000001, "Recovery mission produced an invalid physics step")
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		assert(iterations < 300000, "Recovery mission exceeded its physics-step budget")
	assert(simulation.autopilot_complete, "Unbound-to-Earth-orbit mission failed: phase=%s status=%s elapsed=%.1f altitude=%.1f" % [simulation.autopilot_phase, simulation.status_message, elapsed, float(simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise).get("distance", 0.0)) - body_radius])
	var final_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	var final_position: Vector2 = final_body.relative_position
	var final_velocity: Vector2 = simulation.velocity - Vector2(final_body.velocity)
	var final_orbit := FlightComputer.orbital_state(final_position, final_velocity, body_mu)
	assert(bool(final_orbit.get("bound", false)), "Recovered Earth orbit is not bound")
	assert(absf(float(final_orbit.get("periapsis", 0.0)) - target_radius) < 5000.0, "Recovered Earth orbit missed target periapsis")
	assert(absf(float(final_orbit.get("apoapsis", 0.0)) - target_radius) < 5000.0, "Recovered Earth orbit missed target apoapsis")
	planner.free()
	simulation.free()


func _target_index_for_body(body_name: String) -> int:
	if body_name == "Earth":
		return -2
	if body_name == "Moon":
		return -1
	for planet_index in range(FlightComputer.PLANET_TARGETS.size()):
		if FlightComputer.target_body_name(planet_index) == body_name:
			return planet_index
	for satellite in FlightComputer.SATELLITE_TARGETS:
		var satellite_id := int(satellite.get("id", -1))
		if FlightComputer.target_body_name(satellite_id) == body_name:
			return satellite_id
	return -999999
