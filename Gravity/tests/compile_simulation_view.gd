extends SceneTree

func _initialize() -> void:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string("res://scripts/simulation_view.gd")
	var error: Error = script.reload()
	print("SIMULATION VIEW RELOAD RESULT: ", error)
	quit(0 if error == OK else 1)
