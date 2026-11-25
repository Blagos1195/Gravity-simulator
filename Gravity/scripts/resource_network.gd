extends RefCounted
class_name ResourceNetwork

const NON_TRANSFERABLE_RESOURCES := ["solid_propellant"]

static func component_capacities(component: Dictionary) -> Dictionary:
	var capacities: Dictionary = {}
	var declared: Variant = component.get("resource_capacities", {})
	if declared is Dictionary:
		for resource in declared:
			var amount := maxf(0.0, float(declared[resource]))
			if amount > 0.0:
				capacities[str(resource)] = amount
	var fuel_type := str(component.get("fuel_type", "liquid_propellant" if str(component.get("kind", "")) == "tank" else ""))
	var fuel_capacity := maxf(0.0, float(component.get("fuel_capacity", 0.0)))
	if not fuel_type.is_empty() and fuel_capacity > 0.0:
		capacities[fuel_type] = maxf(float(capacities.get(fuel_type, 0.0)), fuel_capacity)
	var solid_capacity := maxf(0.0, float(component.get("solid_propellant_capacity", 0.0)))
	if solid_capacity > 0.0:
		capacities["solid_propellant"] = solid_capacity
	var rcs_capacity := maxf(0.0, float(component.get("rcs_propellant_capacity", 0.0)))
	if rcs_capacity > 0.0:
		capacities["rcs_propellant"] = rcs_capacity
	var electric_capacity := maxf(0.0, float(component.get("electric_capacity", 0.0)))
	if electric_capacity > 0.0:
		capacities["electricity"] = electric_capacity
	return capacities

static func manifest(components: Array) -> Dictionary:
	var result: Dictionary = {}
	for component_variant in components:
		if not component_variant is Dictionary:
			continue
		var component: Dictionary = component_variant
		var capacities := component_capacities(component)
		for resource in capacities:
			result[resource] = float(result.get(resource, 0.0)) + float(capacities[resource])
	return result

static func create_tank_states(components: Array) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for index in range(components.size()):
		if not components[index] is Dictionary:
			continue
		var component: Dictionary = components[index]
		var capacities := component_capacities(component)
		if capacities.is_empty():
			continue
		var part_id := str(component.get("part_uid", component.get("id", "part_%d" % index)))
		states.append({
			"part_uid": part_id,
			"resources": capacities.duplicate(true),
			"resource_capacities": capacities.duplicate(true),
			"fuel_supply_enabled": bool(component.get("fuel_supply_enabled", true)),
			"transfer_enabled": bool(component.get("transfer_enabled", true))
		})
	return states

static func transfer_between_tanks(source: Dictionary, destination: Dictionary, resource: String, requested_amount: float, connected: bool = true) -> float:
	if not connected or resource in NON_TRANSFERABLE_RESOURCES or requested_amount <= 0.0:
		return 0.0
	if not bool(source.get("fuel_supply_enabled", true)) or not bool(source.get("transfer_enabled", true)):
		return 0.0
	var source_resources: Dictionary = source.get("resources", {})
	var destination_resources: Dictionary = destination.get("resources", {})
	var destination_capacities: Dictionary = destination.get("resource_capacities", component_capacities(destination))
	var available := maxf(0.0, float(source_resources.get(resource, 0.0)))
	var capacity := maxf(0.0, float(destination_capacities.get(resource, 0.0)))
	var current := maxf(0.0, float(destination_resources.get(resource, 0.0)))
	var amount := minf(requested_amount, minf(available, maxf(0.0, capacity - current)))
	if amount <= 0.0:
		return 0.0
	source_resources[resource] = available - amount
	destination_resources[resource] = current + amount
	source["resources"] = source_resources
	destination["resources"] = destination_resources
	return amount

static func split_connected_modules(module_ids: Array, connections: Array, disabled_connection_id: String = "") -> Array:
	var adjacency: Dictionary = {}
	for module_variant in module_ids:
		adjacency[str(module_variant)] = []
	for connection_variant in connections:
		if not connection_variant is Dictionary or not bool(connection_variant.get("active", true)):
			continue
		var connection: Dictionary = connection_variant
		if str(connection.get("id", "")) == disabled_connection_id:
			continue
		var first := str(connection.get("a", ""))
		var second := str(connection.get("b", ""))
		if not adjacency.has(first) or not adjacency.has(second):
			continue
		(adjacency[first] as Array).append(second)
		(adjacency[second] as Array).append(first)
	var groups: Array = []
	var visited: Dictionary = {}
	for module_variant in module_ids:
		var start := str(module_variant)
		if visited.has(start):
			continue
		var group: Array = []
		var queue: Array = [start]
		visited[start] = true
		while not queue.is_empty():
			var current := str(queue.pop_front())
			group.append(current)
			for neighbour_variant in adjacency.get(current, []):
				var neighbour := str(neighbour_variant)
				if not visited.has(neighbour):
					visited[neighbour] = true
					queue.append(neighbour)
		groups.append(group)
	return groups
