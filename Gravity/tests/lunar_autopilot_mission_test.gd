extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var design: Dictionary = RocketDesign.create_default()
	var start_radius: float = PlanetarySystem.EARTH_RADIUS + 200000.0
	var start_position := Vector2(0.0, -start_radius)
	var start_velocity := Vector2(FlightComputer.circular_orbit_speed(start_radius), 0.0)
	var available_delta_v: float = FlightComputer.available_delta_v(design)
	var plan: Dictionary = FlightComputer.simulated_transfer_search_precise(
		PackedFloat64Array([start_position.x, start_position.y]),
		start_velocity,
		0.0,
		-1,
		available_delta_v,
		0.0,
		false,
		200000.0
	)
	assert(bool(plan.get("valid", false)), "Earth-to-Moon transfer planner found no feasible route: %s" % str(plan.get("reason", "unknown reason")))
	plan["target_id"] = -1
	plan["target_altitude"] = 200000.0
	plan["planned_at_time"] = 0.0
	plan["planned_position"] = start_position
	plan["planned_velocity"] = start_velocity
	print("Lunar transfer plan: departure=%.1f m/s capture=%.1f m/s flight=%.2f days closest=%.0f km" % [
		float(plan.get("departure_delta_v", 0.0)),
		float(plan.get("capture_delta_v", 0.0)),
		float(plan.get("transfer_time", 0.0)) / 86400.0,
		float(plan.get("closest_approach", INF)) / 1000.0
	])
	if not _run_lunar_mission(design, plan, false, start_position, start_velocity):
		quit(1)
		return
	if not _run_lunar_mission(design, plan, true, start_position, start_velocity):
		quit(1)
		return
	print("End-to-end Earth-to-Moon autopilot missions passed with finite and infinite propellant.")
	quit(0)


func _run_lunar_mission(design: Dictionary, plan: Dictionary, infinite_propellant: bool, start_position: Vector2, start_velocity: Vector2) -> bool:
	var simulation: Variant = SimulationView.new()
	simulation.set_rocket_design(design)
	simulation.realism = "Realistic"
	simulation.infinite_weightless_fuel = infinite_propellant
	simulation.landed = false
	simulation._set_rocket_position_components(start_position.x, start_position.y)
	simulation.velocity = start_velocity
	simulation.autopilot_enabled = true
	simulation.guidance_enabled = true
	simulation.autopilot_target_mode = "ORBIT"
	simulation.autopilot_target_altitude = 200000.0
	simulation.autopilot_planet_index = -1
	simulation.autopilot_precomputed_transfer_plan = plan.duplicate(true)
	simulation.autopilot_phase = "PLAN_TRANSFER"
	var elapsed := 0.0
	var iterations := 0
	var previous_phase: String = simulation.autopilot_phase
	var phase_transitions: Array[String] = []
	var mission_time_limit := 45.0 * 86400.0
	while elapsed < mission_time_limit and not simulation.autopilot_complete and simulation.autopilot_phase != "FAILED" and not simulation.crashed:
		var step: float = simulation._adaptive_step_size()
		if step <= 0.000001:
			push_error("Lunar %s mission produced an invalid physics step." % ("infinite-fuel" if infinite_propellant else "finite-fuel"))
			simulation.free()
			return false
		step = minf(step, mission_time_limit - elapsed)
		simulation._physics_step(step)
		elapsed += step
		iterations += 1
		if simulation.autopilot_phase != previous_phase:
			var moon_state: Dictionary = simulation._surface_body_state("Moon")
			var relative_position: Vector2 = simulation._relative_position_to_body(moon_state)
			var relative_velocity: Vector2 = simulation.velocity - Vector2(moon_state.get("velocity", Vector2.ZERO))
			var moon_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(moon_state.get("mass", 0.0)))
			if phase_transitions.size() < 40:
				phase_transitions.append("%.2f d %s>%s range=%.0f km radial=%.1f speed=%.1f burn=%.1f" % [
					elapsed / 86400.0,
					previous_phase,
					simulation.autopilot_phase,
					relative_position.length() / 1000.0,
					float(moon_orbit.get("radial_speed", INF)),
					relative_velocity.length(),
					simulation.autopilot_burn_remaining
				])
			previous_phase = simulation.autopilot_phase
		if iterations >= 500000:
			break
	var moon_state: Dictionary = simulation._surface_body_state("Moon")
	var relative_position: Vector2 = simulation._relative_position_to_body(moon_state)
	var relative_velocity: Vector2 = simulation.velocity - Vector2(moon_state.get("velocity", Vector2.ZERO))
	var moon_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(moon_state.get("mass", 0.0)))
	var diagnostic := "phase=%s status=%s elapsed=%.2f d range=%.0f km speed=%.1f radial=%.1f periapsis_alt=%.1f km apoapsis_alt=%.1f km fuel=%.1f iterations=%d transitions=%s" % [
		simulation.autopilot_phase,
		simulation.status_message,
		elapsed / 86400.0,
		relative_position.length() / 1000.0,
		relative_velocity.length(),
		float(moon_orbit.get("radial_speed", INF)),
		(float(moon_orbit.get("periapsis", 0.0)) - float(moon_state.get("radius", 0.0))) / 1000.0,
		(float(moon_orbit.get("apoapsis", INF)) - float(moon_state.get("radius", 0.0))) / 1000.0,
		simulation.fuel,
		iterations,
		"; ".join(PackedStringArray(phase_transitions))
	]
	if simulation.crashed or not simulation.autopilot_complete:
		push_error("Lunar %s mission failed: %s" % ["infinite-fuel" if infinite_propellant else "finite-fuel", diagnostic])
		simulation.free()
		return false
	if str(simulation._nearest_body_state(simulation.rocket_position, simulation.rocket_position_precise).get("name", "")) != "Moon":
		push_error("Lunar %s mission completed without entering lunar orbit: %s" % ["infinite-fuel" if infinite_propellant else "finite-fuel", diagnostic])
		simulation.free()
		return false
	var target_radius := float(moon_state.get("radius", 0.0)) + 200000.0
	if not bool(moon_orbit.get("bound", false)) or absf(float(moon_orbit.get("periapsis", 0.0)) - target_radius) > 10000.0 or absf(float(moon_orbit.get("apoapsis", 0.0)) - target_radius) > 10000.0:
		push_error("Lunar %s mission did not achieve the requested circular orbit: %s" % ["infinite-fuel" if infinite_propellant else "finite-fuel", diagnostic])
		simulation.free()
		return false
	print("Lunar %s mission passed: %s" % ["infinite-fuel" if infinite_propellant else "finite-fuel", diagnostic])
	simulation.free()
	return true
