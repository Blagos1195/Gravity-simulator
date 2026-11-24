extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	var original_mass := RocketDesign.total_initial_mass(design)
	for component_id in ["payload_fairing", "solar_panel_array", "high_gain_antenna", "docking_port", "science_instrument"]:
		assert(RocketDesign.add_payload_component(design, component_id))
	assert(RocketDesign.validation_errors(design).is_empty())
	assert(RocketDesign.total_initial_mass(design) > original_mass)
	assert(RocketDesign.has_payload_component(design, "fairing"))
	var saved_mod_design := design.duplicate(true)
	saved_mod_design["payload_components"][0] = {"id": "removed_mod_component", "definition": RocketDesign.payload_component_definition("payload_fairing")}
	assert(RocketDesign.validation_errors(saved_mod_design).is_empty())
	var sim := SimulationView.new()
	sim.set_rocket_design(design)
	sim.landed = false
	var radius := PlanetarySystem.EARTH_RADIUS + 200000.0
	sim.rocket_position = Vector2(0.0, -radius)
	sim.velocity = Vector2(FlightComputer.circular_orbit_speed(radius), 0.0)
	var mass_before_jettison := sim._current_vehicle_mass()
	assert(sim.can_jettison_fairing())
	assert(sim.jettison_fairing())
	assert(not sim.can_jettison_fairing())
	assert(is_equal_approx(mass_before_jettison - sim._current_vehicle_mass(), 1200.0))
	var saved_data := sim.get_save_data()
	var restored := SimulationView.new()
	assert(restored.load_save_data(saved_data))
	assert(restored.fairing_jettisoned)
	assert(restored.payload_components.size() == 5)
	print("Payload component tests passed.")
	sim.free()
	restored.free()
	quit()
