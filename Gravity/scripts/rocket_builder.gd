extends Window
class_name RocketBuilder

signal design_changed(design: Dictionary)

const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

class PartCard extends Button:
	var component: Dictionary = {}

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = str(component.get("label", component.get("id", "Part")))
		preview.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		set_drag_preview(preview)
		return {"source": "catalog", "id": str(component.get("id", ""))}

class AssemblyCanvas extends Control:
	signal component_dropped(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int)
	signal component_moved(from_index: int, to_index: int)
	signal component_selected(index: int)

	var stage: Dictionary = {}
	var selected_index := -1
	var zoom := 1.0
	var _component_rects: Array[Dictionary] = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(420.0, 500.0)
		queue_redraw()

	func _get_drag_data(at_position: Vector2) -> Variant:
		for index in range(_component_rects.size()):
			var item: Dictionary = _component_rects[index]
			if item.rect.has_point(at_position):
				selected_index = int(item.index)
				component_selected.emit(selected_index)
				var preview := Label.new()
				preview.text = str((stage.get("components", []) as Array)[selected_index].get("label", "Part"))
				set_drag_preview(preview)
				return {"source": "placed", "index": selected_index}
		return null

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and str(data.get("source", "")) in ["catalog", "placed"]

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		var center_x := size.x * 0.5
		if str(data.get("source", "")) == "catalog":
			var attachment := "radial" if absf(at_position.x - center_x) > 78.0 else "stack"
			var side := -1 if at_position.x < center_x else 1
			var insert_index := _insert_index(at_position.y)
			component_dropped.emit(str(data.get("id", "")), attachment, bool(get_meta("mirror_enabled", true)), side, insert_index)
		else:
			var from_index := int(data.get("index", -1))
			var to_index := _insert_index(at_position.y)
			if from_index >= 0 and to_index >= 0 and from_index != to_index:
				component_moved.emit(from_index, to_index)

	func _insert_index(y_position: float) -> int:
		for item in _component_rects:
			var rect: Rect2 = item.rect
			if y_position < rect.get_center().y:
				return int(item.index)
		return (stage.get("components", []) as Array).size()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				for item in _component_rects:
					if item.rect.has_point(event.position):
						component_selected.emit(int(item.index))
						accept_event()
						return
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = minf(2.5, zoom * 1.12)
				queue_redraw()
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = maxf(0.45, zoom / 1.12)
				queue_redraw()
				accept_event()

	func _draw() -> void:
		_component_rects.clear()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.028, 0.05))
		var grid_step := 24.0 * zoom
		var grid_x := fposmod(size.x * 0.5, grid_step)
		var grid_y := fposmod(size.y * 0.5, grid_step)
		for x in range(int(size.x / grid_step) + 2):
			var px := grid_x + float(x) * grid_step
			draw_line(Vector2(px, 0.0), Vector2(px, size.y), Color(0.12, 0.17, 0.24, 0.5), 1.0)
		for y in range(int(size.y / grid_step) + 2):
			var py := grid_y + float(y) * grid_step
			draw_line(Vector2(0.0, py), Vector2(size.x, py), Color(0.12, 0.17, 0.24, 0.5), 1.0)
		var center_x := size.x * 0.5
		draw_line(Vector2(center_x, 12.0), Vector2(center_x, size.y - 12.0), Color(0.3, 0.58, 0.8, 0.55), 1.2)
		var components: Array = stage.get("components", [])
		var axial: Array[Dictionary] = []
		var total_length := 0.0
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) == "radial":
				continue
			axial.append({"index": index, "component": component})
			total_length += maxf(0.5, float(component.get("length_m", 1.0)))
		var scale := minf(zoom * 5.0, (size.y - 72.0) / maxf(1.0, total_length))
		var total_height := total_length * scale
		var current_y := (size.y - total_height) * 0.5
		var max_radius := 0.5
		var axial_centers: Dictionary = {}
		for item in axial:
			max_radius = maxf(max_radius, float(item.component.get("collision_radius_m", 1.0)))
		var width_scale := minf(15.0 * zoom, maxf(4.0, (size.x * 0.22) / max_radius))
		for item in axial:
			var index := int(item.index)
			var component: Dictionary = item.component
			var height := maxf(12.0, float(component.get("length_m", 1.0)) * scale)
			var half_width := clampf(float(component.get("collision_radius_m", 1.0)) * width_scale, 9.0, size.x * 0.2)
			var rect := Rect2(Vector2(center_x - half_width, current_y), Vector2(half_width * 2.0, height))
			_draw_part(rect, component, index == selected_index)
			_component_rects.append({"index": index, "rect": rect})
			axial_centers[index] = rect.get_center().y
			draw_circle(Vector2(center_x, rect.position.y), 4.0, Color(0.35, 0.78, 1.0))
			draw_circle(Vector2(center_x, rect.end.y), 4.0, Color(0.35, 0.78, 1.0))
			current_y += height
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) != "radial":
				continue
			var height := maxf(16.0, float(component.get("length_m", 6.0)) * scale)
			var width := maxf(14.0, float(component.get("collision_radius_m", 1.0)) * width_scale * 0.85)
			var side := int(component.get("side", 1))
			var mirrored := bool(component.get("mirror", true))
			var mount_index := int(component.get("mount_index", -1))
			var y := float(axial_centers.get(mount_index, size.y * 0.5)) - height * 0.5
			var offset := max_radius * width_scale + width * 0.9 + 12.0
			var sides: Array = [-1, 1] if mirrored else [side]
			for direction in sides:
				var rect := Rect2(Vector2(center_x + float(direction) * offset - width * 0.5, y), Vector2(width, height))
				_draw_part(rect, component, index == selected_index)
				_component_rects.append({"index": index, "rect": rect})
				draw_line(Vector2(center_x + float(direction) * max_radius * width_scale, y + height * 0.5), Vector2(center_x + float(direction) * (offset - width * 0.5), y + height * 0.5), Color(0.6, 0.72, 0.84), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(12.0, 22.0), "PAYLOAD END", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0), "ENGINE END", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.9))

	func _draw_part(rect: Rect2, component: Dictionary, selected: bool) -> void:
		var color := Color(0.42, 0.62, 0.76)
		var rgb: Variant = component.get("color_rgb", component.get("visual_color_rgb", []))
		if rgb is Array and rgb.size() == 3:
			color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		var kind := str(component.get("kind", "structure"))
		var polygon := PackedVector2Array()
		match kind:
			"engine":
				polygon = PackedVector2Array([rect.position + Vector2(rect.size.x * 0.2, 0.0), rect.position + Vector2(rect.size.x * 0.8, 0.0), rect.position + Vector2(rect.size.x, rect.size.y), rect.position + Vector2(0.0, rect.size.y)])
			"decoupler":
				polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)])
			"structure":
				polygon = PackedVector2Array([rect.position + Vector2(rect.size.x * 0.5, 0.0), rect.position + Vector2(rect.size.x, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.8, rect.size.y), rect.position + Vector2(rect.size.x * 0.2, rect.size.y), rect.position + Vector2(0.0, rect.size.y * 0.5)])
			_:
				polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)])
		draw_colored_polygon(polygon, color)
		draw_rect(rect, Color(0.65, 0.84, 1.0) if selected else Color(0.12, 0.18, 0.25), false, 2.0 if selected else 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(4.0, minf(16.0, rect.size.y - 2.0)), str(component.get("label", component.get("id", "PART"))), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 10, Color(0.04, 0.06, 0.09))

