extends RefCounted
class_name StagingSystem

static func create_plan(modules: Array) -> Array:
	var stages: Array = []
	var stage_count := 0
	for module_variant in modules:
		if module_variant is Dictionary:
			stage_count = maxi(stage_count, (module_variant.get("stages", []) as Array).size())
	for stage_index in range(stage_count):
		stages.append({"id": "stage_%d" % stage_index, "label": "Stage %d" % (stage_index + 1), "actions": []})
	for module_variant in modules:
		if not module_variant is Dictionary:
			continue
		var module: Dictionary = module_variant
		var module_id := str(module.get("module_id", module.get("name", "module")))
		for physical_stage_index in range((module.get("stages", []) as Array).size()):
			var physical_stage: Dictionary = module.stages[physical_stage_index]
			for component_variant in physical_stage.get("components", []):
				if not component_variant is Dictionary:
					continue
				var component: Dictionary = component_variant
				var kind := str(component.get("kind", ""))
				var action_name := ""
				if kind in ["engine", "radial"]:
					action_name = "activate_engine"
				elif kind in ["decoupler", "docking_port"]:
					action_name = "separate"
				elif bool(component.get("deployable", false)):
					action_name = "deploy"
				if action_name.is_empty():
					continue
				var assigned_stage := clampi(int(component.get("staging_stage", physical_stage_index)), 0, maxi(0, stages.size() - 1))
				var part_id := str(component.get("part_uid", component.get("id", "")))
				stages[assigned_stage].actions.append({"id":"%s:%s:%s" % [module_id, part_id, action_name], "module_id":module_id, "part_id":part_id, "action":action_name, "completed":false, "reversible":action_name != "separate"})
	return stages

static func merge_plans(first_plan: Array, second_plan: Array) -> Array:
	var merged: Array = []
	var count := maxi(first_plan.size(), second_plan.size())
	for index in range(count):
		var actions: Array = []
		for plan in [first_plan, second_plan]:
			if index >= plan.size() or not plan[index] is Dictionary:
				continue
			for action_variant in plan[index].get("actions", []):
				if action_variant is Dictionary:
					actions.append(action_variant.duplicate(true))
		merged.append({"id":"stage_%d" % index, "label":"Stage %d" % (index + 1), "actions":actions})
	return merged

static func rearm_stage(plan: Array, stage_index: int, part_states: Dictionary = {}) -> Array:
	var result: Array = []
	for index in range(plan.size()):
		if not plan[index] is Dictionary:
			continue
		var stage: Dictionary = plan[index].duplicate(true)
		var actions: Array = stage.get("actions", []).duplicate(true)
		if index == stage_index:
			for action_index in range(actions.size()):
				var action: Dictionary = actions[action_index]
				if not bool(action.get("reversible", false)):
					continue
				var state: Dictionary = part_states.get(str(action.get("part_id", "")), {})
				if bool(state.get("can_repeat", true)):
					action["completed"] = false
					actions[action_index] = action
		stage["actions"] = actions
		result.append(stage)
	return result

static func mark_stage_completed(plan: Array, stage_index: int) -> Array:
	var result: Array = []
	for index in range(plan.size()):
		if not plan[index] is Dictionary:
			continue
		var stage: Dictionary = plan[index].duplicate(true)
		var actions: Array = stage.get("actions", []).duplicate(true)
		if index == stage_index:
			for action_index in range(actions.size()):
				var action: Dictionary = actions[action_index]
				action["completed"] = true
				actions[action_index] = action
		stage["actions"] = actions
		result.append(stage)
	return result
