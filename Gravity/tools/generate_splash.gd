extends SceneTree

func _initialize() -> void:
	call_deferred("_generate")

func _generate() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var renderer := Node2D.new()
	renderer.set_script(load("res://tools/splash_art.gd"))
	viewport.add_child(renderer)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	if image.is_empty():
		push_error("Splash renderer produced an empty image.")
		quit(1)
		return
	var output_path := ProjectSettings.globalize_path("res://splash.png")
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save splash.png: %s" % error_string(error))
		quit(1)
		return
	print("Generated splash.png at %s" % output_path)
	quit()
