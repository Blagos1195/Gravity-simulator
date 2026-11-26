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
	assert(builder._snap_selector.item_count == 8)
	assert(builder._snap_selector.get_item_text(builder._snap_selector.selected) == "Off")
	assert(builder._canvas.snap_mode == "Off")
	assert(is_equal_approx(builder._canvas.rotation_snap_degrees, 15.0))
	assert(builder._canvas._snap_position(Vector2(0.62, 0.62)) == Vector2(0.62, 0.62))
	builder._canvas.snap_mode = "0.5 m"
	assert(builder._canvas._snap_position(Vector2(0.62, 0.62)) == Vector2(0.5, 0.5))
	builder._canvas.snap_mode = "Off"
	assert(builder._parts_list.get_child_count() >= 14)
	builder._canvas.stage = {"components": [{}]}
	builder._canvas._component_rects = [{"index": 0, "rect": Rect2(100.0, 100.0, 50.0, 100.0), "attachment": "stack"}]
	var top_node: Dictionary = builder._canvas._find_attachment_target(Vector2(125.0, 101.0))
	assert(str(top_node.get("attachment", "")) == "stack")
	assert(int(top_node.get("insert_index", -1)) == 0)
	var side_node: Dictionary = builder._canvas._find_attachment_target(Vector2(101.0, 150.0))
	assert(str(side_node.get("attachment", "")) == "side")
	assert(int(side_node.get("side", 0)) == -1)
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
	side_builder.free()
	builder.free()
	print("KSP-style vehicle assembly builder tests passed.")
	quit()
