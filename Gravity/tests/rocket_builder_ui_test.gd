extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var main := Main.new()
	main.size = Vector2(1280.0, 720.0)
	root.add_child(main)
	await process_frame
	main.rocket_design = RocketDesign.create_default()
	main._show_vehicle_editor()
	await process_frame
	assert(main.mode == "editor")
	assert(is_instance_valid(main.active_builder))
	assert(_find_label(main.active_builder, "VEHICLE BUILDER"))
	var payload_input: SpinBox = main.active_builder._payload_mass_input
	assert(is_instance_valid(payload_input))
	payload_input.value = 1200.0
	if not is_equal_approx(float(main.rocket_design.payload_mass), 1200.0):
		payload_input.value_changed.emit(payload_input.value)
	assert(is_equal_approx(float(main.rocket_design.payload_mass), 1200.0))
	for button_text in ["PRESETS", "EDIT PAYLOAD DETAILS", "SAVE", "LOAD", "LAUNCH", "BACK"]:
		assert(is_instance_valid(_find_button(main.active_builder, button_text)))
	print("Replacement vehicle builder integration tests passed.")
	main.active_builder.free()
	main.queue_free()
	await process_frame
	quit()


func _find_label(node: Node, expected_text: String) -> bool:
	if node is Label and node.text == expected_text:
		return true
	for child in node.get_children():
		if _find_label(child, expected_text):
			return true
	return false


func _find_button(node: Node, button_text: String) -> Button:
	if node is Button and node.text == button_text:
		return node
	for child in node.get_children():
		var found := _find_button(child, button_text)
		if found != null:
			return found
	return null
