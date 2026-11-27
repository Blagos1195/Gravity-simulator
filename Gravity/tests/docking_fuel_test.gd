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
	var orbit_radius := SimulationView.EARTH_RADIUS + 200000.0
	var orbit_speed := sqrt(SimulationView.G * SimulationView.EARTH_MASS / orbit_radius)
	parent.rocket_position = Vector2(orbit_radius, 0.0)
	child.rocket_position = Vector2(-orbit_radius, 0.0)
	parent.velocity = Vector2(0.0, orbit_speed)
	child.velocity = Vector2(0.0, -orbit_speed)
	assert(main._docking_orbit_altitudes_compatible(parent, child), "Spacecraft in the same orbital altitude band were not recognised")
	assert(main._docking_assist_in_range(parent, child), "Same-altitude spacecraft outside the distance limit were not eligible for rendezvous")
	var orbital_approach := main._docking_orbit_approach(parent, child)
	assert(absf(Vector2(orbital_approach.direction).dot((child.rocket_position - parent.rocket_position).normalized())) < 0.01, "Distant orbital rendezvous attempted a direct path through the central body")
	parent.rocket_position = Vector2.ZERO
	child.rocket_position = Vector2(100000.0, 0.0)
	second_child.rocket_position = Vector2(5000.0, 0.0)
	parent.velocity = Vector2.ZERO
	child.velocity = Vector2.ZERO
	second_child.velocity = Vector2.ZERO
	var avoidance_velocity := main._docking_avoidance_velocity(parent, child, Vector2(100.0, 0.0))
	assert(avoidance_velocity.distance_to(Vector2(100.0, 0.0)) > 1.0, "Docking rendezvous did not steer around a spacecraft crossing its approach path")
	assert(absf((avoidance_velocity - Vector2(100.0, 0.0)).dot(Vector2.RIGHT)) < 0.01, "Docking traffic avoidance did not choose a lateral path")
	var own_approach_port := {"position": parent.rocket_position, "normal": Vector2.LEFT}
	var far_side_port := {"position": child.rocket_position, "normal": Vector2.RIGHT}
	var approach_waypoint := main._docking_approach_waypoint(parent, child, own_approach_port, far_side_port)
	var required_clearance := RocketDesign.vehicle_collision_radius_m({"stages": parent.rocket_stages}, parent.stage_index) + RocketDesign.vehicle_collision_radius_m({"stages": child.rocket_stages}, child.stage_index) + 500.0
	assert(approach_waypoint.distance_to(child.rocket_position) >= required_clearance - 1.0, "Far-side docking waypoint entered the spacecraft collision boundary")
	assert(absf(approach_waypoint.y - child.rocket_position.y) > 1.0, "Far-side docking approach tried to pass straight through the spacecraft")
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
	var child_loop_port_uid := str(child_loop_port.get("part_uid", ""))
	assert(ModuleGraph.connection_between(main._current_module_graph(), child.vehicle_name, second_child.vehicle_name).size() == 1)
	assert(main._are_docked(parent.vehicle_name, second_child.vehicle_name))
	main.sim = parent
	parent.resource_tanks.append({"part_uid":"child_xenon_test","module_id":child.vehicle_name,"resources":{"xenon":50.0},"resource_capacities":{"xenon":100.0}})
	parent.resource_tanks.append({"part_uid":"second_child_xenon_test","module_id":second_child.vehicle_name,"resources":{"xenon":0.0},"resource_capacities":{"xenon":100.0}})
	var transitive_resource_transfer := main._transfer_between_tanks(child.vehicle_name, "child_xenon_test", second_child.vehicle_name, "second_child_xenon_test", "xenon", 30.0)
	assert(is_equal_approx(transitive_resource_transfer, 30.0), "Connected modules could not transfer resources through the assembly graph")
	assert(is_equal_approx(float(parent.resource_tanks[parent.resource_tanks.size() - 2].resources.xenon), 20.0))
	assert(is_equal_approx(float(parent.resource_tanks[parent.resource_tanks.size() - 1].resources.xenon), 30.0))
	assert(main._module_rcs_propellant_capacity(parent) >= 100.0)
	assert(main._module_rcs_propellant_capacity(child) >= 100.0)
	parent.docked_rcs_propellant[child.vehicle_name] = 100.0
	parent.docked_rcs_propellant[second_child.vehicle_name] = 0.0
	parent.rcs_propellant_remaining = 100.0
	main._sync_docked_vehicles()
	var combined_mass_before_rcs_transfer := parent._current_vehicle_mass()
	var rcs_transfer_to_parent := main._transfer_between_tanks(child.vehicle_name, "__rcs_propellant__", parent.vehicle_name, "__rcs_propellant__", "rcs_propellant", 40.0)
	assert(is_equal_approx(rcs_transfer_to_parent, 40.0), "Docked RCS propellant could not be transferred into the parent spacecraft")
	assert(is_equal_approx(float(parent.docked_rcs_propellant[child.vehicle_name]), 60.0))
	assert(is_equal_approx(main._module_rcs_propellant_amount(parent, parent), 40.0))
	assert(is_equal_approx(parent.rcs_propellant_remaining, 100.0))
	assert(is_equal_approx(parent._current_vehicle_mass(), combined_mass_before_rcs_transfer))
	var rcs_transfer_back := main._transfer_between_tanks(parent.vehicle_name, "__rcs_propellant__", child.vehicle_name, "__rcs_propellant__", "rcs_propellant", 25.0)
	assert(is_equal_approx(rcs_transfer_back, 25.0), "RCS propellant could not be transferred back into the docked module")
	assert(is_equal_approx(float(parent.docked_rcs_propellant[child.vehicle_name]), 85.0))
	assert(is_equal_approx(main._module_rcs_propellant_amount(parent, parent), 15.0))
	assert(is_equal_approx(parent.rcs_propellant_remaining, 100.0))
	var expected_docked_mass := child._current_vehicle_mass() + second_child._current_vehicle_mass()
	assert(absf(parent.docked_mass - expected_docked_mass) < 0.01)
	assert(parent.docked_visuals.size() == 2)
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
	for vehicle in main.fleet_sims:
		var save_state: Dictionary = vehicle.get_save_data()
		var saved_stage_fuel: Array = save_state.get("stage_fuel_remaining", [])
		assert(not saved_stage_fuel.is_empty())
		assert(is_equal_approx(float(save_state.get("fuel", -1.0)), float(saved_stage_fuel[0])))
	main.save_slot = 8
	main._save_game(false)
	var save_path := "user://saves/slot_08.json"
	assert(FileAccess.file_exists(save_path))
	main._load_game_from_path(save_path)
	assert(main.docking_links.size() == 3)
	assert(main.fleet_sims.size() == 3)
	var loaded_parent: SimulationView = main.fleet_sims[0]
	var loaded_child: SimulationView = main.fleet_sims[1]
	var loaded_second_child: SimulationView = main.fleet_sims[2]
	assert(not loaded_child.input_enabled)
	assert(not loaded_second_child.input_enabled)
	assert(is_equal_approx(loaded_parent.docked_mass, loaded_child._current_vehicle_mass() + loaded_second_child._current_vehicle_mass()))
	assert(loaded_parent.docked_visuals.size() == 2)
	assert(is_zero_approx(loaded_child.stage_fuel_remaining[1]))
	assert(is_equal_approx(loaded_parent.rcs_propellant_remaining, parent_rcs_capacity))
	assert(is_equal_approx(loaded_parent.stage_fuel_remaining[0], float(loaded_parent._active_stage_data().get("fuel_capacity", 0.0))))
	main.sim = loaded_child
	assert(main._undock_vehicle(loaded_second_child.vehicle_name, child_loop_port_uid), "The saved assembly loop could not be released")
	main.sim = loaded_parent
	assert(main._undock_vehicle(loaded_child.vehicle_name))
	assert(main._undock_vehicle(loaded_second_child.vehicle_name))
	assert(main.docking_links.is_empty())
	assert(is_zero_approx(loaded_parent.docked_mass))
	main.docking_assists[loaded_parent.vehicle_name] = loaded_child.vehicle_name
	main._save_game(false)
	main._load_game_from_path(save_path)
	loaded_parent = main.fleet_sims[0]
	loaded_child = main.fleet_sims[1]
	assert(str(main.docking_assists.get(loaded_parent.vehicle_name, "")) == loaded_child.vehicle_name, "Rendezvous assist state was not restored from save")
	loaded_parent.rotation_angle = 0.0
	loaded_child.rotation_angle = PI
	loaded_parent.rocket_position = Vector2(1000000.0, 2000000.0)
	loaded_child.rocket_position = loaded_parent.rocket_position + Vector2(25.0, 0.0)
	var own_port_state: Dictionary = loaded_parent.docking_port_world_state()
	var child_port_state: Dictionary = loaded_child.docking_port_world_state()
	var child_port_offset: Vector2 = Vector2(child_port_state.position) - loaded_child.rocket_position
	loaded_child.rocket_position = Vector2(own_port_state.position) + Vector2(own_port_state.normal) * 25.0 - child_port_offset
	loaded_parent.velocity = Vector2.ZERO
	loaded_child.velocity = Vector2.ZERO
	var selected_pair := main._available_docking_port_pair(loaded_parent, loaded_child)
	assert(not selected_pair.is_empty(), "Automatic docking could not find an unobstructed port pair")
	main._apply_docking_assists(1.0)
	assert(main._are_docked(loaded_parent.vehicle_name, loaded_child.vehicle_name), "Rendezvous assist did not automatically dock aligned spacecraft")
	assert(main.docking_assists.is_empty(), "Rendezvous assist remained active after automatic docking")
	assert(main._undock_vehicle(loaded_child.vehicle_name), "Docking test could not separate spacecraft for approach-only check")
	var safe_standoff := maxf(1000.0, RocketDesign.vehicle_collision_radius_m({"stages": loaded_parent.rocket_stages}, loaded_parent.stage_index) + RocketDesign.vehicle_collision_radius_m({"stages": loaded_child.rocket_stages}, loaded_child.stage_index) + 500.0)
	loaded_child.rocket_position = loaded_parent.rocket_position + Vector2(safe_standoff + 10.0, 0.0)
	loaded_parent.velocity = Vector2.ZERO
	loaded_child.velocity = Vector2.ZERO
	main.docking_assists[loaded_parent.vehicle_name] = loaded_child.vehicle_name
	main.docking_assist_modes[loaded_parent.vehicle_name] = "approach_only"
	main._apply_docking_assists(1.0)
	assert(main.docking_assists.is_empty(), "Approach-only assist did not hand control back at its safe standoff distance")
	assert(not main._are_docked(loaded_parent.vehicle_name, loaded_child.vehicle_name), "Approach-only assist docked without user input")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Docking and fuel transfer test passed.")
	main.queue_free()
	quit()
