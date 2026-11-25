extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")

func _initialize() -> void:
	var main := Main.new()
	root.add_child(main)
	var docking_design := RocketDesign.create_default()
	var docking_stage := RocketAssembly.add_component(docking_design.stages[0], "rcs_thruster_block")
	docking_stage = RocketAssembly.add_component(docking_stage, "standard_docking_port")
	docking_design["stages"][0] = docking_stage
	main.rocket_design = docking_design
	main._start_flight()
	main._add_new_vehicle()
	main._add_new_vehicle()
	var parent: SimulationView = main.fleet_sims[0]
	var child: SimulationView = main.fleet_sims[1]
	var second_child: SimulationView = main.fleet_sims[2]
	main._switch_vehicle(0)
	parent.landed = false
	child.landed = false
	second_child.landed = false
	child.rotation_angle = PI
	second_child.rotation_angle = PI
	parent.rocket_position = Vector2(1000000.0, 2000000.0)
	child.rocket_position = parent.rocket_position + Vector2(25.0, 0.0)
	parent.velocity = Vector2(12.0, 0.0)
	child.velocity = Vector2.ZERO
	child.rocket_position = parent.rocket_position + Vector2(10000.0, 0.0)
	main.docking_assists[parent.vehicle_name] = child.vehicle_name
	main._apply_docking_assists(1.0)
	assert(parent.velocity.x < 12.0 and parent.velocity.x > 0.0, "Rendezvous assist did not brake relative closing speed")
	parent.velocity = Vector2.ZERO
	var expected_assist_delta_v := minf(0.15, 18000.0 / parent._current_vehicle_mass())
	main._apply_docking_assists(1.0)
	assert(is_equal_approx(parent.velocity.x, expected_assist_delta_v), "Rendezvous assist did not use the available RCS thrust")
	main.docking_assists.clear()
	parent.rocket_position = Vector2(1000000.0, 2000000.0)
	child.rocket_position = parent.rocket_position + Vector2(25.0, 0.0)
	parent.velocity = Vector2(0.0, 1000.0)
	child.velocity = Vector2(0.0, 1003.0)
	assert(not main._dock_vehicle(child.vehicle_name))
	child.velocity = Vector2(0.0, 1001.0)
	assert(main._dock_vehicle(child.vehicle_name))
	assert(main.docking_links.size() == 1)
	assert(main.docking_assists.is_empty(), "Docking did not stop rendezvous assist")
	assert(not child.input_enabled)
	assert(is_equal_approx(parent.docked_mass, child._current_vehicle_mass()))
	second_child.rocket_position = parent.rocket_position + Vector2(-25.0, 0.0)
	second_child.velocity = Vector2(0.0, 1001.0)
	assert(main._dock_vehicle(second_child.vehicle_name))
	assert(main.docking_links.size() == 2)
	assert(not second_child.input_enabled)
	assert(is_equal_approx(parent.docked_mass, child._current_vehicle_mass() + second_child._current_vehicle_mass()))
	assert(main._rename_vehicle(parent.vehicle_name, "Orbital Tug"))
	assert(main._are_docked("Orbital Tug", child.vehicle_name))
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
	var parent_rcs_capacity := parent._remaining_rcs_propellant_capacity()
	parent.rcs_propellant_remaining = parent_rcs_capacity - 100.0
	child.rcs_propellant_remaining = child._remaining_rcs_propellant_capacity()
	var rcs_transferred := main._transfer_fuel(child.vehicle_name, parent.vehicle_name)
	assert(is_equal_approx(rcs_transferred, 100.0))
	assert(is_equal_approx(parent.rcs_propellant_remaining, parent_rcs_capacity))
	assert(is_equal_approx(child.rcs_propellant_remaining, child._remaining_rcs_propellant_capacity() - 100.0))
	assert(is_equal_approx(parent._current_vehicle_mass(), combined_mass_before))
	main.save_slot = 8
	main._save_game(false)
	var save_path := "user://saves/slot_08.json"
	assert(FileAccess.file_exists(save_path))
	main._load_game_from_path(save_path)
	assert(main.docking_links.size() == 2)
	assert(main.fleet_sims.size() == 3)
	var loaded_parent: SimulationView = main.fleet_sims[0]
	var loaded_child: SimulationView = main.fleet_sims[1]
	var loaded_second_child: SimulationView = main.fleet_sims[2]
	assert(not loaded_child.input_enabled)
	assert(not loaded_second_child.input_enabled)
	assert(is_equal_approx(loaded_parent.docked_mass, loaded_child._current_vehicle_mass() + loaded_second_child._current_vehicle_mass()))
	assert(is_zero_approx(loaded_child.stage_fuel_remaining[1]))
	assert(is_equal_approx(loaded_parent.rcs_propellant_remaining, parent_rcs_capacity))
	assert(is_equal_approx(loaded_parent.stage_fuel_remaining[0], float(loaded_parent._active_stage_data().get("fuel_capacity", 0.0))))
	assert(main._undock_vehicle(loaded_child.vehicle_name))
	assert(main._undock_vehicle(loaded_second_child.vehicle_name))
	assert(main.docking_links.is_empty())
	assert(is_zero_approx(loaded_parent.docked_mass))
	main.docking_assists[loaded_parent.vehicle_name] = loaded_child.vehicle_name
	main._save_game(false)
	main._load_game_from_path(save_path)
	assert(str(main.docking_assists.get(loaded_parent.vehicle_name, "")) == loaded_child.vehicle_name, "Rendezvous assist state was not restored from save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Docking and fuel transfer test passed.")
	main.queue_free()
	quit()
