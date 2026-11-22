extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	_validate_catalogue_orbits()
	_validate_local_orbit_autopilot("Moon")
	_validate_local_orbit_autopilot("Mars")
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
	while elapsed < orbital_period * 2.0 and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = simulation._adaptive_step_size()
		assert(step > 0.000001, "%s autopilot produced a zero physics step" % body_name)
		step = minf(step, orbital_period * 2.0 - elapsed)
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		assert(iterations < 300000, "%s autopilot exceeded its step budget" % body_name)
	assert(simulation.autopilot_complete, "%s local orbit autopilot failed: phase=%s status=%s altitude=%.1f fuel=%.1f" % [body_name, simulation.autopilot_phase, simulation.status_message, float(simulation._nearest_body_state(simulation.rocket_position).get("distance", 0.0)) - body_radius, simulation.fuel])
	var final_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	assert(str(final_body.get("name", "")) == body_name, "%s autopilot left its local reference body" % body_name)
	var final_position: Vector2 = final_body.relative_position
	var final_velocity: Vector2 = simulation.velocity - Vector2(final_body.velocity)
	var final_orbit := FlightComputer.orbital_state(final_position, final_velocity, body_mu)
	assert(bool(final_orbit.get("bound", false)), "%s final orbit is unbound" % body_name)
	assert(absf(float(final_orbit.get("periapsis", 0.0)) - target_radius) < maxf(5000.0, FlightComputer.orbit_radius_tolerance(target_radius) * 2.0), "%s periapsis missed its target" % body_name)
	assert(absf(float(final_orbit.get("apoapsis", 0.0)) - target_radius) < maxf(5000.0, FlightComputer.orbit_radius_tolerance(target_radius) * 2.0), "%s apoapsis missed its target" % body_name)

	var coast_period := TAU * sqrt(pow(float(final_orbit.get("semi_major_axis", target_radius)), 3.0) / body_mu)
	var coast_elapsed := 0.0
	while coast_elapsed < coast_period:
		var step: float = minf(simulation._adaptive_step_size(), coast_period - coast_elapsed)
		assert(step > 0.000001, "%s stability check produced a zero physics step" % body_name)
		simulation._physics_step(step)
		coast_elapsed += step
		assert(not simulation.crashed, "%s circular orbit crashed during one revolution" % body_name)
		assert(not simulation.landed, "%s circular orbit unexpectedly landed during one revolution" % body_name)
	var coast_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	assert(str(coast_body.get("name", "")) == body_name, "%s spacecraft left its local body during one revolution" % body_name)
	var coast_position: Vector2 = coast_body.relative_position
	var coast_velocity: Vector2 = simulation.velocity - Vector2(coast_body.velocity)
	var coast_orbit := FlightComputer.orbital_state(coast_position, coast_velocity, body_mu)
	assert(bool(coast_orbit.get("bound", false)), "%s orbit became unbound during one revolution" % body_name)
	assert(float(coast_orbit.get("periapsis", 0.0)) > body_radius + safe_altitude, "%s orbit fell inside its safe altitude during one revolution" % body_name)
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
