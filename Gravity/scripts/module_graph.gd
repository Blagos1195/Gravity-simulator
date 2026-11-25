extends RefCounted
class_name ModuleGraph

static func create(module_ids: Array = []) -> Dictionary:
	var modules: Dictionary = {}
	for module_id in module_ids:
		modules[str(module_id)] = true
	return {"modules": modules, "connections": []}

static func can_connect(graph: Dictionary, module_a: String, module_b: String, port_a: String, port_b: String) -> bool:
	if module_a.is_empty() or module_b.is_empty() or module_a == module_b or port_a.is_empty() or port_b.is_empty():
		return false
	var modules: Dictionary = graph.get("modules", {})
	if not modules.has(module_a) or not modules.has(module_b):
		return false
	for connection in graph.get("connections", []):
		if not connection is Dictionary:
			continue
		if str(connection.get("port_a", "")) in [port_a, port_b] or str(connection.get("port_b", "")) in [port_a, port_b]:
			return false
	return true

static func connect_modules(graph: Dictionary, module_a: String, module_b: String, port_a: String, port_b: String) -> Dictionary:
	if not can_connect(graph, module_a, module_b, port_a, port_b):
		return {"valid": false, "graph": graph.duplicate(true)}
	var result := graph.duplicate(true)
	var connections: Array = result.get("connections", []).duplicate(true)
	connections.append({"id":"%s|%s" % [port_a, port_b],"a":module_a,"b":module_b,"port_a":port_a,"port_b":port_b,"active":true})
	result["connections"] = connections
	return {"valid": true, "graph": result}

static func disconnect_connection(graph: Dictionary, connection_id: String) -> Dictionary:
	var result := graph.duplicate(true)
	var connections: Array = []
	var removed := false
	for connection in result.get("connections", []):
		if connection is Dictionary and str(connection.get("id", "")) == connection_id:
			removed = true
			continue
		connections.append(connection.duplicate(true) if connection is Dictionary else connection)
	result["connections"] = connections
	return {"valid": removed, "graph": result, "groups": connected_components(result)}

static func connected_components(graph: Dictionary) -> Array:
	var modules: Array = (graph.get("modules", {}) as Dictionary).keys()
	return ResourceNetwork.split_connected_modules(modules, graph.get("connections", []))

static func connected_to(graph: Dictionary, module_id: String) -> Array:
	for group in connected_components(graph):
		if module_id in group:
			return group
	return []
