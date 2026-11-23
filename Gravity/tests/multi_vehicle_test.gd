extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")

func _initialize() -> void:
	var main := Main.new()
	root.add_child(main)
	main.rocket_design = RocketDesign.create_default()
	main._start_flight()
	assert(main.fleet_sims.size() == 1)
	var first: SimulationView = main.fleet_sims[0]
	main._add_new_vehicle()
	assert(main.fleet_sims.size() == 2)
	var second: SimulationView = main.sim
	assert(first != second)
	assert(first.visible == false)
	assert(second.visible)
	assert(not first.input_enabled)
	assert(second.input_enabled)
	assert(first.vehicle_name == "Vehicle 1")
	assert(second.vehicle_name == "Vehicle 2")
	main._switch_vehicle(0)
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_W
	key_event.pressed = true
	second._input(key_event)
	assert(not second.thrust_key_down)
	assert(main.sim == first)
	assert(first.visible)
	assert(not second.visible)
	assert(first.input_enabled)
	assert(not second.input_enabled)
	second.landed = false
	second.rocket_position = Vector2(PlanetarySystem.EARTH_RADIUS + 200000.0, 0.0)
	second.velocity = Vector2(0.0, 7780.0)
	second.autopilot_enabled = true
	second.autopilot_phase = "TRANSFER_COAST"
	var second_start_position := second.rocket_position
	main._advance_fleet(0.02)
	assert(first.sim_time > 0.0)
	assert(is_equal_approx(first.sim_time, second.sim_time))
	assert(second.rocket_position.distance_to(second_start_position) > 0.0)
	assert(second.autopilot_enabled)
	assert(first.vehicle_name == "Vehicle 1")
	assert(second.vehicle_name == "Vehicle 2")
	main._switch_vehicle(1)
	main.save_slot = 8
	main._save_game(false)
	var save_path := "user://saves/slot_08.json"
	assert(FileAccess.file_exists(save_path))
	var save_file := FileAccess.open(save_path, FileAccess.READ)
	var saved_data: Dictionary = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	assert(saved_data.get("vehicles", []).size() == 2)
	assert(int(saved_data.get("active_vehicle_index", -1)) == 1)
	main._load_game_from_path(save_path)
	assert(main.fleet_sims.size() == 2)
	assert(main.active_vehicle_index == 1)
	assert(main.sim.vehicle_name == "Vehicle 2")
	assert(is_equal_approx(main.fleet_sims[0].sim_time, main.fleet_sims[1].sim_time))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Multi-vehicle simulation test passed.")
	main.queue_free()
	quit()