var design: Dictionary = {}
var selected_stage_index := 0
var selected_component_index := -1
var mirror_enabled := true
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _canvas: AssemblyCanvas
var _parts_list: VBoxContainer
var _stage_list: VBoxContainer
var _inspector: VBoxContainer
var _stats: Label
var _search := ""
var _category := "all"
var _part_filter: OptionButton
var _search_input: LineEdit
var _property_inputs: Dictionary = {}
var _payload_selector: OptionButton
var _payload_mass_input: SpinBox
var _vehicle_name: LineEdit
var _mirror_button: CheckButton

func configure(source_design: Dictionary, stage_index: int = 0) -> void:
	design = source_design.duplicate(true)
	selected_stage_index = clampi(stage_index, 0, maxi(0, design.get("stages", []).size() - 1))
	var stages: Array = design.get("stages", [])
	for index in range(stages.size()):
		stages[index] = RocketAssembly.ensure_stage_components(stages[index])
	design["stages"] = stages

func _ready() -> void:
	title = "VEHICLE ASSEMBLY BUILDING"
	size = Vector2i(1320, 820)
	min_size = Vector2i(980, 640)
	transient = true
	close_requested.connect(_finish)
	_build_interface()
	_refresh()

func _build_interface() -> void:
	title = "VEHICLE ASSEMBLY BUILDING"
	size = Vector2i(1320, 820)
	min_size = Vector2i(980, 640)
	transient = true
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.add_theme_constant_override("margin_left", 12)
	root.add_theme_constant_override("margin_right", 12)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title_label := Label.new()
	title_label.text = "VEHICLE ASSEMBLY BUILDING"
	title_label.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	title_label.add_theme_font_size_override("font_size", 20)
	header.add_child(title_label)
	var name_input := LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.placeholder_text = "Vehicle name"
	name_input.text = str(design.get("name", "Custom Vehicle"))
	name_input.text_changed.connect(func(value: String):
		design["name"] = value
		_emit_design()
	)
	header.add_child(name_input)
	_vehicle_name = name_input
	var payload_label := Label.new()
	payload_label.text = "PAYLOAD"
	header.add_child(payload_label)
	var payload_selector := OptionButton.new()
	payload_selector.custom_minimum_size.x = 180
	var payload_options := RocketDesign.payload_options()
	var selected_payload := 0
	for index in range(payload_options.size()):
		var option: Dictionary = payload_options[index]
		payload_selector.add_item(str(option.get("label", option.get("id", "Payload"))))
		payload_selector.set_item_metadata(index, option)
		if str(option.get("id", "")) == str(design.get("payload_type", "")):
			selected_payload = index
	if not payload_options.is_empty():
		payload_selector.select(selected_payload)
	payload_selector.item_selected.connect(func(index: int):
		var option: Dictionary = payload_selector.get_item_metadata(index)
		design["payload_mass"] = float(option.get("mass", design.get("payload_mass", 500.0)))
		design["payload_type"] = str(option.get("id", "probe"))
		design["payload_visual"] = RocketDesign.payload_visual_data(str(option.get("id", "probe")))
		if is_instance_valid(_payload_mass_input):
			_payload_mass_input.set_value_no_signal(float(option.get("mass", 500.0)))
		_emit_design()
		_refresh_stats()
	)
	header.add_child(payload_selector)
	_payload_selector = payload_selector
	var payload_limits := RocketDesign.payload_mass_limits()
	var payload_mass_input := SpinBox.new()
	payload_mass_input.custom_minimum_size.x = 125.0
	payload_mass_input.min_value = float(payload_limits.get("minimum", 0.001))
	payload_mass_input.max_value = float(payload_limits.get("maximum", 1.0e300))
	payload_mass_input.step = float(payload_limits.get("step", 1.0))
	payload_mass_input.value = float(design.get("payload_mass", 500.0))
	payload_mass_input.tooltip_text = "Payload mass in kilograms"
	payload_mass_input.value_changed.connect(func(value: float):
		design["payload_mass"] = value
		design["payload_type"] = "custom"
		_refresh_stats()
		_emit_design()
	)
	header.add_child(payload_mass_input)
	_payload_mass_input = payload_mass_input
	var mirror := CheckButton.new()
	mirror.text = "MIRROR NEW RADIAL PARTS"
	mirror.button_pressed = true
	mirror.toggled.connect(func(enabled: bool):
		mirror_enabled = enabled
		if is_instance_valid(_canvas):
			_canvas.set_meta("mirror_enabled", enabled)
	)
	header.add_child(mirror)
	_mirror_button = mirror
	var undo_button := Button.new()
	undo_button.text = "UNDO"
	undo_button.pressed.connect(_undo_change)
	header.add_child(undo_button)
	var redo_button := Button.new()
	redo_button.text = "REDO"
	redo_button.pressed.connect(_redo_change)
	header.add_child(redo_button)
	var workspace := HSplitContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(workspace)
	var parts_panel := PanelContainer.new()
	parts_panel.custom_minimum_size.x = 245.0
	workspace.add_child(parts_panel)
	var parts_column := VBoxContainer.new()
	parts_column.add_theme_constant_override("separation", 6)
	parts_panel.add_child(parts_column)
	var parts_heading := Label.new()
	parts_heading.text = "PARTS CATALOGUE"
	parts_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	parts_column.add_child(parts_heading)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search parts..."
	_search_input.text_changed.connect(func(value: String):
		_search = value.to_lower()
		_refresh_parts()
	)
	parts_column.add_child(_search_input)
	_part_filter = OptionButton.new()
	for category in ["all", "tank", "engine", "decoupler", "structure", "radial"]:
		_part_filter.add_item(category.capitalize())
		_part_filter.set_item_metadata(_part_filter.item_count - 1, category)
	_part_filter.item_selected.connect(func(index: int):
		_category = str(_part_filter.get_item_metadata(index))
		_refresh_parts()
	)
	parts_column.add_child(_part_filter)
	var parts_scroll := ScrollContainer.new()
	parts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_column.add_child(parts_scroll)
	_parts_list = VBoxContainer.new()
	_parts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_scroll.add_child(_parts_list)
	var center_panel := PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(center_panel)
	var center_column := VBoxContainer.new()
	center_column.add_theme_constant_override("separation", 6)
	center_panel.add_child(center_column)
	var canvas_heading := Label.new()
	canvas_heading.text = "ASSEMBLY VIEW  •  SNAP PARTS TO STACK NODES OR SIDE MOUNTS"
	canvas_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	center_column.add_child(canvas_heading)
	_canvas = AssemblyCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.component_dropped.connect(_on_component_dropped)
	_canvas.component_moved.connect(_on_component_moved)
	_canvas.component_selected.connect(_on_component_selected)
	center_column.add_child(_canvas)
	var canvas_tools := HBoxContainer.new()
	canvas_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	var zoom_out := Button.new()
	zoom_out.text = "−"
	zoom_out.pressed.connect(func():
		_canvas.zoom = maxf(0.45, _canvas.zoom / 1.15)
		_canvas.queue_redraw()
	)
	canvas_tools.add_child(zoom_out)
	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.pressed.connect(func():
		_canvas.zoom = minf(2.5, _canvas.zoom * 1.15)
		_canvas.queue_redraw()
	)
	canvas_tools.add_child(zoom_in)
	var fit := Button.new()
	fit.text = "FIT"
	fit.pressed.connect(func():
		_canvas.zoom = 1.0
		_canvas.queue_redraw()
	)
	canvas_tools.add_child(fit)
	center_column.add_child(canvas_tools)
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size.x = 285.0
	workspace.add_child(right_panel)
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 6)
	right_panel.add_child(right_column)
	var stage_heading := Label.new()
	stage_heading.text = "STAGING"
	stage_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	right_column.add_child(stage_heading)
	var stage_scroll := ScrollContainer.new()
	stage_scroll.custom_minimum_size.y = 155.0
	stage_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_child(stage_scroll)
	_stage_list = VBoxContainer.new()
	stage_scroll.add_child(_stage_list)
	var stage_tools := HBoxContainer.new()
	right_column.add_child(stage_tools)
	var stage_options := OptionButton.new()
	stage_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in RocketDesign.stage_part_options():
		stage_options.add_item(str(option.get("label", "Stage")))
		stage_options.set_item_metadata(stage_options.item_count - 1, str(option.get("id", "")))
	stage_tools.add_child(stage_options)
	var add_stage := Button.new()
	add_stage.text = "+"
	add_stage.tooltip_text = "Add a new staging group"
	add_stage.pressed.connect(func():
		var stage := RocketDesign.configure_stage(str(stage_options.get_selected_metadata()), 1, 1.0)
		if not stage.is_empty():
			_push_undo()
			var stages: Array = design.get("stages", [])
			stages.append(RocketAssembly.ensure_stage_components(stage))
			design["stages"] = stages
			selected_stage_index = stages.size() - 1
			selected_component_index = -1
			_changed()
	)
	stage_tools.add_child(add_stage)
	var duplicate_stage := Button.new()
	duplicate_stage.text = "COPY"
	duplicate_stage.pressed.connect(_duplicate_selected_stage)
	stage_tools.add_child(duplicate_stage)
	var delete_stage := Button.new()
	delete_stage.text = "DEL"
	delete_stage.pressed.connect(_delete_selected_stage)
	stage_tools.add_child(delete_stage)
	var move_stage_row := HBoxContainer.new()
	right_column.add_child(move_stage_row)
	var stage_up := Button.new()
	stage_up.text = "MOVE TOWARD PAYLOAD"
	stage_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_up.pressed.connect(func(): _move_stage(1))
	move_stage_row.add_child(stage_up)
	var stage_down := Button.new()
	stage_down.text = "MOVE TOWARD ENGINE"
	stage_down.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_down.pressed.connect(func(): _move_stage(-1))
	move_stage_row.add_child(stage_down)
	var separator := HSeparator.new()
	right_column.add_child(separator)
	var selected_heading := Label.new()
	selected_heading.text = "PART INSPECTOR"
	selected_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	right_column.add_child(selected_heading)
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(inspector_scroll)
	_inspector = VBoxContainer.new()
	_inspector.add_theme_constant_override("separation", 6)
	inspector_scroll.add_child(_inspector)
	_refresh_inspector()
	var stats := Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_theme_color_override("font_color", Color(0.76, 0.85, 0.94))
	root.add_child(stats)
	_stats = stats
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(footer)
	var note := Label.new()
	note.text = "Drag parts onto the stack nodes or side mounts. Drag installed parts to reorder them. Mirroring duplicates radial mounts."
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(note)
	var done := Button.new()
	done.text = "DONE"
	done.custom_minimum_size.x = 110.0
	done.pressed.connect(_finish)
	footer.add_child(done)
	_canvas.set_meta("mirror_enabled", mirror_enabled)

