extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")

func _initialize() -> void:
	var main := Main.new()
	main.size = Vector2(1280.0, 720.0)
	root.add_child(main)
	main.rocket_design = RocketDesign.create_default()
	main.rocket_design["payload_type"] = "modded_probe"
	main.rocket_design["payload_visual"] = {"visual_type": "probe", "visual_color_rgb": [0.1, 0.2, 0.3]}
	main._show_vehicle_editor()
	assert(main.rocket_design.payload_type == "modded_probe")
	assert(main.rocket_design.payload_visual.visual_color_rgb == [0.1, 0.2, 0.3])
	assert(main.mode == "editor")
	assert(is_instance_valid(main.active_builder))
	assert(main.active_builder.title == "VEHICLE ASSEMBLY BUILDING")
	var payload_input: SpinBox = main.active_builder._payload_mass_input
	assert(is_instance_valid(payload_input))
	payload_input.value = 1200.0
	if not is_equal_approx(float(main.rocket_design.payload_mass), 1200.0):
		payload_input.value_changed.emit(payload_input.value)
	assert(is_equal_approx(float(main.rocket_design.payload_mass), 1200.0))
	main._show_payload_editor()
	var payload_dialog: ConfirmationDialog
	for child in main.get_children():
		if child is ConfirmationDialog and child.title == "EDIT PAYLOAD APPEARANCE":
			payload_dialog = child
			break
	assert(is_instance_valid(payload_dialog))
	main._apply_payload_editor_values({
		"visual_type": "cargo",
		"visual_width_factor": 1.4,
		"visual_height_factor": 1.2,
		"visual_color_r": 0.11,
		"visual_color_g": 0.22,
		"visual_color_b": 0.33
	})
	assert(main.rocket_design.payload_visual.visual_type == "cargo")
	assert(is_equal_approx(float(main.rocket_design.payload_visual.visual_width_factor), 1.4))
	assert(main.rocket_design.payload_visual.visual_color_rgb == [0.11, 0.22, 0.33])
	payload_dialog.free()
	main._show_stage_editor(0)
	var stage_dialog: ConfirmationDialog
	for child in main.get_children():
		if child is ConfirmationDialog:
			stage_dialog = child
			break
	assert(is_instance_valid(stage_dialog))
	var dry_mass_input := _find_tooltip_spinbox(stage_dialog, "dry_mass")
	assert(is_instance_valid(dry_mass_input))
	var edited_dry_mass := float(main.rocket_design["stages"][0].dry_mass) + 1000.0
	main._apply_stage_editor_values(0, {"name": "Core Booster", "dry_mass": edited_dry_mass, "engine_layout": "radial", "visual_color_r": 0.12, "visual_color_g": 0.34, "visual_color_b": 0.56})
	assert(main.rocket_design["stages"][0].name == "Core Booster")
	assert(is_equal_approx(float(main.rocket_design["stages"][0].dry_mass), edited_dry_mass))
	assert(main.rocket_design["stages"][0].engine_layout == "radial")
	assert(main.rocket_design["stages"][0].visual_color_rgb == [0.12, 0.34, 0.56])
	var red_input := _find_tooltip_spinbox(stage_dialog, "visual_color_r")
	assert(is_instance_valid(red_input))
	assert(is_equal_approx(red_input.min_value, 0.0))
	assert(is_equal_approx(red_input.max_value, 1.0))
	assert(main.design_error_label.text == "DESIGN VALID")
	stage_dialog.free()
	var original_stage: Dictionary = main.rocket_design["stages"][0].duplicate(true)
	var original_stage_count: int = main.rocket_design["stages"].size()
	main._duplicate_stage(0)
	assert(main.rocket_design["stages"].size() == original_stage_count + 1)
	assert(main.rocket_design["stages"][1] == original_stage)
	main.rocket_design["stages"][1]["visual_color_rgb"][0] = 0.9
	assert(is_equal_approx(float(main.rocket_design["stages"][0]["visual_color_rgb"][0]), 0.12))
	main.rocket_design["stages"].remove_at(1)
	main._show_vehicle_editor()
	var blank_design := RocketDesign.create_blank()
	assert(str(blank_design.get("name", "")) == "Custom Vehicle")
	assert(RocketDesign.validation_errors(blank_design).is_empty())
	main._start_flight()
	assert(main.sim.landed_surface_normal == Vector2.UP)
	var second_design := RocketDesign.create_blank()
	main._launch_vehicle_design(second_design)
	assert(main.fleet_sims.size() == 2)
	assert(main.sim == main.fleet_sims[1])
	assert(main.sim.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	main._advance_fleet(0.016)
	assert(main.sim.fleet_visuals.size() == 1)
	main._show_new_vehicle_dialog()
	var vehicle_dialog: Window
	for child in main.get_children():
		if child is Window and child.title == "BUILD OR SELECT A VEHICLE":
			vehicle_dialog = child
			break
	assert(is_instance_valid(vehicle_dialog))
	var vehicle_selector: OptionButton = vehicle_dialog.get_child(0).get_child(1)
	assert(vehicle_selector.item_count >= 2)
	print("Rocket builder UI test passed.")
	main.queue_free()
	quit()


func _find_spinbox(node: Node) -> SpinBox:
	if node is SpinBox and node.tooltip_text == "Set the payload mass directly in kilograms.":
		return node
	for child in node.get_children():
		var found := _find_spinbox(child)
		if found != null:
			return found
	return null


func _find_tooltip_spinbox(node: Node, tooltip: String) -> SpinBox:
	if node is SpinBox and node.tooltip_text == tooltip:
		return node
	for child in node.get_children():
		var found := _find_tooltip_spinbox(child, tooltip)
		if found != null:
			return found
	return null


func _find_button(node: Node, button_text: String) -> Button:
	if node is Button and node.text == button_text:
		return node
	for child in node.get_children():
		var found := _find_button(child, button_text)
		if found != null:
			return found
	return null

