extends SceneTree

const RocketBuilder = preload("res://scripts/rocket_builder.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

func _find_label(node: Node, expected_text: String) -> bool:
	if node is Label and node.text == expected_text:
		return true
	for child in node.get_children():
		if _find_label(child, expected_text):
			return true
	return false

func _initialize() -> void:
	var design := RocketDesign.create_default()
	var builder := RocketBuilder.new()
	builder.configure(design, 0)
	builder._build_interface()
	builder._refresh()
	assert(_find_label(builder, "VEHICLE BUILDER"))
	assert(builder._snap_selector.item_count == 2)
	assert(builder._snap_selector.get_item_text(0) == "Free")
	assert(builder._snap_selector.get_item_text(1) == "Parts")
	assert(builder._snap_selector.get_item_text(builder._snap_selector.selected) == "Free")
	assert(builder._canvas.snap_mode == "Off")
	assert(is_equal_approx(builder._canvas.rotation_snap_degrees, 15.0))
	assert(builder._canvas._snap_position(Vector2(0.62, 0.62)) == Vector2(0.62, 0.62))
	assert(builder._parts_list.get_child_count() >= 14)
	builder._canvas.stage = {"components": [{}]}
	builder._canvas._component_rects = [{"index": 0, "rect": Rect2(100.0, 100.0, 50.0, 100.0), "attachment": "stack"}]
	var top_node: Dictionary = builder._canvas._find_attachment_target(Vector2(125.0, 101.0))
	assert(str(top_node.get("attachment", "")) == "stack")
	assert(int(top_node.get("insert_index", -1)) == 0)
	var rotated_rect := Rect2(100.0, 100.0, 40.0, 100.0)
	var rotated_item := {"index": 0, "rect": rotated_rect, "attachment": "stack", "center": rotated_rect.get_center(), "rotation": PI * 0.5}
	assert(not builder._canvas._rect_hit(rotated_item, Vector2(100.0, 100.0)))
	assert(builder._canvas._rect_hit(rotated_item, Vector2(120.0, 160.0)))
	var custom_nodes := builder._canvas._component_attachment_nodes(rotated_rect, {"rotation_deg": 90.0, "attachment_nodes": [{"id": "left_mount", "position": [-0.5, 0.0], "direction": [-1.0, 0.0]}]})
	assert(custom_nodes.size() == 1)
	assert(Vector2(custom_nodes[0].direction).is_equal_approx(Vector2(0.0, -1.0)))
	var side_node: Dictionary = builder._canvas._find_attachment_target(Vector2(101.0, 150.0))
	assert(str(side_node.get("attachment", "")) == "side")
	assert(int(side_node.get("side", 0)) == -1)
	builder._canvas._component_rects = [{"index": 0, "rect": Rect2(100.0, 100.0, 50.0, 100.0), "attachment": "free"}]
	var moved_part_target: Dictionary = builder._canvas._find_attachment_target(Vector2(151.0, 150.0))
	assert(str(moved_part_target.get("attachment", "")) == "free")
	assert(str(moved_part_target.get("edge", "")) == "right")
	var moved_preview := builder._canvas._preview_position_for_target(Vector2(151.0, 150.0), moved_part_target, {"component": {"length_m": 2.0, "collision_radius_m": 0.5}})
	assert(moved_preview.x > 150.0)
	assert(is_equal_approx(moved_preview.y, 150.0))
	assert(builder._stage_list.get_child_count() == design.stages.size())
	builder._payload_mass_input.value = 900.0
	if not is_equal_approx(float(builder.design.payload_mass), 900.0):
		builder._payload_mass_input.value_changed.emit(900.0)
	assert(is_equal_approx(float(builder.design.payload_mass), 900.0))
	assert(str(builder.design.payload_type) == "custom")
	builder._add_component("medium_tank", "stack", true, 1, -1)
	var stage: Dictionary = builder.design.stages[0]
	assert(stage.components.size() == 3)
	assert(str(stage.components[1].id) == "medium_tank")
	builder._add_component("solid_booster_pair", "radial", true, -1, 1)
	stage = builder.design.stages[0]
	assert(bool(stage.components[3].mirror))
	assert(str(stage.components[3].attachment) == "radial")
	assert(int(stage.components[3].mount_index) == 1)
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(stage).dry_mass), 16000.0))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(stage).fuel_capacity), 84000.0))
	builder._update_component_property("mirror", false)
	stage = builder.design.stages[0]
	assert(not bool(stage.components[3].mirror))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(stage).dry_mass), 8000.0))
	builder._undo_change()
	stage = builder.design.stages[0]
	assert(bool(stage.components[3].mirror))
	builder._redo_change()
	stage = builder.design.stages[0]
	assert(not bool(stage.components[3].mirror))
	builder._on_component_moved(1, 0)
	stage = builder.design.stages[0]
	assert(str(stage.components[0].id) == "medium_tank")
	assert(int(stage.components[3].mount_index) == 0)
	builder._remove_selected_component()
	stage = builder.design.stages[0]
	assert(int(stage.components[2].mount_index) == 0)
	assert(RocketDesign.validation_errors(builder.design).is_empty())
	var stage_count: int = builder.design.stages.size()
	builder._duplicate_selected_stage()
	assert(builder.design.stages.size() == stage_count + 1)
	var moved_stage: Dictionary = builder.design.stages[1].duplicate(true)
	builder._move_stage(-1)
	assert(builder.design.stages[0] == moved_stage)
	builder._on_component_selected(2)
	builder._update_component_property("side", -1)
	assert(int(builder.design.stages[0].components[2].side) == -1)
	var part_count: int = builder.design.stages[0].components.size()
	builder._duplicate_selected_component()
	assert(builder.design.stages[0].components.size() == part_count + 1)
	var connected_design := RocketDesign.create_default()
	var connected_stage: Dictionary = RocketAssembly.ensure_stage_components(connected_design.stages[0])
	var connected_components: Array = connected_stage.components
	var parent_uid := str(connected_components[0].get("part_uid", ""))
	var graph_builder := RocketBuilder.new()
	graph_builder.configure(connected_design, 0)
	graph_builder._build_interface()
	graph_builder._refresh()
	graph_builder._add_component("battery_pack", "free", false, 1, -1, Vector2(0.0, 0.0), parent_uid, "right")
	var linked_component: Dictionary = graph_builder.design.stages[0].components.back()
	assert(str(linked_component.get("structural_parent_uid", "")) == parent_uid)
	assert(not str(RocketDesign.validation_errors(graph_builder.design)).contains("disconnected part"))
	var loose_design := RocketDesign.create_default()
	var loose_builder := RocketBuilder.new()
	loose_builder.configure(loose_design, 0)
	loose_builder._build_interface()
	loose_builder._refresh()
	loose_builder._add_component("battery_pack", "free", false, 1, -1, Vector2(0.0, 0.0))
	var loose_errors := RocketDesign.validation_errors(loose_builder.design)
	assert(str(loose_errors).contains("disconnected part"))
	graph_builder.free()
	loose_builder.free()
	var emitted_designs: Array[Dictionary] = []
	builder.design_changed.connect(func(updated: Dictionary): emitted_designs.append(updated))
	builder._emit_design()
	assert(not emitted_designs.is_empty())
	var side_design := RocketDesign.create_default()
	var side_base: Dictionary = RocketAssembly.ensure_stage_components(side_design.stages[0])
	var side_builder := RocketBuilder.new()
	side_builder.configure(side_design, 0)
	side_builder._build_interface()
	side_builder._refresh()
	side_builder._add_component("medium_tank", "side", true, 1, 0)
	var side_stage: Dictionary = side_builder.design.stages[0]
	var side_part: Dictionary = side_stage.components[2]
	assert(str(side_part.attachment) == "side")
	assert(bool(side_part.mirror))
	assert(int(side_part.mount_index) == 0)
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(side_stage), RocketDesign.stage_total_dry_mass(side_base) + 12000.0))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(side_stage), RocketDesign.stage_total_fuel_capacity(side_base) + 160000.0))
	side_builder._on_component_repositioned(2, "stack", 1, 0)
	side_stage = side_builder.design.stages[0]
	assert(str(side_stage.components[0].id) == "medium_tank")
	assert(str(side_stage.components[0].attachment) == "stack")
	side_builder._on_component_repositioned(0, "side", -1, 0)
	side_stage = side_builder.design.stages[0]
	assert(str(side_stage.components.back().attachment) == "side")
	assert(int(side_stage.components.back().mount_index) >= 0)
	var group_builder := RocketBuilder.new()
	group_builder.configure(RocketDesign.create_default(), 0)
	group_builder._build_interface()
	group_builder._refresh()
	group_builder._canvas.size = Vector2(800.0, 600.0)
	group_builder._canvas.selected_indices = [0]
	group_builder._canvas.selected_index = 0
	group_builder._canvas._component_rects = [
		{"index": 0, "rect": Rect2(100.0, 100.0, 40.0, 80.0), "attachment": "stack"},
		{"index": 1, "rect": Rect2(160.0, 100.0, 40.0, 80.0), "attachment": "stack"}
	]
	var multi_select_event := InputEventMouseButton.new()
	multi_select_event.button_index = MOUSE_BUTTON_LEFT
	multi_select_event.pressed = true
	multi_select_event.ctrl_pressed = true
	multi_select_event.position = Vector2(180.0, 140.0)
	group_builder._canvas._gui_input(multi_select_event)
	assert(group_builder._canvas.selected_indices.size() == 2)
	var zoom_anchor := Vector2(180.0, 240.0)
	var before_zoom := (zoom_anchor - group_builder._canvas.size * 0.5 - group_builder._canvas.view_offset) / group_builder._canvas.zoom
	group_builder._canvas._zoom_at(2.0, zoom_anchor)
	var after_zoom := (zoom_anchor - group_builder._canvas.size * 0.5 - group_builder._canvas.view_offset) / group_builder._canvas.zoom
	assert(before_zoom.is_equal_approx(after_zoom))
	var pan_offset_before := group_builder._canvas.view_offset
	var pan_start := InputEventMouseButton.new()
	pan_start.button_index = MOUSE_BUTTON_MIDDLE
	pan_start.pressed = true
	pan_start.position = Vector2(100.0, 100.0)
	group_builder._canvas._gui_input(pan_start)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.position = Vector2(145.0, 130.0)
	group_builder._canvas._gui_input(pan_motion)
	assert(group_builder._canvas.view_offset.distance_to(pan_offset_before + Vector2(45.0, 30.0)) < 0.01)
	var group_stage_before: Dictionary = group_builder.design.stages[0]
	assert(group_stage_before.components.size() >= 2)
	group_builder._on_components_position_changed([0, 1], [Vector2(-2.0, 0.0), Vector2(2.0, 0.0)])
	var group_stage_after: Dictionary = group_builder.design.stages[0]
	assert(str(group_stage_after.components[0].attachment) == "free")
	assert(str(group_stage_after.components[1].attachment) == "free")
	assert(group_stage_after.components[0].position_m == [-2.0, 0.0])
	assert(group_stage_after.components[1].position_m == [2.0, 0.0])
	group_builder.free()
	side_builder.free()
	builder.free()
	print("KSP-style vehicle assembly builder tests passed.")
	quit()
