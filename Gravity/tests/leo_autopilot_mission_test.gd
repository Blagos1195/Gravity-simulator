extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

func _initialize() -> void:
	if not _validate_leo_autopilot_mission(false):
		quit(1)
		return
	if not _validate_leo_autopilot_mission(true):
		quit(1)
		return
	if not _validate_pathfinder_leo_autopilot():
		quit(1)
		return
	print("LEO autopilot missions and one-revolution stability checks passed with finite and infinite propellant, including Pathfinder.")
	quit(0)


func _validate_pathfinder_leo_autopilot() -> bool:
	var design := RocketAssembly.add_preset_hardware(RocketDesign.create_preset("LUNAR_CARGO"))
	var stages: Array = design.get("stages", []).duplicate(true)
	var upper_stage: Dictionary = stages.back()
	upper_stage = RocketAssembly.add_component(upper_stage, "compact_tank", "stack", false, 1, 0)
	var upper_components: Array = upper_stage.get("components", []).duplicate(true)
	var compact_tank: Dictionary = upper_components.pop_back()
	upper_components.insert(0, compact_tank)
	upper_stage = RocketAssembly.compile_stage(upper_stage, upper_components)
	stages[stages.size() - 1] = upper_stage
	design["stages"] = stages
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(design)
	print("PATHFINDER INITIAL RCS remaining=%.1f capacity=%.1f installed=%s gimbal=%s" % [simulation.rcs_propellant_remaining, simulation._remaining_rcs_propellant_capacity(), simulation.has_rcs_installed(), simulation._remaining_engine_elements(0.0, 0.0).any(func(engine: Dictionary) -> bool: return bool(engine.get("gimballed", false)))])
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
	var target_orbit_radius: float = PlanetarySystem.EARTH_RADIUS + simulation.autopilot_target_altitude
	var target_orbit_period := TAU * sqrt(pow(target_orbit_radius, 3.0) / (PlanetarySystem.G * PlanetarySystem.EARTH_MASS))
	var elapsed := 0.0
	var iterations := 0
	var next_trace_time := 10.0
	while elapsed < target_orbit_period * 2.0 and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = simulation._adaptive_step_size()
		if step <= 0.000001:
			break
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		if elapsed >= next_trace_time:
			var trace_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
			print("PATHFINDER TRACE t=%.1f alt=%.0f speed=%.0f radial=%.0f tangential=%.0f pitch=%.1f rot=%.2f angular=%.3f rcs=%.0f fuel=%.0f stage=%d thrust=%s" % [elapsed, float(trace_body.distance) - PlanetarySystem.EARTH_RADIUS, simulation.velocity.length(), (simulation.velocity - trace_body.velocity).dot(trace_body.relative_position.normalized()), (simulation.velocity - trace_body.velocity).dot(Vector2(-trace_body.relative_position.y, trace_body.relative_position.x).normalized()), simulation.rotation_angle, simulation.rotation_angle, simulation.angular_velocity, simulation.rcs_propellant_remaining, simulation.fuel, simulation.stage_index, simulation.thrust_key_down])
			print("PATHFINDER CONTROL status=%s rcs_capacity=%.0f installed=%s gimbal=%.2f throttle=%.2f" % [simulation.status_message, simulation._remaining_rcs_propellant_capacity(), simulation.has_rcs_installed(), rad_to_deg(simulation.gimbal_angle), simulation.throttle])
			next_trace_time += 10.0
		if iterations >= 300000:
			break
	var body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	var orbit := FlightComputer.orbital_state(body.relative_position, simulation.velocity - body.velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
	var rcs_reserve_capacity := simulation._remaining_rcs_propellant_capacity()
	var rcs_reserve_valid := simulation.rcs_propellant_remaining + 0.1 >= rcs_reserve_capacity * 0.5
	var valid: bool = simulation.autopilot_complete and not simulation.crashed and bool(orbit.get("bound", false)) and absf(float(orbit.get("periapsis", 0.0)) - target_orbit_radius) < 5000.0 and absf(float(orbit.get("apoapsis", 0.0)) - target_orbit_radius) < 5000.0 and rcs_reserve_valid
	if not valid:
		push_error("Pathfinder LEO autopilot failed: phase=%s status=%s altitude=%.1f periapsis=%.1f apoapsis=%.1f fuel=%.1f rcs=%.1f/%.1f iterations=%d" % [simulation.autopilot_phase, simulation.status_message, float(body.distance) - PlanetarySystem.EARTH_RADIUS, float(orbit.get("periapsis", 0.0)) - PlanetarySystem.EARTH_RADIUS, float(orbit.get("apoapsis", INF)) - PlanetarySystem.EARTH_RADIUS, simulation.fuel, simulation.rcs_propellant_remaining, rcs_reserve_capacity, iterations])
	simulation.free()
	return valid

func _validate_leo_autopilot_mission(infinite_propellant: bool) -> bool:
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(RocketDesign.create_default())
	simulation.realism = "Realistic"
	simulation.infinite_weightless_fuel = infinite_propellant
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
	var target_orbit_period: float = TAU * sqrt(pow(target_orbit_radius, 3.0) / (PlanetarySystem.G * PlanetarySystem.EARTH_MASS))
	var mission_time_limit: float = target_orbit_period * 2.0
	var elapsed := 0.0
	var iterations := 0
	var previous_phase: String = simulation.autopilot_phase
	var phase_transitions: Array[String] = []
	while elapsed < mission_time_limit and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = simulation._adaptive_step_size()
		if step <= 0.000001:
			push_error("LEO %s mission produced an invalid physics step." % ("infinite-fuel" if infinite_propellant else "finite-fuel"))
			simulation.free()
			return false
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		if simulation.autopilot_phase != previous_phase:
			var transition_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
			var transition_orbit: Dictionary = FlightComputer.orbital_state(transition_body.relative_position, simulation.velocity - transition_body.velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
			if phase_transitions.size() < 30:
				phase_transitions.append("%.1f s %s>%s alt=%.0f radial=%.1f peri=%.0f apo=%.0f burn=%.1f" % [elapsed, previous_phase, simulation.autopilot_phase, float(transition_body.distance) - PlanetarySystem.EARTH_RADIUS, float(transition_orbit.get("radial_speed", INF)), float(transition_orbit.get("periapsis", 0.0)) - PlanetarySystem.EARTH_RADIUS, float(transition_orbit.get("apoapsis", INF)) - PlanetarySystem.EARTH_RADIUS, simulation.autopilot_burn_remaining])
			elif phase_transitions.size() == 30:
				phase_transitions.append("Further phase transitions omitted")
			previous_phase = simulation.autopilot_phase
		if iterations >= 300000:
			break
	print("LEO phase trace (%s): " % ("infinite" if infinite_propellant else "finite") + "; ".join(PackedStringArray(phase_transitions)))
	var end_body: Dictionary = simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise)
	var end_orbit: Dictionary = FlightComputer.orbital_state(end_body.relative_position, simulation.velocity - end_body.velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
	if simulation.crashed or not simulation.autopilot_complete:
		push_error("LEO %s mission failed: phase=%s status=%s elapsed=%.1f iterations=%d altitude=%.1f speed=%.1f radial_speed=%.1f periapsis_altitude=%.1f apoapsis_altitude=%.1f fuel=%.1f landed=%s crashed=%s transitions=%s" % ["infinite-fuel" if infinite_propellant else "finite-fuel", simulation.autopilot_phase, simulation.status_message, elapsed, iterations, float(end_body.distance) - PlanetarySystem.EARTH_RADIUS, simulation.velocity.length(), float(end_orbit.get("radial_speed", INF)), float(end_orbit.get("periapsis", 0.0)) - PlanetarySystem.EARTH_RADIUS, float(end_orbit.get("apoapsis", INF)) - PlanetarySystem.EARTH_RADIUS, simulation.fuel, simulation.landed, simulation.crashed, "; ".join(PackedStringArray(phase_transitions))])
		simulation.free()
		return false
	var earth_state: Dictionary = simulation._surface_body_state("Earth")
	var relative_position: Vector2 = simulation._relative_position_to_body(earth_state)
	var relative_velocity: Vector2 = simulation.velocity - Vector2(earth_state.velocity)
	var orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
	var orbit_failure := ""
	if not bool(orbit.get("valid", false)) or not bool(orbit.get("bound", false)):
		orbit_failure = "insertion did not produce a valid bound orbit"
	elif float(orbit.get("periapsis", 0.0)) <= PlanetarySystem.EARTH_RADIUS + 70000.0:
		orbit_failure = "insertion periapsis is below the safe-orbit floor"
	elif absf(float(orbit.get("periapsis", 0.0)) - target_orbit_radius) >= 5000.0:
		orbit_failure = "insertion periapsis missed the target altitude"
	elif absf(float(orbit.get("apoapsis", 0.0)) - target_orbit_radius) >= 5000.0:
		orbit_failure = "insertion apoapsis missed the target altitude"
	if not orbit_failure.is_empty():
		push_error("LEO %s mission %s: periapsis=%.1f km apoapsis=%.1f km." % ["infinite-fuel" if infinite_propellant else "finite-fuel", orbit_failure, (float(orbit.get("periapsis", 0.0)) - PlanetarySystem.EARTH_RADIUS) / 1000.0, (float(orbit.get("apoapsis", 0.0)) - PlanetarySystem.EARTH_RADIUS) / 1000.0])
		simulation.free()
		return false
	var orbital_period := TAU * sqrt(pow(float(orbit.get("semi_major_axis", 0.0)), 3.0) / (PlanetarySystem.G * PlanetarySystem.EARTH_MASS))
	var coast_elapsed := 0.0
	while coast_elapsed < orbital_period:
		var step: float = minf(simulation._adaptive_step_size(), orbital_period - coast_elapsed)
		if step <= 0.000001:
			push_error("LEO %s orbit produced an invalid coast step." % ("infinite-fuel" if infinite_propellant else "finite-fuel"))
			simulation.free()
			return false
		simulation._physics_step(step)
		coast_elapsed += step
		if simulation.crashed or simulation.landed:
			push_error("LEO %s orbit did not survive one full revolution: crashed=%s landed=%s altitude=%.1f." % ["infinite-fuel" if infinite_propellant else "finite-fuel", simulation.crashed, simulation.landed, simulation.rocket_position.length() - PlanetarySystem.EARTH_RADIUS])
			simulation.free()
			return false
	var coast_earth_state: Dictionary = simulation._surface_body_state("Earth")
	var coast_position: Vector2 = simulation._relative_position_to_body(coast_earth_state)
	var coast_velocity: Vector2 = simulation.velocity - Vector2(coast_earth_state.velocity)
	var coast_orbit: Dictionary = FlightComputer.orbital_state(coast_position, coast_velocity, PlanetarySystem.G * PlanetarySystem.EARTH_MASS)
	if not bool(coast_orbit.get("bound", false)) or float(coast_orbit.get("periapsis", 0.0)) <= PlanetarySystem.EARTH_RADIUS + 70000.0:
		push_error("LEO %s orbit became unbound or unsafe after one revolution." % ("infinite-fuel" if infinite_propellant else "finite-fuel"))
		simulation.free()
		return false
	simulation.free()
	return true
