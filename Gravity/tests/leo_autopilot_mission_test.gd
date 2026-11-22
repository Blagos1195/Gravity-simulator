extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")

func _initialize() -> void:
	_validate_leo_autopilot_mission()
	print("LEO autopilot mission test passed.")
	quit()

func _validate_leo_autopilot_mission() -> void:
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.landed = true
	simulation.landed_body_name = "Earth"
	simulation.landed_surface_normal = Vector2.UP
	simulation._set_rocket_position_components(0.0, -PlanetarySystem.EARTH_RADIUS - 0.5)
	simulation.autopilot_enabled = true
	simulation.guidance_enabled = true
	simulation.autopilot_target_altitude = 200000.0
	simulation.autopilot_target_mode = "ORBIT"
	simulation.autopilot_planet_index = -2
	simulation.autopilot_phase = "ASCENT"
	simulation.thrust_key_down = true
	var target_orbit_radius: float = PlanetarySystem.EARTH_RADIUS + float(simulation.autopilot_target_altitude)
	var mission_time_limit: float = TAU * sqrt(pow(target_orbit_radius, 3.0) / (PlanetarySystem.G * PlanetarySystem.EARTH_MASS))
	var elapsed := 0.0
	var iterations := 0
	while elapsed < mission_time_limit and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = simulation._adaptive_step_size()
		assert(step > 0.000001)
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		assert(iterations < 100000, "LEO mission exceeded its iteration budget: phase=%s status=%s elapsed=%.1f altitude=%.1f speed=%.1f fuel=%.1f step=%.4f" % [simulation.autopilot_phase, simulation.status_message, elapsed, simulation._nearest_body_state(simulation.rocket_position).distance - PlanetarySystem.EARTH_RADIUS, simulation.velocity.length(), simulation.fuel, step])
	assert(not simulation.crashed, "LEO ascent crashed: phase=%s status=%s elapsed=%.1f altitude=%.1f speed=%.1f fuel=%.1f" % [simulation.autopilot_phase, simulation.status_message, elapsed, simulation._nearest_body_state(simulation.rocket_position).distance - PlanetarySystem.EARTH_RADIUS, simulation.velocity.length(), simulation.fuel])
	assert(simulation.autopilot_complete)
	assert(simulation.autopilot_phase == "COMPLETE")
	assert(not simulation.landed)
	var earth_state: Dictionary = simulation._surface_body_state("Earth")
	var relative_position: Vector2 = simulation._relative_position_to_body(earth_state)
	var relative_velocity: Vector2 = simulation.velocity - Vector2(earth_state.velocity)
	var orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
	assert(bool(orbit.get("valid", false)))
	assert(bool(orbit.get("bound", false)))
	assert(float(orbit.get("periapsis", 0.0)) > PlanetarySystem.EARTH_RADIUS + 70000.0)
	assert(float(orbit.get("apoapsis", 0.0)) > PlanetarySystem.EARTH_RADIUS + 100000.0)
	assert(float(orbit.get("apoapsis", 0.0)) < PlanetarySystem.EARTH_RADIUS + 1000000.0)
	var orbital_period := TAU * sqrt(pow(float(orbit.get("semi_major_axis", 0.0)), 3.0) / (PlanetarySystem.G * PlanetarySystem.EARTH_MASS))
	var coast_elapsed := 0.0
	while coast_elapsed < orbital_period:
		var step: float = minf(simulation._adaptive_step_size(), orbital_period - coast_elapsed)
		assert(step > 0.000001)
		simulation._physics_step(step)
		coast_elapsed += step
		assert(not simulation.crashed, "LEO orbit decayed into Earth during one revolution")
		assert(not simulation.landed, "LEO autopilot unexpectedly landed during one revolution")
	var coast_earth_state: Dictionary = simulation._surface_body_state("Earth")
	var coast_position: Vector2 = simulation._relative_position_to_body(coast_earth_state)
	var coast_velocity: Vector2 = simulation.velocity - Vector2(coast_earth_state.velocity)
	var coast_orbit: Dictionary = FlightComputer.orbital_state(coast_position, coast_velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
	assert(bool(coast_orbit.get("bound", false)), "LEO became unbound during one revolution")
	assert(float(coast_orbit.get("periapsis", 0.0)) > PlanetarySystem.EARTH_RADIUS + 70000.0, "LEO periapsis fell below the safe orbit")
	simulation.free()
