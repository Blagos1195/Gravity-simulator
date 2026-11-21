extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var orbit_cases := [
		{"name": "LEO", "altitude": 200000.0},
		{"name": "MEO", "altitude": 20200000.0},
		{"name": "GEO", "altitude": 35786000.0}
	]
	for orbit_case in orbit_cases:
		_validate_orbit(str(orbit_case.name), float(orbit_case.altitude))
	print("Long-duration orbital stability tests passed.")
	quit()

func _validate_orbit(orbit_name: String, altitude: float) -> void:
	var radius: float = FlightComputer.EARTH_RADIUS + altitude
	var speed: float = FlightComputer.circular_orbit_speed(radius)
	var period: float = TAU * sqrt(radius * radius * radius / (FlightComputer.G * FlightComputer.EARTH_MASS))
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Arcade"
	simulation.landed = false
	simulation.rocket_position = Vector2(0.0, -radius)
	simulation.velocity = Vector2(speed, 0.0)
	simulation.sim_time = 0.0
	var elapsed := 0.0
	var maximum_step_count := int(ceil(period / 0.5)) + 10
	var step_count := 0
	while elapsed < period:
		var step: float = minf(simulation._adaptive_step_size(), period - elapsed)
		assert(step > 0.000001, "%s produced a zero physics step" % orbit_name)
		simulation._physics_step(step)
		elapsed += step
		step_count += 1
		assert(step_count <= maximum_step_count, "%s exceeded its integration step budget" % orbit_name)
		assert(not simulation.crashed, "%s crashed during an unpowered orbit" % orbit_name)
	var final_state: Dictionary = FlightComputer.orbital_state(simulation.rocket_position, simulation.velocity)
	var final_altitude: float = simulation.rocket_position.length() - FlightComputer.EARTH_RADIUS
	var altitude_error: float = absf(final_altitude - altitude)
	assert(bool(final_state.get("bound", false)), "%s became unbound" % orbit_name)
	assert(altitude_error < maxf(1000.0, altitude * 0.0001), "%s altitude drifted by %.1f m" % [orbit_name, altitude_error])
	assert(float(final_state.get("eccentricity", 1.0)) < 0.001, "%s orbit became eccentric" % orbit_name)
	simulation.free()
