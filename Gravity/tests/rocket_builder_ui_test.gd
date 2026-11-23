extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var main := Main.new()
	main.size = Vector2(1280.0, 720.0)
	root.add_child(main)
	main.rocket_design = RocketDesign.create_default()
	main._show_vehicle_editor()
	assert(main.mode == "editor")
	assert(is_instance_valid(main.design_preview))
	assert(is_instance_valid(main.design_stats_label))
	assert(is_instance_valid(main.design_error_label))
	assert(main.design_stats_label.text.contains("IDEAL ΔV"))
	assert(main.design_error_label.text == "DESIGN VALID")
	var payload_input := _find_spinbox(main)
	assert(is_instance_valid(payload_input))
	payload_input.value = 1200.0
	if not is_equal_approx(float(main.rocket_design.payload_mass), 1200.0):
		payload_input.value_changed.emit(payload_input.value)
	assert(is_equal_approx(float(main.rocket_design.payload_mass), 1200.0))
	assert(main.design_error_label.text == "DESIGN VALID")
	main._start_flight()
	main._show_new_vehicle_dialog()
	var vehicle_dialog: Window
	for child in main.get_children():
		if child is Window:
			vehicle_dialog = child
			break
	assert(is_instance_valid(vehicle_dialog))
	var vehicle_selector: OptionButton = vehicle_dialog.get_child(0).get_child(1)
	assert(vehicle_selector.item_count >= 2)
	print("Rocket builder UI test passed.")
	main.queue_free()
	quit()


func _find_spinbox(node: Node) -> SpinBox:
	if node is SpinBox:
		return node
	for child in node.get_children():
		var found := _find_spinbox(child)
		if found != null:
			return found
	return null
