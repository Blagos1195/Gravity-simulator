extends RefCounted
class_name StagingSystem

const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

static func create_plan(modules: Array) -> Array:
	var stages: Array = []
	var stage_count := 0
	for module_variant in modules:
		if module_variant is Dictionary:
			stage_count = maxi(stage_count, (module_variant.get("stages", []) as Array).size())
			stage_count = maxi(stage_count, int(module_variant.get("staging_stage_count", 0)))
			for physical_stage in module_variant.get("stages", []):
				for component_variant in physical_stage.get("components", []):
					if component_variant is Dictionary:
						stage_count = maxi(stage_count, int(component_variant.get("staging_stage", 0)) + 1)
	for stage_index in range(stage_count):
		stages.append({"id": "stage_%d" % stage_index, "label": "Stage %d" % (stage_index + 1), "actions": []})
	for module_variant in modules:
		if not module_variant is Dictionary:
			continue
		var module: Dictionary = module_variant
		var module_id := str(module.get("module_id", module.get("name", "module")))
		var docking_boundaries := RocketAssembly.docking_module_boundaries(module.get("stages", []))
		for physical_stage_index in range((module.get("stages", []) as Array).size()):
			var physical_stage: Dictionary = module.stages[physical_stage_index]
			var component_group_boundaries := RocketAssembly.docking_component_group_boundaries(physical_stage)
			for component_variant in physical_stage.get("components", []):
				if not component_variant is Dictionary:
					continue
				var component: Dictionary = component_variant
				var kind := str(component.get("kind", ""))
				var part_id := str(component.get("part_uid", component.get("id", "")))
				var action_name := str(component.get("staging_action", ""))
				if kind == "docking_port":
					if component_group_boundaries.has(part_id):
						action_name = "undock_component_group"
					else:
						action_name = "undock_module" if docking_boundaries.has(physical_stage_index) and str(docking_boundaries[physical_stage_index].get("upper_part_uid", "")) == part_id else ""
				elif action_name.is_empty():
					if kind in ["engine", "radial"]:
						if bool(component.get("solid_motor", false)):
							action_name = "ignite_solid_motor"
						else:
							action_name = "activate_engine"
					elif kind == "decoupler":
						action_name = "separate"
					elif kind == "tank":
						action_name = "enable_fuel_supply"
					elif kind == "rcs":
						action_name = "activate_rcs"
					elif bool(component.get("deployable", false)):
						action_name = "deploy"
				if action_name.is_empty():
					continue
				var assigned_stage := clampi(int(component.get("staging_stage", physical_stage_index)), 0, maxi(0, stages.size() - 1))
				stages[assigned_stage].actions.append({"id":"%s:%s:%s" % [module_id, part_id, action_name], "module_id":module_id, "physical_stage_index":physical_stage_index, "part_id":part_id, "action":action_name, "completed":false, "reversible":action_name not in ["separate", "undock_module"]})
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

static func filter_module_plan(plan: Array, module_id: String) -> Array:
	var result: Array = []
	for stage_variant in plan:
		if not stage_variant is Dictionary:
			continue
		var stage: Dictionary = stage_variant.duplicate(true)
		var actions: Array = []
		for action in stage.get("actions", []):
			if action is Dictionary and str(action.get("module_id", "")) == module_id:
				actions.append(action.duplicate(true))
		stage["actions"] = actions
		result.append(stage)
	return result

static func remove_module_plan(plan: Array, module_id: String) -> Array:
	var result: Array = []
	for stage_variant in plan:
		if not stage_variant is Dictionary:
			continue
		var stage: Dictionary = stage_variant.duplicate(true)
		var actions: Array = []
		for action in stage.get("actions", []):
			if action is Dictionary and str(action.get("module_id", "")) != module_id:
				actions.append(action.duplicate(true))
		stage["actions"] = actions
		result.append(stage)
	return result

static func filter_module_plan_members(plan: Array, module_ids: Dictionary) -> Array:
	var result: Array = []
	for stage_variant in plan:
		if not stage_variant is Dictionary:
			continue
		var stage: Dictionary = stage_variant.duplicate(true)
		var actions: Array = []
		for action in stage.get("actions", []):
			if action is Dictionary and module_ids.has(str(action.get("module_id", ""))):
				actions.append(action.duplicate(true))
		stage["actions"] = actions
		result.append(stage)
	return result

static func remove_module_plan_members(plan: Array, module_ids: Dictionary) -> Array:
	var result: Array = []
	for stage_variant in plan:
		if not stage_variant is Dictionary:
			continue
		var stage: Dictionary = stage_variant.duplicate(true)
		var actions: Array = []
		for action in stage.get("actions", []):
			if action is Dictionary and not module_ids.has(str(action.get("module_id", ""))):
				actions.append(action.duplicate(true))
		stage["actions"] = actions
		result.append(stage)
	return result

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

static func execute_stage(plan: Array, stage_index: int, part_states: Dictionary) -> Dictionary:
	if stage_index < 0 or stage_index >= plan.size() or not plan[stage_index] is Dictionary:
		return {"valid":false,"plan":plan.duplicate(true),"part_states":part_states.duplicate(true)}
	var updated_plan := plan.duplicate(true)
	var updated_states := part_states.duplicate(true)
	var stage: Dictionary = updated_plan[stage_index]
	var actions: Array = stage.get("actions", []).duplicate(true)
	for action_index in range(actions.size()):
		var action: Dictionary = actions[action_index]
		if bool(action.get("completed", false)):
			continue
		var part_id := str(action.get("part_id", ""))
		var state: Dictionary = updated_states.get(part_id, {}).duplicate(true)
		var action_name := str(action.get("action", ""))
		match action_name:
			"activate_engine":
				state["engine_enabled"] = true
			"ignite_solid_motor":
				state["engine_enabled"] = true
				state["ignited"] = true
			"deactivate_engine":
				state["engine_enabled"] = false
			"enable_fuel_supply":
				state["fuel_supply_enabled"] = true
			"disable_fuel_supply":
				state["fuel_supply_enabled"] = false
			"activate_rcs":
				state["rcs_enabled"] = true
			"deactivate_rcs":
				state["rcs_enabled"] = false
			"deploy":
				state["deployed"] = true
			"retract":
				state["deployed"] = false
			"separate":
				if not bool(state.get("attached", true)):
					continue
				state["attached"] = false
			"undock_module":
				state["module_release_requested"] = true
			"attach":
				if not bool(state.get("can_attach", false)):
					continue
				state["attached"] = true
			_:
				state["active"] = action_name == "activate"
		updated_states[part_id] = state
		action["completed"] = true
		actions[action_index] = action
	stage["actions"] = actions
	updated_plan[stage_index] = stage
	return {"valid":true,"plan":updated_plan,"part_states":updated_states}

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
