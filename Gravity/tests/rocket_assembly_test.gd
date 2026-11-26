extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const RocketBuilder = preload("res://scripts/rocket_builder.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")
const StagingSystem = preload("res://scripts/staging_system.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	var original: Dictionary = design["stages"][0]
	var original_dry_mass := RocketDesign.stage_total_dry_mass(original)
	var original_fuel := RocketDesign.stage_total_fuel_capacity(original)
	var original_thrust := RocketDesign.stage_total_thrust(original)
	var original_vacuum_thrust := RocketDesign.stage_total_thrust(original, true)
	var original_flow := RocketDesign.stage_total_flow(original)
	var assembled := RocketAssembly.ensure_stage_components(original)
	assert(bool(assembled.get("component_assembly", false)))
	assert(assembled.get("components", []).size() == 2)
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(assembled), original_dry_mass))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(assembled), original_fuel))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(assembled), original_thrust))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(assembled, true), original_vacuum_thrust))
	assert(is_equal_approx(RocketDesign.stage_total_flow(assembled), original_flow))
	var with_tank := RocketAssembly.add_component(assembled, "medium_tank")
	assert(not with_tank.is_empty())
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(with_tank), original_dry_mass + 6000.0))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(with_tank), original_fuel + 80000.0))
	var side_tank := RocketAssembly.add_component(assembled, "medium_tank", "side", true, 1, 0)
	assert(not side_tank.is_empty())
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(side_tank), original_dry_mass + 12000.0))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(side_tank), original_fuel + 160000.0))
	assert(is_equal_approx(float(side_tank.physical_length_m), float(assembled.physical_length_m)))
	assert(float(side_tank.collision_radius_m) > float(assembled.collision_radius_m))
	var second_side_tank := RocketAssembly.add_component(side_tank, "medium_tank", "side", true, -1, 0)
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(second_side_tank), original_dry_mass + 24000.0))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(second_side_tank), original_fuel + 320000.0))
	assert(float(second_side_tank.collision_radius_m) > float(side_tank.collision_radius_m))
	var side_engine := RocketAssembly.add_component(assembled, "heavy_engine", "side", true, -1, 0)
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(side_engine), original_dry_mass + 13000.0))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(side_engine), original_thrust + 5600000.0))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(side_engine, true), original_vacuum_thrust + 6200000.0))
	assert(is_equal_approx(RocketDesign.stage_total_flow(side_engine), original_flow + 1800.0))
	var one_sided_engine := RocketAssembly.add_component(assembled, "heavy_engine", "side", false, 1, 0)
	var one_sided_engine_elements := RocketAssembly.stage_engine_elements(one_sided_engine, 1.0)
	var one_sided_torque := 0.0
	for engine in one_sided_engine_elements:
		one_sided_torque += Vector2(engine.position).cross(Vector2.UP * float(engine.thrust))
	assert(absf(one_sided_torque) > 1.0, "A one-sided engine should produce torque")
	var mirrored_engine := RocketAssembly.add_component(assembled, "heavy_engine", "side", true, 1, 0)
	var mirrored_engine_elements := RocketAssembly.stage_engine_elements(mirrored_engine, 1.0)
	var mirrored_torque := 0.0
	for engine in mirrored_engine_elements:
		mirrored_torque += Vector2(engine.position).cross(Vector2.UP * float(engine.thrust))
	assert(absf(mirrored_torque) < 0.001, "Mirrored engines should cancel their axial thrust torque")
	var one_sided_tank := RocketAssembly.add_component(assembled, "medium_tank", "side", false, 1, 0)
	var full_mass_elements := RocketAssembly.stage_mass_elements(one_sided_tank, RocketDesign.stage_total_fuel_capacity(one_sided_tank))
	var empty_mass_elements := RocketAssembly.stage_mass_elements(one_sided_tank, 0.0)
	var full_mass := 0.0
	var full_weighted_x := 0.0
	var empty_mass := 0.0
	var empty_weighted_x := 0.0
	for element in full_mass_elements:
		var element_mass := float(element.mass)
		full_mass += element_mass
		full_weighted_x += element_mass * Vector2(element.position).x
	for element in empty_mass_elements:
		var element_mass := float(element.mass)
		empty_mass += element_mass
		empty_weighted_x += element_mass * Vector2(element.position).x
	var full_com_x := full_weighted_x / full_mass
	var empty_com_x := empty_weighted_x / empty_mass
	assert(full_com_x > empty_com_x and empty_com_x > 0.0, "Fuel mass should shift the centre of mass towards a one-sided tank")
	var simulation := SimulationView.new()
	var asymmetric_design := RocketDesign.create_default()
	asymmetric_design["stages"][0] = one_sided_engine
	simulation.set_rocket_design(asymmetric_design)
	var asymmetric_mass := simulation._vehicle_mass_properties()
	var asymmetric_profile := simulation._engine_force_profile(asymmetric_mass.center_of_mass, 1.0, 1.0)
	assert(absf(float(asymmetric_profile.torque)) > 1.0, "The flight model should calculate torque from an asymmetric engine layout")
	var balanced_design := RocketDesign.create_default()
	balanced_design["stages"][0] = mirrored_engine
	simulation.set_rocket_design(balanced_design)
	var balanced_mass := simulation._vehicle_mass_properties()
	var balanced_profile := simulation._engine_force_profile(balanced_mass.center_of_mass, 1.0, 1.0)
	assert(absf(float(balanced_profile.torque)) < 0.001, "The flight model should preserve torque balance for mirrored engines")
	var rcs_stage := RocketAssembly.add_component(assembled, "rcs_thruster_block")
	assert(is_equal_approx(RocketDesign.stage_rcs_propellant_capacity(rcs_stage), 250.0))
	assert(is_equal_approx(float(rcs_stage.rcs_thrust), 1800.0))
	var port_stage := RocketAssembly.add_component(rcs_stage, "standard_docking_port")
	assert(RocketAssembly.stage_docking_ports(port_stage).size() == 1)
	var rcs_design := RocketDesign.create_default()
	rcs_design["stages"][0] = port_stage
	simulation.set_rocket_design(rcs_design)
	assert(simulation.has_rcs() and simulation.has_docking_port())
	var module_design := RocketDesign.create_default()
	module_design["stages"] = [port_stage.duplicate(true), port_stage.duplicate(true)]
	simulation.set_rocket_design(module_design)
	assert(simulation.stage_separation_is_dockable_module(), "Matching ports on adjacent stages should create a detachable module")
	var upper_stage_without_port := RocketAssembly.remove_component(module_design.stages[1], module_design.stages[1].components.size() - 1)
	module_design["stages"][1] = upper_stage_without_port
	simulation.set_rocket_design(module_design)
	assert(not simulation.stage_separation_is_dockable_module(), "A module should not detach as dockable without ports on both sides")
	var upper_stage_without_rcs := RocketAssembly.remove_component(port_stage.duplicate(true), 2)
	module_design["stages"][1] = upper_stage_without_rcs
	simulation.set_rocket_design(module_design)
	assert(not simulation.stage_separation_is_dockable_module(), "A detached module without RCS should not be dockable")
	rcs_design["stages"][0] = port_stage
	simulation.set_rocket_design(rcs_design)
	var port_state := simulation.docking_port_world_state()
	assert(not port_state.is_empty())
	assert(Vector2(port_state.normal).dot(Vector2.UP) > 0.99)
	var rcs_fuel_before := simulation.rcs_propellant_remaining
	assert(simulation.apply_rcs_velocity_correction(Vector2(0.1, 0.0), 1.0))
	assert(simulation.velocity.x > 0.0 and simulation.rcs_propellant_remaining < rcs_fuel_before)
	var saved_rcs_state := simulation.get_save_data()
	assert(is_equal_approx(float(saved_rcs_state.get("rcs_propellant_remaining", -1.0)), simulation.rcs_propellant_remaining))
	assert(simulation.load_save_data(saved_rcs_state), "RCS propellant should survive a save/load cycle")
	var aft_port_stage := port_stage.duplicate(true)
	for component in aft_port_stage.components:
		if str(component.get("kind", "")) == "docking_port":
			component["port_facing"] = -1
	var aft_ports := RocketAssembly.stage_docking_ports(aft_port_stage)
	assert(Vector2(aft_ports[0].normal).dot(Vector2.DOWN) > 0.99)
	var lower_module_stage := port_stage.duplicate(true)
	var lower_port_index := -1
	for component_index in range(lower_module_stage.components.size()):
		if str(lower_module_stage.components[component_index].get("kind", "")) == "docking_port":
			lower_port_index = component_index
			break
	assert(lower_port_index >= 0)
	var lower_port_component: Dictionary = lower_module_stage.components.pop_at(lower_port_index)
	lower_module_stage.components.insert(0, lower_port_component)
	lower_module_stage = RocketAssembly.compile_stage(lower_module_stage, lower_module_stage.components)
	var upper_module_stage := aft_port_stage.duplicate(true)
	var paired_stages: Array = [lower_module_stage, upper_module_stage]
	var module_boundaries := RocketAssembly.docking_module_boundaries(paired_stages)
	assert(module_boundaries.has(1), "Opposing docking ports at adjacent stage ends should define a releasable module")
	var paired_plan := StagingSystem.create_plan([{"module_id":"test_vehicle", "stages":paired_stages}])
	var has_module_release_action := false
	for plan_stage in paired_plan:
		for action in plan_stage.get("actions", []):
			if str(action.get("action", "")) == "undock_module" and int(action.get("physical_stage_index", -1)) == 1:
				has_module_release_action = true
	assert(has_module_release_action, "The upper connector should create a module-release staging action")
	var grouped_stage := RocketAssembly.add_component(port_stage.duplicate(true), "standard_docking_port")
	var grouped_components: Array = grouped_stage.components.duplicate(true)
	for component_index in range(grouped_components.size()):
		var grouped_component: Dictionary = grouped_components[component_index]
		if str(grouped_component.get("kind", "")) == "docking_port":
			grouped_component["subassembly_id"] = "payload_group" if component_index == grouped_components.size() - 1 else "main"
		grouped_components[component_index] = grouped_component
	grouped_stage = RocketAssembly.compile_stage(grouped_stage, grouped_components)
	assert(RocketAssembly.split_stage_by_group(grouped_stage, "payload_group").size() == 2, "A physical stage should split into retained and released component groups")
	var inline_stage := RocketAssembly.ensure_stage_components({})
	var inline_parts: Array = []
	var upper_port := RocketAssembly.component_definition("standard_docking_port")
	upper_port["part_uid"] = "inline_upper_port"
	upper_port["attachment"] = "stack"
	upper_port["length_m"] = 1.0
	upper_port["subassembly_id"] = "payload_group"
	upper_port["port_facing"] = 1
	var lower_port := RocketAssembly.component_definition("standard_docking_port")
	lower_port["part_uid"] = "inline_lower_port"
	lower_port["attachment"] = "stack"
	lower_port["length_m"] = 1.0
	lower_port["subassembly_id"] = "main"
	lower_port["port_facing"] = -1
	inline_parts.append(upper_port)
	inline_parts.append(lower_port)
	var upper_rcs := RocketAssembly.component_definition("rcs_thruster_block")
	upper_rcs["part_uid"] = "inline_upper_rcs"
	upper_rcs["attachment"] = "side"
	upper_rcs["mirror"] = false
	upper_rcs["side"] = 1
	upper_rcs["subassembly_id"] = "payload_group"
	var lower_rcs := RocketAssembly.component_definition("rcs_thruster_block")
	lower_rcs["part_uid"] = "inline_lower_rcs"
	lower_rcs["attachment"] = "side"
	lower_rcs["mirror"] = false
	lower_rcs["side"] = -1
	lower_rcs["subassembly_id"] = "main"
	inline_parts.append(upper_rcs)
	inline_parts.append(lower_rcs)
	inline_stage = RocketAssembly.compile_stage(inline_stage, inline_parts)
	var inline_boundaries := RocketAssembly.docking_component_group_boundaries(inline_stage)
	assert(inline_boundaries.has("inline_upper_port"), "Opposing docking ports between component groups should create an in-stage release boundary")
	var inline_plan := StagingSystem.create_plan([{"module_id":"inline_vehicle","stages":[inline_stage]}])
	var has_inline_release := false
	for plan_stage in inline_plan:
		for action in plan_stage.get("actions", []):
			if str(action.get("action", "")) == "undock_component_group":
				has_inline_release = true
	assert(has_inline_release, "An in-stage docking boundary should create a staging action")
	var inline_simulation := SimulationView.new()
	var inline_design := RocketDesign.create_default()
	inline_design["payload_mass"] = 100.0
	inline_design["preserve_part_uids"] = true
	inline_design["stages"] = [inline_stage]
	inline_simulation.set_rocket_design(inline_design)
	var inline_released: Array[Dictionary] = []
	inline_simulation.stage_separated.connect(func(stage_data: Dictionary): inline_released.append(stage_data))
	assert(inline_simulation._release_component_group("inline_upper_port"), "An individual component group should release from its physical stage")
	assert(inline_simulation.rocket_stages[0].components.size() == 1, "The parent should retain only its own component group")
	assert(inline_released.size() == 1 and inline_released[0].stages[0].components.size() == 1, "The released spacecraft should contain only the selected component group")
	inline_simulation.free()
	var unpaired_port_stage := RocketAssembly.add_component(RocketAssembly.ensure_stage_components({}), "standard_docking_port")
	for component in unpaired_port_stage.components:
		if str(component.get("kind", "")) == "docking_port":
			component["staging_action"] = "separate"
	var unpaired_port_plan := StagingSystem.create_plan([{"module_id":"unpaired_vehicle","stages":[unpaired_port_stage]}])
	for plan_stage in unpaired_port_plan:
		for action in plan_stage.get("actions", []):
			assert(str(action.get("action", "")) != "separate" and str(action.get("action", "")) != "undock_module", "An unpaired docking port must not become a detachable part or module")
	var release_simulation := SimulationView.new()
	var release_design := RocketDesign.create_default()
	release_design["stages"] = paired_stages
	release_simulation.set_rocket_design(release_design)
	var released_modules: Array[Dictionary] = []
	release_simulation.stage_separated.connect(func(stage_data: Dictionary): released_modules.append(stage_data))
	assert(release_simulation._release_upper_module(1), "A paired docking connector should release the upper module")
	assert(release_simulation.rocket_stages.size() == 1, "The launch vehicle should retain its lower stage after module release")
	assert(released_modules.size() == 1, "The docking release should create exactly one independent module")
	var released_module: Dictionary = released_modules[0]
	assert((released_module.get("stages", []) as Array).size() == 1, "The released module should retain its complete upper stack")
	assert(is_equal_approx(float(released_module.get("payload_mass", 0.0)), float(release_design.get("payload_mass", 0.0))))
	release_simulation.free()
	var no_rcs_simulation := SimulationView.new()
	no_rcs_simulation.set_rocket_design(RocketDesign.create_default())
	assert(not no_rcs_simulation.has_rcs() and not no_rcs_simulation.apply_rcs_velocity_correction(Vector2.RIGHT, 1.0))
	no_rcs_simulation.free()
	simulation.docked_mass = 5000.0
	simulation.docked_visuals = [{
		"mass": 5000.0,
		"offset": Vector2(20.0, 0.0),
		"center_of_mass": Vector2.ZERO,
		"moment_of_inertia": 100000.0
	}]
	var docked_mass_properties := simulation._vehicle_mass_properties()
	assert(Vector2(docked_mass_properties.center_of_mass).x > 0.0, "An offset docked spacecraft should shift the vehicle centre of mass")
	simulation.free()
	var with_engine := RocketAssembly.add_component(with_tank, "vacuum_engine")
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(with_engine), original_dry_mass + 6900.0))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(with_engine, true), original_vacuum_thrust + 310000.0))
	assert(is_equal_approx(RocketDesign.stage_total_flow(with_engine), original_flow + 85.0))
	var without_engine := RocketAssembly.remove_component(with_engine, with_engine.components.size() - 1)
	assert(is_equal_approx(RocketDesign.stage_total_thrust(without_engine, true), original_vacuum_thrust))
	var reordered := RocketAssembly.move_component(with_engine, 2, -1)
	assert(str(reordered.components[1].get("id", "")) == "medium_tank", "Component stack order was not updated")
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(reordered), RocketDesign.stage_total_dry_mass(with_engine)))
	assert(RocketAssembly.move_component(with_engine, 0, -1).is_empty())
	assert(RocketAssembly.move_component(with_engine, with_engine.components.size() - 1, 1).is_empty())
	assert(RocketAssembly.component_options().size() >= 16)
	var mirrored_booster_stage := RocketAssembly.add_component(assembled, "solid_booster_pair", "radial", true, -1)
	assert(not mirrored_booster_stage.is_empty())
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(mirrored_booster_stage).dry_mass), 16000.0))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(mirrored_booster_stage).fuel_capacity), 84000.0))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(mirrored_booster_stage).vacuum_thrust), 1200000.0))
	var single_booster_stage := RocketAssembly.add_component(assembled, "solid_booster_pair", "radial", false, 1)
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(single_booster_stage).dry_mass), 8000.0))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(single_booster_stage).fuel_capacity), 42000.0))
	assert(RocketAssembly.remove_component(assembled, 99).is_empty())
	design["stages"][0] = with_engine
	assert(RocketDesign.validation_errors(design).is_empty(), "A valid component-built stage failed rocket validation")
	var builder := RocketBuilder.new()
	builder.configure(design, 0)
	root.add_child(builder)
	await process_frame
	assert(is_instance_valid(builder), "The component assembly editor did not enter the scene tree")
	builder.call("_refresh_stats")
	var stats_text := builder.performance_summary_text()
	assert(stats_text.contains("STAGE TWR") and stats_text.contains("IDEAL ΔV"), "The component editor does not show live TWR and vehicle delta-v")
	builder.queue_free()
	print("Rocket component assembly tests passed.")
	quit()
