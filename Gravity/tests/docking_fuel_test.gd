extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")
const ModuleGraph = preload("res://scripts/module_graph.gd")

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
	var expected_assist_delta_v := minf(0.15, 1800.0 / parent._current_vehicle_mass())
	var rcs_fuel_before_assist := parent.rcs_propellant_remaining
	main._apply_docking_assists(1.0)
	assert(is_equal_approx(parent.velocity.x, expected_assist_delta_v), "Rendezvous assist did not use the available RCS thrust")
	assert(parent.rcs_propellant_remaining < rcs_fuel_before_assist, "Rendezvous assist did not consume RCS propellant")
	main.docking_assists.clear()
	parent.rocket_position = Vector2(1000000.0, 2000000.0)
	child.rocket_position = parent.rocket_position + Vector2(25.0, 0.0)
	parent.velocity = Vector2(0.0, 1000.0)
	child.velocity = Vector2(0.0, 1003.0)
	var child_stage_with_port: Dictionary = child.rocket_stages[0].duplicate(true)
	var port_component_index := -1
	for index in range(child_stage_with_port.components.size()):
		if str(child_stage_with_port.components[index].get("kind", "")) == "docking_port":
			port_component_index = index
	assert(port_component_index >= 0)
	var rcs_component_index := -1
	for index in range(child_stage_with_port.components.size()):
		if str(child_stage_with_port.components[index].get("kind", "")) == "rcs":
			rcs_component_index = index
	assert(rcs_component_index >= 0)
	child.rocket_stages[0] = RocketAssembly.remove_component(child_stage_with_port, rcs_component_index)
	assert(not main._dock_vehicle(child.vehicle_name), "A spacecraft without RCS hardware connected")
	child.rocket_stages[0] = child_stage_with_port
	child.rocket_stages[0] = RocketAssembly.remove_component(child_stage_with_port, port_component_index)
	assert(not main._dock_vehicle(child.vehicle_name), "A spacecraft without a docking port connected")
	child.rocket_stages[0] = child_stage_with_port
	child.rotation_angle = 0.0
	assert(not main._dock_vehicle(child.vehicle_name), "Misaligned docking ports connected")
	child.rotation_angle = PI
	child.rcs_propellant_remaining = 0.0
	assert(not child.has_rcs() and child.has_rcs_installed())
	child.velocity = Vector2(0.0, 1001.0)
	assert(main._dock_vehicle(child.vehicle_name), "An RCS-equipped spacecraft could not dock manually with empty propellant")
	assert(main._undock_vehicle(child.vehicle_name))
	child.rotation_angle = PI
	child.rcs_propellant_remaining = child._remaining_rcs_propellant_capacity()
	child.velocity = Vector2(0.0, 1003.0)
	assert(not main._dock_vehicle(child.vehicle_name))
	child.velocity = Vector2(0.0, 1001.0)
	assert(main._dock_vehicle(child.vehicle_name))
	assert(main.docking_links.size() == 1)
	assert(main.docking_assists.is_empty(), "Docking did not stop rendezvous assist")
	assert(not child.input_enabled)
	assert(is_equal_approx(parent.docked_mass, child._current_vehicle_mass()))
	parent.rocket_stages[0] = RocketAssembly.add_component(parent.rocket_stages[0], "standard_docking_port")
	child.rocket_stages[0] = RocketAssembly.add_component(child.rocket_stages[0], "standard_docking_port")
	var parent_parallel_port: Dictionary = parent.docking_port_world_states()[1]
	var child_parallel_port: Dictionary = child.docking_port_world_states()[1]
	child.rocket_position = Vector2(parent_parallel_port.position) - (Vector2(child_parallel_port.position) - child.rocket_position)
	var first_connection_port := str(main.docking_links[0].get("port_a", ""))
	assert(main._dock_vehicle(child.vehicle_name), "A second independent connector could not join an already docked pair")
	assert(main.docking_links.size() == 2)
	assert(is_equal_approx(parent.docked_mass, child._current_vehicle_mass()), "A second connector double-counted the docked mass")
	assert(main._undock_vehicle(child.vehicle_name, first_connection_port), "The first parallel connector could not be released")
	assert(main.docking_links.size() == 1 and child.resource_inventory_external, "Releasing one of two connectors incorrectly separated the spacecraft")
	var remaining_connection_port := str(main.docking_links[0].get("port_a", ""))
	assert(main._undock_vehicle(child.vehicle_name, remaining_connection_port), "The final parallel connector could not be released")
	assert(main.docking_links.is_empty() and not child.resource_inventory_external, "The spacecraft remained connected after its final connector was released")
	assert(main._dock_vehicle(child.vehicle_name, first_connection_port), "The spacecraft could not reconnect after a complete undock")
	parent.rocket_stages[0] = RocketAssembly.add_component(parent.rocket_stages[0], "standard_docking_port")
	var second_parent_port: Dictionary = parent.docking_port_world_states()[1]
	var second_child_port: Dictionary = second_child.docking_port_world_state()
	second_child.rocket_position = Vector2(second_parent_port.position) - (Vector2(second_child_port.position) - second_child.rocket_position)
	second_child.velocity = Vector2(0.0, 1001.0)
	assert(main._dock_vehicle(second_child.vehicle_name))
	assert(main.docking_links.size() == 2)
	assert(not second_child.input_enabled)
	second_child.rocket_stages[0] = RocketAssembly.add_component(second_child.rocket_stages[0], "standard_docking_port")
	var child_loop_port: Dictionary = child.docking_port_world_states()[1]
	var second_loop_stage: Dictionary = second_child.rocket_stages[0].duplicate(true)
	second_loop_stage.components[second_loop_stage.components.size() - 1]["rotation_deg"] = 180.0
	second_child.rocket_stages[0] = RocketAssembly.compile_stage(second_loop_stage, second_loop_stage.components)
	var second_loop_port: Dictionary = second_child.docking_port_world_states()[1]
	second_child.rocket_position = Vector2(child_loop_port.position) - (Vector2(second_loop_port.position) - second_child.rocket_position)
	main.sim = child
	assert(main._dock_vehicle(second_child.vehicle_name, str(child_loop_port.get("part_uid", ""))), "A loop between modules in one connected assembly could not be created")
	assert(main.docking_links.size() == 3)
	assert(ModuleGraph.connection_between(main._current_module_graph(), child.vehicle_name, second_child.vehicle_name).size() == 1)
	assert(main._undock_vehicle(second_child.vehicle_name, str(child_loop_port.get("part_uid", ""))), "An additional assembly loop could not be released")
	assert(main.docking_links.size() == 2 and main._are_docked(parent.vehicle_name, second_child.vehicle_name))
	main.sim = parent
	parent.resource_tanks.append({"part_uid":"child_xenon_test","module_id":child.vehicle_name,"resources":{"xenon":50.0},"resource_capacities":{"xenon":100.0}})
	parent.resource_tanks.append({"part_uid":"second_child_xenon_test","module_id":second_child.vehicle_name,"resources":{"xenon":0.0},"resource_capacities":{"xenon":100.0}})
	var transitive_resource_transfer := main._transfer_between_tanks(child.vehicle_name, "child_xenon_test", second_child.vehicle_name, "second_child_xenon_test", "xenon", 30.0)
	assert(is_equal_approx(transitive_resource_transfer, 30.0), "Connected modules could not transfer resources through the assembly graph")
	assert(is_equal_approx(float(parent.resource_tanks[parent.resource_tanks.size() - 2].resources.xenon), 20.0))
	assert(is_equal_approx(float(parent.resource_tanks[parent.resource_tanks.size() - 1].resources.xenon), 30.0))
	var expected_docked_mass := child._current_vehicle_mass() + second_child._current_vehicle_mass()
	assert(absf(parent.docked_mass - expected_docked_mass) < 0.01)
	assert(main._rename_vehicle(parent.vehicle_name, "Orbital Tug"))
	assert(main._are_docked("Orbital Tug", child.vehicle_name))
	var parent_capacity := float(parent._active_stage_data().get("fuel_capacity", 0.0))
	parent.rcs_propellant_remaining = parent._remaining_rcs_propellant_capacity()
	parent.fuel = parent_capacity - 10000.0
	parent.stage_fuel_remaining[0] = parent.fuel
	child.fuel = 0.0
	child.stage_fuel_remaining[0] = 0.0
	child.stage_fuel_remaining[1] = 10000.0
	main._sync_external_module_fuel(child, parent)
	main._update_docked_masses()
	var combined_mass_before := parent._current_vehicle_mass()
	var transferred := main._transfer_fuel(child.vehicle_name, parent.vehicle_name)
	assert(is_equal_approx(transferred, 10000.0))
	assert(is_equal_approx(parent.fuel, parent_capacity))
	assert(is_zero_approx(child.stage_fuel_remaining[1]))
	assert(is_zero_approx(child.total_propellant_remaining()))
	assert(is_equal_approx(parent._current_vehicle_mass(), combined_mass_before))
	var parent_rcs_capacity := parent._remaining_rcs_propellant_capacity()
	assert(is_equal_approx(parent.rcs_propellant_remaining, parent_rcs_capacity))
	var combined_mass_before_rcs_transfer := parent._current_vehicle_mass()
	var rcs_transferred := main._transfer_fuel(child.vehicle_name, parent.vehicle_name)
	assert(is_zero_approx(rcs_transferred))
	assert(is_equal_approx(parent.rcs_propellant_remaining, parent_rcs_capacity))
	assert(is_equal_approx(parent._current_vehicle_mass(), combined_mass_before_rcs_transfer))
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
