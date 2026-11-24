extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")

func _initialize() -> void:
	var main := Main.new()
	root.add_child(main)
	main.career_enabled = true
	main.funds = 100000000.0
	main._start_flight()
	var design := RocketDesign.create_default()
	design["payload_mass"] = 150.0
	design["payload_type"] = "satellite"
	design["payload_visual"] = RocketDesign.payload_visual_data("satellite")
	var funds_before_launch := main.funds
	var expected_launch_cost := main._launch_cost_for_design(design)
	main._launch_vehicle_design(design)
	assert(main.fleet_sims.size() == 2)
	assert(is_equal_approx(main.funds, funds_before_launch - expected_launch_cost))
	var satellite: SimulationView = main.sim
	var radius := PlanetarySystem.EARTH_RADIUS + 200000.0
	satellite.landed = false
	satellite.rocket_position = Vector2(0.0, -radius)
	satellite.velocity = Vector2(FlightComputer.circular_orbit_speed(radius), 0.0)
	satellite.launch_time = 0.0
	satellite.sim_time = 86400.0
	var primary: SimulationView = main.fleet_sims[0]
	primary.sim_time = 86400.0
	primary.rocket_position = Vector2(1.0e9, 0.0)
	main._switch_vehicle(0)
	main.economy_last_sim_time = 0.0
	var funds_before_income := main.funds
	main._update_economy()
	assert(is_equal_approx(main.funds - funds_before_income, 11000.0), "Stable satellite did not generate its configured net daily revenue")
	main.economy_last_sim_time = 3650.0 * 86400.0
	primary.sim_time = 3651.0 * 86400.0
	satellite.sim_time = primary.sim_time
	var funds_after_lifetime := main.funds
	main._update_economy()
	assert(is_equal_approx(main.funds, funds_after_lifetime), "Expired satellite continued generating revenue")
	assert(main._decommission_vehicle(satellite))
	assert(main.fleet_sims.size() == 1)
	main.funds = 1234567.0
	main.save_slot = 1
	main._save_game(false)
	var save_path := "user://saves/slot_01.json"
	var file := FileAccess.open(save_path, FileAccess.READ)
	var saved_data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	assert(is_equal_approx(float(saved_data.get("funds", 0.0)), 1234567.0))
	main.funds = 0.0
	main._load_game_from_path(save_path)
	assert(is_equal_approx(main.funds, 1234567.0), "Career funds were not restored from the save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	main.queue_free()
	print("Career economy tests passed.")
	quit()
