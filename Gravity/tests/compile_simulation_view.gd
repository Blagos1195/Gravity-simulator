extends SceneTree

func _initialize() -> void:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://scripts/simulation_view.gd")
	var error: Error = script.reload()
	print("SIMULATION VIEW RELOAD RESULT: ", error)
	var route_script := GDScript.new()
	route_script.source_code = "\\n".join(PackedStringArray([
		"extends SceneTree",
		"const RoutePlanner = preload(\"res://scripts/route_planner.gd\")",
		"func _initialize():",
		"\tquit()"
	]))
	var route_error: Error = route_script.reload()
	print("ROUTE PLANNER RELOAD RESULT: ", route_error)
	quit(0 if error == OK and route_error == OK else 1)
