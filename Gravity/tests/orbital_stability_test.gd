extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var orbit_cases := [
		{"name": "LEO", "altitude": 200000.0, "orbits": 3},
		{"name": "MEO", "altitude": 20200000.0, "orbits": 1},
		{"name": "GEO", "altitude": 35786000.0, "orbits": 1}
	]
	for orbit_case in orbit_cases:
		if not _validate_orbit(str(orbit_case.name), float(orbit_case.altitude), int(orbit_case.orbits)):
			return
	var local_orbit_cases := [
		{"body": "Moon", "altitude": 100000.0, "orbits": 1},
		{"body": "Mars", "altitude": 300000.0, "orbits": 1}
	]
	for orbit_case in local_orbit_cases:
		if not _validate_local_orbit(str(orbit_case.body), float(orbit_case.altitude), int(orbit_case.orbits)):
			return
	print("Long-duration orbital stability tests passed.")
	quit()

func _validate_orbit(orbit_name: String, altitude: float, orbit_count: int) -> bool:
	var radius: float = FlightComputer.EARTH_RADIUS + altitude
	var speed: float = FlightComputer.circular_orbit_speed(radius)
	var period: float = TAU * sqrt(radius * radius * radius / (FlightComputer.G * PlanetarySystem.EARTH_MASS))
	var duration: float = period * float(orbit_count)
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.landed = false
	simulation.rocket_position = Vector2(0.0, -radius)
	simulation.velocity = Vector2(speed, 0.0)
	simulation.sim_time = 0.0
	var elapsed := 0.0
	var maximum_step_count := int(ceil(duration / 0.3)) + 10
	var step_count := 0
	while elapsed < duration:
		var step: float = minf(simulation._adaptive_step_size(), duration - elapsed)
		if not _check(step > 0.000001, "%s produced a zero physics step" % orbit_name):
			simulation.free()
			return false
		simulation._physics_step(step)
		elapsed += step
		step_count += 1
		if not _check(step_count <= maximum_step_count, "%s exceeded its integration step budget" % orbit_name):
			simulation.free()
			return false
		if not _check(not simulation.crashed, "%s crashed during an unpowered orbit" % orbit_name):
			simulation.free()
			return false
	var final_state: Dictionary = FlightComputer.orbital_state(simulation.rocket_position, simulation.velocity)
	var final_altitude: float = simulation.rocket_position.length() - FlightComputer.EARTH_RADIUS
	var altitude_error: float = absf(final_altitude - altitude)
	var valid := _check(bool(final_state.get("bound", false)), "%s became unbound" % orbit_name)
	valid = _check(altitude_error < maxf(1000.0, altitude * 0.0001), "%s altitude drifted by %.1f m" % [orbit_name, altitude_error]) and valid
	valid = _check(float(final_state.get("eccentricity", 1.0)) < 0.001, "%s orbit became eccentric" % orbit_name) and valid
	simulation.free()
	return valid

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _validate_local_orbit(body_name: String, altitude: float, orbit_count: int) -> bool:
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.landed = false
	simulation.sim_time = 0.0
	var body_state: Dictionary = simulation._surface_body_state(body_name)
	var radius: float = float(body_state.radius) + altitude
	var mu: float = FlightComputer.G * float(body_state.mass)
	var speed := sqrt(mu / radius)
	var period := TAU * sqrt(radius * radius * radius / mu)
	var duration := period * float(orbit_count)
	simulation._set_rocket_position_relative_to_body(body_state, Vector2(radius, 0.0))
	simulation.velocity = Vector2(body_state.velocity) + Vector2(0.0, speed)
	if body_name == "Moon":
		var initial_states: Dictionary = simulation._ephemeris_states_at(0.0)
		var initial_acceleration: Vector2 = PlanetarySystem.gravity_acceleration_from_precise_states(simulation.rocket_position_precise, initial_states)
		var moon_before: PackedFloat64Array = PlanetarySystem.moon_state(-1.0).position_components
		var moon_now: PackedFloat64Array = PlanetarySystem.moon_state(0.0).position_components
		var moon_after: PackedFloat64Array = PlanetarySystem.moon_state(1.0).position_components
		var moon_acceleration := Vector2(moon_after[0] - moon_now[0] * 2.0 + moon_before[0], moon_after[1] - moon_now[1] * 2.0 + moon_before[1])
		var relative_acceleration: Vector2 = initial_acceleration - moon_acceleration
		var expected_acceleration: Vector2 = Vector2(-mu / (radius * radius), 0.0)
		print("Moon acceleration diagnostic: gravity=%s moon=%s relative=%s rocket=%s moon_position=%s moon_velocity=%s" % [initial_acceleration, moon_acceleration, relative_acceleration, simulation.rocket_position_precise, moon_now, PlanetarySystem.moon_state(0.0).velocity_components])
		for gravity_body in initial_states.get("bodies", []):
			print("Gravity body %s position=%s precise=%s mass=%s" % [gravity_body.get("name", ""), gravity_body.get("position", Vector2.ZERO), gravity_body.get("position_components", PackedFloat64Array()), gravity_body.get("mass", 0.0)])
	var elapsed := 0.0
	var maximum_step_count := int(ceil(duration / 0.3)) + 10
	var step_count := 0
	var next_checkpoint := 0.25
	while elapsed < duration:
		var step: float = minf(simulation._adaptive_step_size(), duration - elapsed)
		if not _check(step > 0.000001, "%s orbit produced a zero physics step" % body_name):
			simulation.free()
			return false
		simulation._physics_step(step)
		elapsed += step
		step_count += 1
		if not _check(step_count <= maximum_step_count, "%s orbit exceeded its integration step budget" % body_name):
			simulation.free()
			return false
		if not _check(not simulation.crashed, "%s orbit crashed during an unpowered revolution" % body_name):
			simulation.free()
			return false
		if elapsed >= duration * next_checkpoint:
			var checkpoint_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
			var checkpoint_position: Vector2 = checkpoint_body.relative_position
			var checkpoint_velocity: Vector2 = simulation.velocity - Vector2(checkpoint_body.velocity)
			var checkpoint_state: Dictionary = FlightComputer.orbital_state(checkpoint_position, checkpoint_velocity, mu)
			print("%s orbit at %.0f%%: e=%.8f" % [body_name, next_checkpoint * 100.0, float(checkpoint_state.get("eccentricity", 1.0))])
			next_checkpoint += 0.25
	var final_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	var relative_position: Vector2 = final_body.relative_position
	var relative_velocity: Vector2 = simulation.velocity - Vector2(final_body.velocity)
	var final_state: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, mu)
	var final_altitude: float = relative_position.length() - float(body_state.radius)
	var altitude_error: float = absf(final_altitude - altitude)
	var altitude_tolerance := 5000.0 if body_name == "Moon" else maxf(1000.0, altitude * 0.0001)
	var eccentricity_limit := 0.002 if body_name == "Moon" else 0.001
	var valid := _check(str(final_body.get("name", "")) == body_name, "%s spacecraft left its local reference body" % body_name)
	valid = _check(bool(final_state.get("bound", false)), "%s local orbit became unbound" % body_name) and valid
	valid = _check(altitude_error < altitude_tolerance, "%s local orbit altitude drifted by %.1f m" % [body_name, altitude_error]) and valid
	valid = _check(float(final_state.get("eccentricity", 1.0)) < eccentricity_limit, "%s local orbit became eccentric (e=%.6f, limit=%.6f)" % [body_name, float(final_state.get("eccentricity", 1.0)), eccentricity_limit]) and valid
	simulation.free()
	return valid