func _refresh() -> void:
	if not is_instance_valid(_canvas):
		return
	_canvas.stage = _current_stage()
	_canvas.selected_index = selected_component_index
	_canvas.set_meta("mirror_enabled", mirror_enabled)
	_canvas.queue_redraw()
	_refresh_parts()
	_refresh_stages()
	_refresh_inspector()
	_refresh_stats()

func _current_stage() -> Dictionary:
	var stages: Array = design.get("stages", [])
	if selected_stage_index < 0 or selected_stage_index >= stages.size():
		return {}
	return stages[selected_stage_index]

func _refresh_parts() -> void:
	if not is_instance_valid(_parts_list):
		return
	for child in _parts_list.get_children():
		child.queue_free()
	for option in RocketAssembly.component_options():
		var kind := str(option.get("kind", "structure"))
		var label := str(option.get("label", option.get("id", "Part")))
		if _category != "all" and _category != kind:
			continue
		if not _search.is_empty() and not (label.to_lower().contains(_search) or kind.contains(_search)):
			continue
		var card := PartCard.new()
		card.component = option
		card.text = "%s\n%s  •  %.0f kg" % [label, kind.to_upper(), float(option.get("dry_mass", 0.0))]
		card.custom_minimum_size.y = 58.0
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.pressed.connect(func(): _add_component(str(option.get("id", "")), "radial" if kind == "radial" else "stack", mirror_enabled, 1, -1))
		_parts_list.add_child(card)

