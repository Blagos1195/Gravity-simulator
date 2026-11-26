extends RefCounted
class_name ModuleGraph

static func create(module_ids: Array = []) -> Dictionary:
	var modules: Dictionary = {}
	for module_id in module_ids:
		modules[str(module_id)] = true
	return {"modules": modules, "connections": []}

static func can_connect(graph: Dictionary, module_a: String, module_b: String, port_a: String, port_b: String) -> bool:
	if module_a.is_empty() or module_b.is_empty() or module_a == module_b or port_a.is_empty() or port_b.is_empty() or port_a == port_b:
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

static func connection_for_port(graph: Dictionary, port_id: String) -> Dictionary:
	for connection in graph.get("connections", []):
		if connection is Dictionary and port_id in [str(connection.get("port_a", "")), str(connection.get("port_b", ""))]:
			return connection.duplicate(true)
	return {}

static func connection_between(graph: Dictionary, module_a: String, module_b: String) -> Array:
	var result: Array = []
	for connection in graph.get("connections", []):
		if not connection is Dictionary:
			continue
		var a := str(connection.get("a", ""))
		var b := str(connection.get("b", ""))
		if (a == module_a and b == module_b) or (a == module_b and b == module_a):
			result.append(connection.duplicate(true))
	return result

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

static func remove_module(graph: Dictionary, module_id: String) -> Dictionary:
	var result := graph.duplicate(true)
	var modules: Dictionary = result.get("modules", {}).duplicate(true)
	if not modules.has(module_id):
		return {"valid": false, "graph": result, "removed_connections": []}
	modules.erase(module_id)
	result["modules"] = modules
	var connections: Array = []
	var removed_connections: Array = []
	for connection in result.get("connections", []):
		if connection is Dictionary and module_id in [str(connection.get("a", "")), str(connection.get("b", ""))]:
			removed_connections.append(connection.duplicate(true))
		else:
			connections.append(connection.duplicate(true) if connection is Dictionary else connection)
	result["connections"] = connections
	return {"valid": true, "graph": result, "removed_connections": removed_connections, "groups": connected_components(result)}

static func validate(graph: Dictionary) -> Array:
	var errors: Array = []
	var modules: Dictionary = graph.get("modules", {})
	var used_ports: Dictionary = {}
	var connection_ids: Dictionary = {}
	for connection in graph.get("connections", []):
		if not connection is Dictionary:
			errors.append("Connection entry is not a dictionary")
			continue
		var module_a := str(connection.get("a", ""))
		var module_b := str(connection.get("b", ""))
		var port_a := str(connection.get("port_a", ""))
		var port_b := str(connection.get("port_b", ""))
		var connection_id := str(connection.get("id", ""))
		if module_a == module_b or not modules.has(module_a) or not modules.has(module_b):
			errors.append("Connection references invalid modules")
		if port_a.is_empty() or port_b.is_empty() or port_a == port_b:
			errors.append("Connection has invalid docking ports")
		for port_id in [port_a, port_b]:
			if used_ports.has(port_id):
				errors.append("Docking port is used by more than one connection: " + port_id)
			used_ports[port_id] = true
		if connection_id.is_empty() or connection_ids.has(connection_id):
			errors.append("Connection has an empty or duplicate ID")
		connection_ids[connection_id] = true
	return errors

static func connected_components(graph: Dictionary) -> Array:
	var modules: Array = (graph.get("modules", {}) as Dictionary).keys()
	return ResourceNetwork.split_connected_modules(modules, graph.get("connections", []))

static func connected_to(graph: Dictionary, module_id: String) -> Array:
	for group in connected_components(graph):
		if module_id in group:
			return group
	return []
