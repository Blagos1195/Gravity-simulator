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
	var merged := StagingSystem.merge_plans(plan_a, plan_b)
	assert(merged.size() == 1 and merged[0].actions.size() == 2)
	var rearmed := StagingSystem.rearm_stage(merged, 0)
	assert(not bool(rearmed[0].actions[0].completed))
	var completed := StagingSystem.mark_stage_completed(rearmed, 0)
	assert(bool(completed[0].actions[0].completed) and bool(completed[0].actions[1].completed))
	var stage := RocketAssembly.ensure_stage_components({"dry_mass":10.0,"fuel_capacity":0.0,"thrust":100.0,"vacuum_thrust":100.0,"flow":1.0})
	var engine_index := -1
	for index in range(stage.components.size()):
		if str(stage.components[index].kind) == "engine":
			engine_index = index
	assert(engine_index >= 0)
	stage.components[engine_index]["rotation_deg"] = 90.0
	stage = RocketAssembly.compile_stage(stage, stage.components)
	var engines := RocketAssembly.stage_engine_elements(stage, 0.0)
	assert(engines.size() == 1 and Vector2(engines[0].direction).dot(Vector2.RIGHT) > 0.99)
	print("Spacecraft resource, staging and component orientation tests passed.")
	quit()
