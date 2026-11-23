extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")

func _initialize() -> void:
	var main := Main.new()
	root.add_child(main)
	main.rocket_design = RocketDesign.create_default()
	main._start_flight()
	main._add_new_vehicle()
	var parent: SimulationView = main.fleet_sims[0]
	var child: SimulationView = main.fleet_sims[1]
	main._switch_vehicle(0)
	parent.landed = false
	child.landed = false
	parent.rocket_position = Vector2(1000000.0, 2000000.0)
	child.rocket_position = parent.rocket_position + Vector2(25.0, 0.0)
	parent.velocity = Vector2(0.0, 1000.0)
	child.velocity = Vector2(0.0, 1003.0)
	assert(not main._dock_vehicle(child.vehicle_name))
	child.velocity = Vector2(0.0, 1001.0)
	assert(main._dock_vehicle(child.vehicle_name))
	assert(main.docking_links.size() == 1)
	assert(not child.input_enabled)
	assert(is_equal_approx(parent.docked_mass, child._current_vehicle_mass()))
	var parent_capacity := float(parent._active_stage_data().get("fuel_capacity", 0.0))
	parent.fuel = parent_capacity - 10000.0
	parent.stage_fuel_remaining[0] = parent.fuel
	child.fuel = 0.0
	child.stage_fuel_remaining[0] = 0.0
	child.stage_fuel_remaining[1] = 10000.0
	main._update_docked_masses()
	var combined_mass_before := parent._current_vehicle_mass()
	var transferred := main._transfer_fuel(child.vehicle_name, parent.vehicle_name)
	assert(is_equal_approx(transferred, 10000.0))
	assert(is_equal_approx(parent.fuel, parent_capacity))
	assert(is_zero_approx(child.stage_fuel_remaining[1]))
	assert(is_zero_approx(child.total_propellant_remaining()))
	assert(is_equal_approx(parent._current_vehicle_mass(), combined_mass_before))
	main.save_slot = 8
	main._save_game(false)
	var save_path := "user://saves/slot_08.json"
	assert(FileAccess.file_exists(save_path))
	main._load_game_from_path(save_path)
	assert(main.docking_links.size() == 1)
	assert(main.fleet_sims.size() == 2)
	var loaded_parent: SimulationView = main.fleet_sims[0]
	var loaded_child: SimulationView = main.fleet_sims[1]
	assert(not loaded_child.input_enabled)
	assert(is_equal_approx(loaded_parent.docked_mass, loaded_child._current_vehicle_mass()))
	assert(is_zero_approx(loaded_child.stage_fuel_remaining[1]))
	assert(is_equal_approx(loaded_parent.stage_fuel_remaining[0], float(loaded_parent._active_stage_data().get("fuel_capacity", 0.0))))
	assert(main._undock_vehicle(loaded_child.vehicle_name))
	assert(main.docking_links.is_empty())
	assert(is_zero_approx(loaded_parent.docked_mass))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Docking and fuel transfer test passed.")
	main.queue_free()
	quit()
