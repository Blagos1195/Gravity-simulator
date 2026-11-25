extends SceneTree

const ResourceNetwork = preload("res://scripts/resource_network.gd")
const StagingSystem = preload("res://scripts/staging_system.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

func _initialize() -> void:
	var source := {"fuel_supply_enabled": true, "resources": {"xenon": 80.0}, "resource_capacities": {"xenon": 100.0}}
	var destination := {"resources": {"xenon": 10.0}, "resource_capacities": {"xenon": 60.0}}
	assert(is_equal_approx(ResourceNetwork.transfer_between_tanks(source, destination, "xenon", 100.0), 50.0))
	assert(is_equal_approx(float(source.resources.xenon), 30.0))
	assert(is_equal_approx(float(destination.resources.xenon), 60.0))
	assert(is_zero_approx(ResourceNetwork.transfer_between_tanks(source, destination, "xenon", 10.0, false)))
	assert(is_zero_approx(ResourceNetwork.transfer_between_tanks(source, destination, "solid_propellant", 10.0)))
	var groups := ResourceNetwork.split_connected_modules(["tug", "station", "satellite"], [{"id":"dock_a","a":"tug","b":"station"},{"id":"dock_b","a":"station","b":"satellite"}], "dock_a")
	assert(groups.size() == 2 and groups[0].size() == 1 and groups[1].size() == 2)
	var plan_a: Array = [{"id":"stage_0","actions":[{"id":"a:engine","part_id":"engine","action":"activate_engine","completed":true,"reversible":true}]}]
	var plan_b: Array = [{"id":"stage_0","actions":[{"id":"b:deploy","part_id":"panel","action":"deploy","completed":false,"reversible":true}]}]
	var plan_modules := [{"name":"tug","staging_stage_count":3,"stages":[{"components":[{"id":"engine","kind":"engine","part_uid":"engine","staging_stage":2},{"id":"tank","kind":"tank","part_uid":"tank","staging_stage":1}]}]}]
	var generated_plan := StagingSystem.create_plan(plan_modules)
	assert(generated_plan.size() == 3)
	assert(generated_plan[1].actions[0].action == "enable_fuel_supply")
	assert(generated_plan[2].actions[0].action == "activate_engine")
	var merged := StagingSystem.merge_plans(plan_a, plan_b)
	assert(merged.size() == 1 and merged[0].actions.size() == 2)
	var rearmed := StagingSystem.rearm_stage(merged, 0)
	assert(not bool(rearmed[0].actions[0].completed))
	var completed := StagingSystem.mark_stage_completed(rearmed, 0)
	assert(bool(completed[0].actions[0].completed) and bool(completed[0].actions[1].completed))
	var skipped_completed := StagingSystem.execute_stage(completed, 0, {})
	assert(bool(skipped_completed.plan[0].actions[0].completed))
	var executable_plan: Array = [{"id":"stage_0","actions":[{"id":"engine","part_id":"engine","action":"activate_engine","completed":false,"reversible":true},{"id":"separator","part_id":"separator","action":"separate","completed":false,"reversible":false}]}]
	var executed := StagingSystem.execute_stage(executable_plan, 0, {"separator":{"attached":true}})
	assert(bool(executed.part_states.engine.engine_enabled))
	assert(not bool(executed.part_states.separator.attached))
	var executed_again := StagingSystem.rearm_stage(executed.plan, 0, {"separator":{"can_repeat":false}})
	assert(not bool(executed_again[0].actions[0].completed))
	assert(bool(executed_again[0].actions[1].completed))
	var stage := RocketAssembly.ensure_stage_components({"dry_mass":10.0,"fuel_capacity":0.0,"thrust":100.0,"vacuum_thrust":100.0,"flow":1.0})
	assert(float(stage.resource_capacities.get("liquid_propellant", 0.0)) == 0.0)
	var resource_stage := RocketAssembly.add_component(stage, "medium_tank")
	assert(float(resource_stage.resource_capacities.get("liquid_propellant", 0.0)) > 0.0)
	assert(not resource_stage.tank_states.is_empty())
	var engine_index := -1
	for index in range(stage.components.size()):
		if str(stage.components[index].kind) == "engine":
			engine_index = index
	assert(engine_index >= 0)
	stage.components[engine_index]["rotation_deg"] = 90.0
	stage = RocketAssembly.compile_stage(stage, stage.components)
	var engines := RocketAssembly.stage_engine_elements(stage, 0.0)
	assert(engines.size() == 1 and Vector2(engines[0].direction).dot(Vector2.RIGHT) > 0.99)
	stage.components[engine_index]["engine_enabled"] = false
	stage = RocketAssembly.compile_stage(stage, stage.components)
	assert(RocketAssembly.stage_engine_elements(stage, 0.0).is_empty())
	assert(is_zero_approx(float(stage.thrust)))
	var rcs_stage := RocketAssembly.add_component(stage, "rcs_thruster_block")
	var rcs_components: Array = rcs_stage.components.duplicate(true)
	for index in range(rcs_components.size()):
		if str(rcs_components[index].get("kind", "")) == "rcs":
			rcs_components[index]["rcs_enabled"] = false
	rcs_stage = RocketAssembly.compile_stage(rcs_stage, rcs_components)
	assert(is_zero_approx(float(rcs_stage.rcs_thrust)))
	assert(RocketAssembly.stage_rcs_elements(rcs_stage).is_empty())
	print("Spacecraft resource, staging and component orientation tests passed.")
	quit()