func _on_component_dropped(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int) -> void:
	_add_component(component_id, attachment, mirrored, side, insert_index)

func _add_component(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int) -> void:
	var stage := _current_stage()
	if stage.is_empty():
		return
	_push_undo()
	var updated := RocketAssembly.add_component(stage, component_id, attachment, mirrored, side, insert_index)
	if updated.is_empty():
		return
	var components: Array = updated.get("components", [])
	if attachment == "radial" and insert_index >= 0:
		var axial_indices: Array[int] = []
		for index in range(components.size() - 1):
			if str(components[index].get("attachment", "stack")) != "radial":
				axial_indices.append(index)
		if not axial_indices.is_empty():
			var mount_index := axial_indices[0]
			for candidate in axial_indices:
				if absi(candidate - insert_index) < absi(mount_index - insert_index):
					mount_index = candidate
			components[components.size() - 1]["mount_index"] = mount_index
	if attachment == "stack" and insert_index >= 0 and insert_index < components.size() - 1:
		for index in range(components.size() - 1):
			var existing_component: Dictionary = components[index]
			if str(existing_component.get("attachment", "stack")) == "radial":
				var mount_index := int(existing_component.get("mount_index", -1))
				if mount_index >= insert_index:
					existing_component["mount_index"] = mount_index + 1
					components[index] = existing_component
		var added: Variant = components.pop_back()
		components.insert(insert_index, added)
		updated = RocketAssembly.compile_stage(updated, components)
	design["stages"][selected_stage_index] = updated
	selected_component_index = components.size() - 1 if attachment == "stack" else components.size() - 1
	_changed()

