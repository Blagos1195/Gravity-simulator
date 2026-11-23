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
