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
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image.is_empty():
		push_error("Splash renderer produced an empty image.")
		quit(1)
		return
	var splash_path := ProjectSettings.globalize_path("res://splash.png")
	var splash_error := image.save_png(splash_path)
	if splash_error != OK:
		push_error("Could not save splash.png: %s" % error_string(splash_error))
		quit(1)
		return
	var icon_error := _generate_windows_icon()
	if icon_error != OK:
		push_error("Could not generate icon.ico: %s" % error_string(icon_error))
		quit(1)
		return
	print("Generated splash.png and icon.ico")
	quit()

func _generate_windows_icon() -> Error:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	if svg.is_empty():
		return ERR_FILE_NOT_FOUND
	var icon_image: Image = Image.new()
	var svg_error: Error = icon_image.load_svg_from_string(svg, 1.0)
	if svg_error != OK or icon_image.is_empty():
		return ERR_FILE_CANT_READ if svg_error == OK else svg_error
	icon_image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var png: PackedByteArray = icon_image.save_png_to_buffer()
	if png.is_empty():
		return ERR_CANT_CREATE
	var ico := PackedByteArray()
	ico.resize(22)
	ico.encode_u16(0, 0)
	ico.encode_u16(2, 1)
	ico.encode_u16(4, 1)
	ico.encode_u8(6, 0)
	ico.encode_u8(7, 0)
	ico.encode_u8(8, 0)
	ico.encode_u8(9, 0)
	ico.encode_u16(10, 1)
	ico.encode_u16(12, 32)
	ico.encode_u32(14, png.size())
	ico.encode_u32(18, 22)
	ico.append_array(png)
	var output_path := ProjectSettings.globalize_path("res://icon.ico")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(ico)
	file.close()
	return OK