func _on_component_moved(from_index: int, to_index: int) -> void:
	var components: Array = _current_stage().get("components", []).duplicate(true)
	if from_index < 0 or from_index >= components.size() or to_index < 0 or to_index > components.size():
		return
	_push_undo()
	var item: Variant = components.pop_at(from_index)
	var destination := clampi(to_index, 0, components.size())
	if item is Dictionary and str(item.get("attachment", "stack")) == "radial":
		var item_mount := int(item.get("mount_index", -1))
		if from_index < destination and item_mount > from_index and item_mount <= destination:
			item["mount_index"] = item_mount - 1
		elif destination < from_index and item_mount >= destination and item_mount < from_index:
			item["mount_index"] = item_mount + 1
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("attachment", "stack")) != "radial":
			continue
		var mount_index := int(component.get("mount_index", -1))
		if mount_index == from_index:
			component["mount_index"] = destination
		elif from_index < destination and mount_index > from_index and mount_index <= destination:
			component["mount_index"] = mount_index - 1
		elif destination < from_index and mount_index >= destination and mount_index < from_index:
			component["mount_index"] = mount_index + 1
		components[index] = component
	components.insert(destination, item)
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(_current_stage(), components)
	selected_component_index = to_index
	_changed()

func _on_component_selected(index: int) -> void:
	selected_component_index = index
	_canvas.selected_index = index
	_canvas.queue_redraw()
	_refresh_inspector()

