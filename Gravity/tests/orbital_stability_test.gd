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