func _refresh_stages() -> void:
	for child in _stage_list.get_children():
		child.queue_free()
	var stages: Array = design.get("stages", [])
	for index in range(stages.size()):
		var button := Button.new()
		var stage: Dictionary = stages[index]
		button.text = "STAGE %02d  •  %d PARTS" % [index + 1, (stage.get("components", []) as Array).size()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = index == selected_stage_index
		button.pressed.connect(func():
			selected_stage_index = index
			selected_component_index = -1
			_refresh()
		)
		_stage_list.add_child(button)

func _refresh_inspector() -> void:
	if not is_instance_valid(_inspector):
		return
	for child in _inspector.get_children():
		if child is Label and child.text in ["STAGING", "PART INSPECTOR"]:
			continue
		child.queue_free()
	var components: Array = _current_stage().get("components", [])
	if selected_component_index < 0 or selected_component_index >= components.size():
		var hint := Label.new()
		hint.text = "Select a part on the rocket to inspect its properties."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector.add_child(hint)
		return
	var component: Dictionary = components[selected_component_index]
	var title_label := Label.new()
	title_label.text = str(component.get("label", component.get("id", "PART")))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector.add_child(title_label)
	var mirror_selected := CheckButton.new()
	mirror_selected.text = "MIRROR THIS RADIAL PART"
	mirror_selected.disabled = str(component.get("attachment", "stack")) != "radial"
	mirror_selected.button_pressed = bool(component.get("mirror", false))
	mirror_selected.toggled.connect(func(enabled: bool):
		_update_component_property("mirror", enabled)
	)
	_inspector.add_child(mirror_selected)
	var fields := [
		{"key":"dry_mass","label":"Dry mass (kg)","max":100000000.0},
		{"key":"fuel_capacity","label":"Propellant (kg)","max":1000000000.0},
		{"key":"thrust","label":"Sea-level thrust (N)","max":100000000000.0},
		{"key":"vacuum_thrust","label":"Vacuum thrust (N)","max":100000000000.0},
		{"key":"flow","label":"Fuel flow (kg/s)","max":100000000.0},
		{"key":"length_m","label":"Length (m)","max":100000.0},
		{"key":"collision_radius_m","label":"Radius (m)","max":10000.0}
	]
	for field in fields:
		if not component.has(field.key):
			continue
		var row := VBoxContainer.new()
		var label := Label.new()
		label.text = str(field.label)
		row.add_child(label)
		var input := SpinBox.new()
		input.min_value = 0.0
		input.max_value = float(field.max)
		input.step = 1.0 if str(field.key) in ["dry_mass","fuel_capacity","thrust","vacuum_thrust"] else 0.1
		input.value = float(component[field.key])
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.value_changed.connect(func(value: float): _update_component_property(str(field.key), value))
		row.add_child(input)
		_inspector.add_child(row)
	var actions := HBoxContainer.new()
	var duplicate := Button.new()
	duplicate.text = "DUPLICATE"
	duplicate.pressed.connect(_duplicate_selected_component)
	actions.add_child(duplicate)
	var remove := Button.new()
	remove.text = "REMOVE PART"
	remove.pressed.connect(_remove_selected_component)
	actions.add_child(remove)
	_inspector.add_child(actions)

func _update_component_property(key: String, value: Variant) -> void:
	var stage := _current_stage()
	var components: Array = stage.get("components", []).duplicate(true)
	if selected_component_index < 0 or selected_component_index >= components.size():
		return
	_push_undo()
	var component: Dictionary = components[selected_component_index]
	component[key] = value
	components[selected_component_index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(stage, components)
	_changed(false)

func _duplicate_selected_component() -> void:
	var components: Array = _current_stage().get("components", []).duplicate(true)
	if selected_component_index < 0 or selected_component_index >= components.size():
		return
	_push_undo()
	var destination := selected_component_index + 1
	var duplicate: Dictionary = components[selected_component_index].duplicate(true)
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("attachment", "stack")) == "radial" and int(component.get("mount_index", -1)) >= destination:
			component["mount_index"] = int(component.get("mount_index", -1)) + 1
			components[index] = component
	if str(duplicate.get("attachment", "stack")) == "radial" and int(duplicate.get("mount_index", -1)) >= destination:
		duplicate["mount_index"] = int(duplicate.get("mount_index", -1)) + 1
	components.insert(destination, duplicate)
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(_current_stage(), components)
	selected_component_index = destination
	_changed()

func _remove_selected_component() -> void:
	var stage := _current_stage()
	var components: Array = stage.get("components", []).duplicate(true)
	if selected_component_index < 0 or selected_component_index >= components.size():
		return
	_push_undo()
	components.remove_at(selected_component_index)
	var axial_indices: Array[int] = []
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("attachment", "stack")) != "radial":
			axial_indices.append(index)
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("attachment", "stack")) != "radial":
			continue
		var mount_index := int(component.get("mount_index", -1))
		if mount_index > selected_component_index:
			component["mount_index"] = mount_index - 1
		elif mount_index == selected_component_index:
			component["mount_index"] = axial_indices[mini(axial_indices.size() - 1, selected_component_index)] if not axial_indices.is_empty() else -1
		components[index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(stage, components)
	selected_component_index = -1
	_changed()

func _duplicate_selected_stage() -> void:
	var stages: Array = design.get("stages", []).duplicate(true)
	if selected_stage_index < 0 or selected_stage_index >= stages.size():
		return
	_push_undo()
	stages.insert(selected_stage_index + 1, stages[selected_stage_index].duplicate(true))
	design["stages"] = stages
	selected_stage_index += 1
	_changed()

func _delete_selected_stage() -> void:
	var stages: Array = design.get("stages", []).duplicate(true)
	if stages.size() <= RocketDesign.MIN_STAGES:
		return
	_push_undo()
	stages.remove_at(selected_stage_index)
	design["stages"] = stages
	selected_stage_index = clampi(selected_stage_index, 0, stages.size() - 1)
	selected_component_index = -1
	_changed()

func _move_stage(direction: int) -> void:
	var stages: Array = design.get("stages", []).duplicate(true)
	var destination := selected_stage_index + direction
	if destination < 0 or destination >= stages.size():
		return
	_push_undo()
	var item: Variant = stages.pop_at(selected_stage_index)
	stages.insert(destination, item)
	design["stages"] = stages
	selected_stage_index = destination
	_changed()

func _push_undo() -> void:
	_undo.append(design.duplicate(true))
	if _undo.size() > 60:
		_undo.pop_front()
	_redo.clear()

func _undo_change() -> void:
	if _undo.is_empty():
		return
	_redo.append(design.duplicate(true))
	design = _undo.pop_back()
	selected_stage_index = clampi(selected_stage_index, 0, design.get("stages", []).size() - 1)
	selected_component_index = -1
	_changed()

func _redo_change() -> void:
	if _redo.is_empty():
		return
	_undo.append(design.duplicate(true))
	design = _redo.pop_back()
	selected_stage_index = clampi(selected_stage_index, 0, design.get("stages", []).size() - 1)
	selected_component_index = -1
	_changed()

func _refresh_stats() -> void:
	if not is_instance_valid(_stats):
		return
	var stage := _current_stage()
	var mass := RocketDesign.total_initial_mass(design)
	var thrust := RocketDesign.stage_total_thrust(stage, true)
	var twr := thrust / maxf(1.0, RocketDesign.stage_ignition_mass(design, selected_stage_index) * RocketDesign.G0)
	_stats.text = "TOTAL MASS  %.1f t     STAGE TWR  %.2f     IDEAL ΔV  %.2f km/s     STAGES  %d" % [mass / 1000.0, twr, RocketDesign.total_delta_v(design) / 1000.0, design.get("stages", []).size()]

func _changed(refresh_inspector: bool = true) -> void:
	if refresh_inspector:
		_refresh()
	else:
		_canvas.stage = _current_stage()
		_canvas.queue_redraw()
		_refresh_stats()
	_emit_design()

func _emit_design() -> void:
	design_changed.emit(design.duplicate(true))

func _finish() -> void:
	_emit_design()
	queue_free()
