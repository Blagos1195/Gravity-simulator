extends Control
class_name RocketBuilder

signal design_changed(design: Dictionary)
signal save_requested
signal load_requested
signal launch_requested
signal back_requested
signal payload_edit_requested

const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const StagingSystem = preload("res://scripts/staging_system.gd")

class PartCard extends Button:
	var component: Dictionary = {}

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = str(component.get("label", component.get("id", "Part")))
		preview.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		set_drag_preview(preview)
		return {"source": "catalog", "id": str(component.get("id", "")), "kind": str(component.get("kind", ""))}

class AssemblyCanvas extends Control:
	signal component_dropped(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int, position_m: Vector2)
	signal component_moved(from_index: int, to_index: int)
	signal component_position_changed(index: int, position_m: Vector2)
	signal component_rotated(index: int, rotation_deg: float)
	signal component_selected(index: int)

	var stage: Dictionary = {}
	var design: Dictionary = {}
	var selected_stage_index := 0
	var selected_index := -1
	var zoom := 1.0
	var snap_mode := "0.5 m"
	var _component_rects: Array[Dictionary] = []
	var _rotating_index := -1
	var _rotation_center := Vector2.ZERO
	var _rotation_start_angle := 0.0
	var _rotation_start_degrees := 0.0
	var _drawing_scale := 1.0
	var _drawing_width_scale := 1.0
	var _drawing_stage_center_y := 0.0

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
		var position_m := _snap_position(_canvas_to_metres(at_position))
		if str(data.get("source", "")) == "catalog":
			component_dropped.emit(str(data.get("id", "")), "free", false, 1, -1, position_m)
		else:
			var from_index := int(data.get("index", -1))
			var components: Array = stage.get("components", [])
			if from_index < 0 or from_index >= components.size():
				return
			if str(components[from_index].get("attachment", "stack")) == "free":
				component_position_changed.emit(from_index, position_m)
			else:
				var to_index := _insert_index(at_position.y)
				if to_index >= 0 and from_index != to_index:
					component_moved.emit(from_index, to_index)

	func _canvas_to_metres(position: Vector2) -> Vector2:
		var stack_length := 0.0
		for component in stage.get("components", []):
			if str(component.get("attachment", "stack")) == "stack":
				stack_length += maxf(0.5, float(component.get("length_m", 1.0)))
		var scale := maxf(1.0, _drawing_scale)
		var width_scale := maxf(1.0, _drawing_width_scale)
		return Vector2((position.x - size.x * 0.5) / width_scale, (_drawing_stage_center_y - position.y) / scale)

	func _snap_position(position: Vector2) -> Vector2:
		var grid := 0.0
		match snap_mode:
			"0.25 m":
				grid = 0.25
			"0.5 m":
				grid = 0.5
			"1 m":
				grid = 1.0
			"2 m":
				grid = 2.0
			"5 m":
				grid = 5.0
			"Centreline":
				position.x = 0.0
			"Attachment points":
				var geometry := RocketAssembly.stage_geometry(stage)
				var nearest := position
				var nearest_distance := 1.5
				for index in geometry.component_positions:
					for point in geometry.component_positions[index]:
						var distance := position.distance_to(Vector2(point))
						if distance < nearest_distance:
							nearest_distance = distance
							nearest = Vector2(point)
				position = nearest
		if grid > 0.0:
			position.x = snappedf(position.x, grid)
			position.y = snappedf(position.y, grid)
		return position

	func _insert_index(y_position: float) -> int:
		for item in _component_rects:
			var rect: Rect2 = item.rect
			if str(item.get("attachment", "stack")) == "stack" and y_position < rect.get_center().y:
				return int(item.index)
		return (stage.get("components", []) as Array).size()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				for item in _component_rects:
					if item.get("rotation_handle", false) and item.rect.has_point(event.position):
						_rotating_index = int(item.index)
						_rotation_center = Vector2(item.center)
						var component: Dictionary = (stage.get("components", []) as Array)[_rotating_index]
						_rotation_start_degrees = float(component.get("rotation_deg", 0.0))
						_rotation_start_angle = (event.position - _rotation_center).angle()
						accept_event()
						return
					if item.rect.has_point(event.position):
						component_selected.emit(int(item.index))
						accept_event()
						return
			else:
				_rotating_index = -1
		elif event is InputEventMouseMotion and _rotating_index >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var angle_delta := rad_to_deg((event.position - _rotation_center).angle() - _rotation_start_angle)
			var rotation := wrapf(_rotation_start_degrees + angle_delta, -180.0, 180.0)
			if Input.is_key_pressed(KEY_SHIFT):
				rotation = snappedf(rotation, 15.0)
			component_rotated.emit(_rotating_index, rotation)
			accept_event()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
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
		draw_string(ThemeDB.fallback_font, Vector2(center_x + 8.0, 26.0), "CENTRELINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.58, 0.8, 0.75))
		var stages: Array = design.get("stages", [])
		if stages.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(20.0, size.y * 0.5), "DRAG PARTS FROM THE CATALOGUE TO BEGIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.72, 0.86))
			return
		var total_length := 0.0
		var max_radius := 0.5
		for stage_data in stages:
			var core_radius := 0.5
			var side_mount_radii: Dictionary = {}
			for component in stage_data.get("components", []):
				var attachment := str(component.get("attachment", "stack"))
				if attachment == "radial":
					continue
				if attachment == "side":
					var mount_index := int(component.get("mount_index", -1))
					side_mount_radii[mount_index] = float(side_mount_radii.get(mount_index, 0.0)) + float(component.get("collision_radius_m", 1.0)) * 1.75
					continue
				total_length += maxf(0.5, float(component.get("length_m", 1.0)))
				core_radius = maxf(core_radius, float(component.get("collision_radius_m", 1.0)))
			var widest_side_mount := 0.0
			for mount_radius in side_mount_radii.values():
				widest_side_mount = maxf(widest_side_mount, float(mount_radius))
			max_radius = maxf(max_radius, core_radius + widest_side_mount)
		var gap := 16.0 * zoom
		var scale := minf(zoom * 5.0, (size.y - 72.0 - gap * float(maxi(0, stages.size() - 1))) / maxf(1.0, total_length))
		var total_height := total_length * scale + gap * float(maxi(0, stages.size() - 1))
		var current_y := (size.y - total_height) * 0.5
		var width_scale := minf(15.0 * zoom, maxf(4.0, (size.x * 0.22) / max_radius))
		for stage_index in range(stages.size() - 1, -1, -1):
			var stage_data: Dictionary = stages[stage_index]
			draw_string(ThemeDB.fallback_font, Vector2(12.0, current_y + 14.0), "STAGE %02d%s" % [stage_index + 1, "  EDITING" if stage_index == selected_stage_index else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.48, 0.82, 1.0) if stage_index == selected_stage_index else Color(0.48, 0.58, 0.68))
			current_y = _draw_stage(stage_data, stage_index, center_x, current_y, scale, width_scale, max_radius, stage_index == selected_stage_index)
			if stage_index > 0:
				draw_line(Vector2(center_x - max_radius * width_scale - 24.0, current_y + gap * 0.5), Vector2(center_x + max_radius * width_scale + 24.0, current_y + gap * 0.5), Color(0.85, 0.55, 0.28, 0.75), 1.5)
				current_y += gap
		draw_string(ThemeDB.fallback_font, Vector2(12.0, 22.0), "PAYLOAD END", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0), "ENGINE END", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.9))

	func _draw_stage(stage_data: Dictionary, stage_index: int, center_x: float, start_y: float, scale: float, width_scale: float, max_radius: float, editable: bool) -> float:
		var components: Array = stage_data.get("components", [])
		var current_y := start_y
		var axial_centers: Dictionary = {}
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) != "stack":
				continue
			var height := maxf(12.0, float(component.get("length_m", 1.0)) * scale)
			var half_width := clampf(float(component.get("collision_radius_m", 1.0)) * width_scale, 9.0, size.x * 0.2)
			var rect := Rect2(Vector2(center_x - half_width, current_y), Vector2(half_width * 2.0, height))
			_draw_part(rect, component, editable and index == selected_index, 1.0 if editable else 0.34)
			axial_centers[index] = rect.get_center().y
			if editable:
				_register_component_rect(index, rect, "stack")
				draw_circle(Vector2(center_x, rect.position.y), 4.0, Color(0.35, 0.78, 1.0))
				draw_circle(Vector2(center_x, rect.end.y), 4.0, Color(0.35, 0.78, 1.0))
			current_y += height
		var core_radius := 0.5
		for component in components:
			if str(component.get("attachment", "stack")) == "stack":
				core_radius = maxf(core_radius, float(component.get("collision_radius_m", 0.5)))
		var side_mount_offsets: Dictionary = {}
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) != "side":
				continue
			var height := maxf(16.0, float(component.get("length_m", 6.0)) * scale)
			var component_radius := float(component.get("collision_radius_m", 1.0))
			var width := maxf(14.0, component_radius * width_scale * 1.7)
			var mount_index := int(component.get("mount_index", -1))
			var y := float(axial_centers.get(mount_index, start_y + (current_y - start_y) * 0.5)) - height * 0.5
			var mount_radius := float(side_mount_offsets.get(mount_index, core_radius))
			var offset := (mount_radius + component_radius * 0.9) * width_scale
			side_mount_offsets[mount_index] = offset / width_scale + component_radius * 0.85
			var side := int(component.get("side", 1))
			var sides: Array = [-1, 1] if bool(component.get("mirror", true)) else [side]
			for direction in sides:
				var rect := Rect2(Vector2(center_x + float(direction) * offset - width * 0.5, y), Vector2(width, height))
				_draw_part(rect, component, editable and index == selected_index, 1.0 if editable else 0.34)
				if editable:
					_register_component_rect(index, rect, "side")
				draw_line(Vector2(center_x + float(direction) * mount_radius * width_scale, y + height * 0.5), Vector2(center_x + float(direction) * (offset - width * 0.5), y + height * 0.5), Color(0.6, 0.72, 0.84, 1.0 if editable else 0.34), 2.0)
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) != "radial":
				continue
			var height := maxf(16.0, float(component.get("length_m", 6.0)) * scale)
			var width := maxf(14.0, float(component.get("collision_radius_m", 1.0)) * width_scale * 0.85)
			var mount_index := int(component.get("mount_index", -1))
			var y := float(axial_centers.get(mount_index, start_y + (current_y - start_y) * 0.5)) - height * 0.5
			var offset := max_radius * width_scale + width * 0.9 + 12.0
			var side := int(component.get("side", 1))
			var mirrored := bool(component.get("mirror", true))
			var sides: Array = [-1, 1] if mirrored else [side]
			for direction in sides:
				var rect := Rect2(Vector2(center_x + float(direction) * offset - width * 0.5, y), Vector2(width, height))
				_draw_part(rect, component, editable and index == selected_index, 1.0 if editable else 0.34)
				if editable:
					_register_component_rect(index, rect, "radial")
				draw_line(Vector2(center_x + float(direction) * max_radius * width_scale, y + height * 0.5), Vector2(center_x + float(direction) * (offset - width * 0.5), y + height * 0.5), Color(0.6, 0.72, 0.84, 1.0 if editable else 0.34), 2.0)
		var stage_center_y := (start_y + current_y) * 0.5
		_drawing_scale = scale
		_drawing_width_scale = width_scale
		_drawing_stage_center_y = stage_center_y
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) != "free":
				continue
			var position_data: Variant = component.get("position_m", [0.0, 0.0])
			var position_m := Vector2.ZERO
			if position_data is Array and position_data.size() >= 2:
				position_m = Vector2(float(position_data[0]), float(position_data[1]))
			var height := maxf(16.0, float(component.get("length_m", 2.0)) * scale)
			var width := maxf(14.0, float(component.get("collision_radius_m", 0.5)) * width_scale * 2.0)
			var rect := Rect2(Vector2(center_x + position_m.x * width_scale - width * 0.5, stage_center_y - position_m.y * scale - height * 0.5), Vector2(width, height))
			_draw_part(rect, component, editable and index == selected_index, 1.0 if editable else 0.34)
			if editable:
				_register_component_rect(index, rect, "free")
		return current_y

	func _register_component_rect(index: int, rect: Rect2, attachment: String) -> void:
		_component_rects.append({"index": index, "rect": rect, "attachment": attachment})
		if index == selected_index:
			var handle_center := Vector2(rect.get_center().x, rect.position.y - 20.0)
			draw_line(Vector2(rect.get_center().x, rect.position.y), handle_center, Color(0.45, 0.82, 1.0), 1.5)
			draw_circle(handle_center, 7.0, Color(0.12, 0.22, 0.32))
			draw_arc(handle_center, 6.0, 0.0, TAU, 24, Color(0.55, 0.88, 1.0), 2.0)
			_component_rects.append({"index": index, "rect": Rect2(handle_center - Vector2(9.0, 9.0), Vector2(18.0, 18.0)), "rotation_handle": true, "center": rect.get_center()})

	func _draw_part(rect: Rect2, component: Dictionary, selected: bool, opacity: float = 1.0) -> void:
		var angle := deg_to_rad(float(component.get("rotation_deg", 0.0)))
		if not is_zero_approx(angle):
			var center := rect.get_center()
			draw_set_transform(center - center.rotated(angle), angle, Vector2.ONE)
		var color := Color(0.42, 0.62, 0.76)
		var rgb: Variant = component.get("color_rgb", component.get("visual_color_rgb", []))
		if rgb is Array and rgb.size() == 3:
			color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
		var kind := str(component.get("kind", "structure"))
		var polygon := PackedVector2Array()
		match kind:
			"engine":
				polygon = PackedVector2Array([rect.position + Vector2(rect.size.x * 0.2, 0.0), rect.position + Vector2(rect.size.x * 0.8, 0.0), rect.position + Vector2(rect.size.x, rect.size.y), rect.position + Vector2(0.0, rect.size.y)])
			"decoupler", "docking_port":
				polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)])
			"rcs":
				polygon = PackedVector2Array([rect.position + Vector2(rect.size.x * 0.2, rect.size.y * 0.2), rect.position + Vector2(rect.size.x * 0.8, rect.size.y * 0.2), rect.position + Vector2(rect.size.x, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.8, rect.size.y * 0.8), rect.position + Vector2(rect.size.x * 0.2, rect.size.y * 0.8), rect.position, rect.position + Vector2(0.0, rect.size.y * 0.5)])
			"structure":
				polygon = PackedVector2Array([rect.position + Vector2(rect.size.x * 0.5, 0.0), rect.position + Vector2(rect.size.x, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.8, rect.size.y), rect.position + Vector2(rect.size.x * 0.2, rect.size.y), rect.position + Vector2(0.0, rect.size.y * 0.5)])
			_:
				polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)])
		draw_colored_polygon(polygon, Color(color.r, color.g, color.b, opacity))
		draw_rect(rect, Color(0.65, 0.84, 1.0, opacity) if selected else Color(0.12, 0.18, 0.25, opacity), false, 2.0 if selected else 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(4.0, minf(16.0, rect.size.y - 2.0)), str(component.get("label", component.get("id", "PART"))), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 10, Color(0.04, 0.06, 0.09, opacity))
		if not is_zero_approx(angle):
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var design: Dictionary = {}
var selected_stage_index := 0
var selected_component_index := -1
var mirror_enabled := true
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _canvas: AssemblyCanvas
var _parts_list: VBoxContainer
var _stage_list: VBoxContainer
var _action_stage_list: VBoxContainer
var _inspector: VBoxContainer
var _stats: Label
var _search := ""
var _category := "all"
var _part_filter: OptionButton
var _search_input: LineEdit
var _property_inputs: Dictionary = {}
var _payload_selector: OptionButton
var _payload_mass_input: SpinBox
var _payload_group_input: LineEdit
var _vehicle_name: LineEdit
var _mirror_button: CheckButton
var _snap_selector: OptionButton

func configure(source_design: Dictionary, stage_index: int = 0) -> void:
	design = source_design.duplicate(true)
	selected_stage_index = clampi(stage_index, 0, maxi(0, design.get("stages", []).size() - 1))
	var stages: Array = design.get("stages", [])
	for index in range(stages.size()):
		stages[index] = RocketAssembly.ensure_stage_components(stages[index])
	design["stages"] = stages

func load_design(source_design: Dictionary) -> void:
	design = source_design.duplicate(true)
	var stages: Array = design.get("stages", [])
	for index in range(stages.size()):
		stages[index] = RocketAssembly.ensure_stage_components(stages[index])
	design["stages"] = stages
	selected_stage_index = clampi(selected_stage_index, 0, maxi(0, stages.size() - 1))
	selected_component_index = -1
	if is_instance_valid(_vehicle_name):
		_vehicle_name.text = str(design.get("name", "Custom Vehicle"))
	if is_instance_valid(_payload_mass_input):
		_payload_mass_input.set_value_no_signal(float(design.get("payload_mass", 500.0)))
	if is_instance_valid(_payload_group_input):
		_payload_group_input.text = str(design.get("payload_subassembly_id", "main"))
	if is_instance_valid(_payload_selector):
		for index in range(_payload_selector.item_count):
			var option: Dictionary = _payload_selector.get_item_metadata(index)
			if str(option.get("id", "")) == str(design.get("payload_type", "")):
				_payload_selector.select(index)
				break
	_changed()


func _ready() -> void:
	name = "RocketBuilder"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	_refresh()

func _build_interface() -> void:

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.add_theme_constant_override("margin_left", 12)
	root.add_theme_constant_override("margin_right", 12)
	root.add_theme_constant_override("margin_top", 10)
	root.add_theme_constant_override("margin_bottom", 10)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var header := VBoxContainer.new()
	root.add_child(header)
	var header_primary := VBoxContainer.new()
	header.add_child(header_primary)
	var identity_row := HBoxContainer.new()
	header_primary.add_child(identity_row)
	var payload_row := HBoxContainer.new()
	header_primary.add_child(payload_row)
	var title_label := Label.new()
	title_label.text = "VEHICLE BUILDER"
	title_label.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title_label.custom_minimum_size.x = 190.0
	identity_row.add_child(title_label)
	var name_input := LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.placeholder_text = "Vehicle name"
	name_input.text = str(design.get("name", "Custom Vehicle"))
	name_input.text_changed.connect(func(value: String):
		design["name"] = value
		_emit_design()
	)
	identity_row.add_child(name_input)
	_vehicle_name = name_input
	var preset_button := Button.new()
	preset_button.text = "LOAD PRESET"
	preset_button.pressed.connect(_show_preset_dialog)
	identity_row.add_child(preset_button)
	var payload_label := Label.new()
	payload_label.text = "PAYLOAD"
	payload_row.add_child(payload_label)
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
	payload_row.add_child(payload_selector)
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
	payload_row.add_child(payload_mass_input)
	_payload_mass_input = payload_mass_input
	var payload_group_input := LineEdit.new()
	payload_group_input.custom_minimum_size.x = 115.0
	payload_group_input.placeholder_text = "Payload group"
	payload_group_input.text = str(design.get("payload_subassembly_id", "main"))
	payload_group_input.tooltip_text = "Assign the payload to a detachable subassembly group"
	payload_group_input.text_submitted.connect(func(value: String):
		design["payload_subassembly_id"] = value.strip_edges().to_lower().replace(" ", "_") if not value.strip_edges().is_empty() else "main"
		_emit_design()
	)
	payload_group_input.focus_exited.connect(func():
		var value := payload_group_input.text.strip_edges().to_lower().replace(" ", "_")
		if value.is_empty():
			value = "main"
		design["payload_subassembly_id"] = value
		payload_group_input.text = value
		_emit_design()
	)
	payload_row.add_child(payload_group_input)
	_payload_group_input = payload_group_input
	var header_actions := GridContainer.new()
	header_actions.columns = 3
	header.add_child(header_actions)
	var payload_edit := Button.new()
	payload_edit.text = "EDIT PAYLOAD"
	payload_edit.pressed.connect(func(): payload_edit_requested.emit())
	header_actions.add_child(payload_edit)
	var new_vehicle := Button.new()
	new_vehicle.text = "NEW"
	new_vehicle.tooltip_text = "Start a blank vehicle design"
	new_vehicle.pressed.connect(func():
		_push_undo()
		design = RocketDesign.create_blank()
		selected_stage_index = 0
		selected_component_index = -1
		_changed()
	)
	header_actions.add_child(new_vehicle)
	var mirror := CheckButton.new()
	mirror.text = "MIRROR NEW SIDE PARTS"
	mirror.button_pressed = true
	mirror.toggled.connect(func(enabled: bool):
		mirror_enabled = enabled
		if is_instance_valid(_canvas):
			_canvas.set_meta("mirror_enabled", enabled)
	)
	header_actions.add_child(mirror)
	_mirror_button = mirror
	var undo_button := Button.new()
	undo_button.text = "UNDO"
	undo_button.pressed.connect(_undo_change)
	header_actions.add_child(undo_button)
	var redo_button := Button.new()
	redo_button.text = "REDO"
	redo_button.pressed.connect(_redo_change)
	header_actions.add_child(redo_button)
	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(workspace)
	var parts_panel := PanelContainer.new()
	parts_panel.custom_minimum_size.x = 200.0
	parts_panel.name = "PARTS CATALOGUE"
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
	for category in ["all", "tank", "engine", "decoupler", "structure", "rcs", "docking_port", "power", "payload", "radial"]:
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
	center_panel.custom_minimum_size.x = 420.0
	center_panel.name = "ASSEMBLY"
	workspace.add_child(center_panel)
	var center_column := VBoxContainer.new()
	center_column.add_theme_constant_override("separation", 6)
	center_panel.add_child(center_column)
	var canvas_heading := Label.new()
	canvas_heading.text = "ASSEMBLY VIEW  •  STACK PARTS CENTRALLY OR MOUNT THEM BESIDE THE STACK"
	canvas_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	canvas_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	center_column.add_child(canvas_heading)
	_canvas = AssemblyCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.component_dropped.connect(_on_component_dropped)
	_canvas.component_moved.connect(_on_component_moved)
	_canvas.component_position_changed.connect(_on_component_position_changed)
	_canvas.component_rotated.connect(_on_component_rotated)
	_canvas.component_selected.connect(_on_component_selected)
	_snap_selector = OptionButton.new()
	for mode in ["Off", "0.25 m", "0.5 m", "1 m", "2 m", "5 m", "Centreline", "Attachment points"]:
		_snap_selector.add_item(mode)
	_snap_selector.select(2)
	_snap_selector.item_selected.connect(func(index: int):
		_canvas.snap_mode = _snap_selector.get_item_text(index)
	)
	center_column.add_child(_snap_selector)
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
	right_panel.custom_minimum_size.x = 280.0
	right_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_panel.name = "STAGING & INSPECTOR"
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
	var stage_tools := GridContainer.new()
	stage_tools.columns = 3
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
	stage_up.text = "TO PAYLOAD"
	stage_up.tooltip_text = "Move selected stage toward the payload"
	stage_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_up.pressed.connect(func(): _move_stage(1))
	move_stage_row.add_child(stage_up)
	var stage_down := Button.new()
	stage_down.text = "TO ENGINE"
	stage_down.tooltip_text = "Move selected stage toward the engine"
	stage_down.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_down.pressed.connect(func(): _move_stage(-1))
	move_stage_row.add_child(stage_down)
	var action_header := HBoxContainer.new()
	right_column.add_child(action_header)
	var action_heading := Label.new()
	action_heading.text = "ACTION STAGING"
	action_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	action_header.add_child(action_heading)
	var add_action_stage := Button.new()
	add_action_stage.text = "+"
	add_action_stage.tooltip_text = "Add an empty action stage"
	add_action_stage.pressed.connect(func():
		design["staging_stage_count"] = maxi(int(design.get("staging_stage_count", 0)), _action_stage_list.get_child_count()) + 1
		_changed()
	)
	action_header.add_child(add_action_stage)
	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size.y = 115.0
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_child(action_scroll)
	_action_stage_list = VBoxContainer.new()
	action_scroll.add_child(_action_stage_list)
	var separator := HSeparator.new()
	right_column.add_child(separator)
	var selected_heading := Label.new()
	selected_heading.text = "PART INSPECTOR"
	selected_heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	right_column.add_child(selected_heading)
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_column.add_child(inspector_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	note.text = "Stack parts centrally or mount them to either side. RCS uses the arrow keys for translation and A/D for rotation. Docking needs RCS and a port on both craft. Put ports and RCS on both sides of a stage boundary to detach a controllable module in orbit."
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(note)
	var footer_actions := HBoxContainer.new()
	footer.add_child(footer_actions)
	var save_button := Button.new()
	save_button.text = "SAVE DESIGN"
	save_button.pressed.connect(func(): save_requested.emit())
	footer_actions.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "LOAD DESIGN"
	load_button.pressed.connect(func(): load_requested.emit())
	footer_actions.add_child(load_button)
	var launch_button := Button.new()
	launch_button.text = "LAUNCH"
	launch_button.custom_minimum_size.x = 110.0
	launch_button.pressed.connect(func(): launch_requested.emit())
	footer_actions.add_child(launch_button)
	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.pressed.connect(func(): back_requested.emit())
	footer_actions.add_child(back_button)
	_canvas.set_meta("mirror_enabled", mirror_enabled)

func _refresh() -> void:
	if not is_instance_valid(_canvas):
		return
	_canvas.stage = _current_stage()
	_canvas.design = design
	_canvas.selected_stage_index = selected_stage_index
	_canvas.selected_index = selected_component_index
	_canvas.set_meta("mirror_enabled", mirror_enabled)
	_canvas.snap_mode = _snap_selector.get_item_text(_snap_selector.selected) if is_instance_valid(_snap_selector) else "0.5 m"
	_canvas.queue_redraw()
	_refresh_parts()
	_refresh_stages()
	_refresh_action_stages()
	_refresh_inspector()
	_refresh_stats()

func _current_stage() -> Dictionary:
	var stages: Array = design.get("stages", [])
	if selected_stage_index < 0 or selected_stage_index >= stages.size():
		return {}
	return stages[selected_stage_index]

func _refresh_action_stages() -> void:
	if not is_instance_valid(_action_stage_list):
		return
	for child in _action_stage_list.get_children():
		child.queue_free()
	var plan := StagingSystem.create_plan([design])
	var requested_count := maxi(plan.size(), int(design.get("staging_stage_count", 0)))
	while plan.size() < requested_count:
		plan.append({"id":"stage_%d" % plan.size(),"label":"Stage %d" % (plan.size() + 1),"actions":[]})
	for index in range(plan.size()):
		var stage: Dictionary = plan[index]
		var actions: Array = stage.get("actions", [])
		var row := VBoxContainer.new()
		var heading := Label.new()
		heading.text = "STAGE %02d  •  %d ACTIONS" % [index + 1, actions.size()]
		heading.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
		row.add_child(heading)
		for action_variant in actions:
			if not action_variant is Dictionary:
				continue
			var action: Dictionary = action_variant
			var item := Label.new()
			item.text = "%s  %s" % [str(action.get("action", "ACTION")).replace("_", " ").to_upper(), str(action.get("part_id", "PART"))]
			item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item.add_theme_color_override("font_color", Color(0.68, 0.77, 0.86))
			row.add_child(item)
		if actions.is_empty():
			var empty := Label.new()
			empty.text = "No actions assigned"
			empty.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62))
			row.add_child(empty)
		_action_stage_list.add_child(row)

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
		card.pressed.connect(func(): _add_component(str(option.get("id", "")), "free", false, 1, -1, Vector2.ZERO))
		_parts_list.add_child(card)

func _on_component_dropped(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int, position_m: Vector2) -> void:
	_add_component(component_id, attachment, mirrored, side, insert_index, position_m)

func _add_component(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int, position_m: Vector2 = Vector2.ZERO) -> void:
	var stage := _current_stage()
	if stage.is_empty():
		return
	_push_undo()
	var updated := RocketAssembly.add_component(stage, component_id, attachment, mirrored, side, insert_index)
	if updated.is_empty():
		return
	var components: Array = updated.get("components", [])
	if attachment == "free" and not components.is_empty():
		components.back()["position_m"] = [position_m.x, position_m.y]
		updated = RocketAssembly.compile_stage(updated, components)
	if attachment == "stack" and insert_index < 0 and str(components.back().get("kind", "")) != "engine":
		insert_index = components.size() - 1
		for index in range(components.size() - 1):
			var existing_component: Dictionary = components[index]
			if str(existing_component.get("attachment", "stack")) != "stack":
				insert_index = index
				break
			if str(existing_component.get("kind", "")) == "engine":
				insert_index = index
				break
	if attachment in ["radial", "side"]:
		var axial_indices: Array[int] = []
		for index in range(components.size() - 1):
			if str(components[index].get("attachment", "stack")) == "stack":
				axial_indices.append(index)
		if not axial_indices.is_empty():
			var target_index := insert_index if insert_index >= 0 else int(float(components.size()) * 0.5)
			var mount_index := axial_indices[0]
			for candidate in axial_indices:
				if absi(candidate - target_index) < absi(mount_index - target_index):
					mount_index = candidate
			components[components.size() - 1]["mount_index"] = mount_index
	if attachment == "stack" and insert_index >= 0 and insert_index < components.size() - 1:
		for index in range(components.size() - 1):
			var existing_component: Dictionary = components[index]
			if str(existing_component.get("attachment", "stack")) != "stack":
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

func _on_component_position_changed(index: int, position_m: Vector2) -> void:
	var components: Array = _current_stage().get("components", []).duplicate(true)
	if index < 0 or index >= components.size():
		return
	_push_undo()
	var component: Dictionary = components[index]
	component["position_m"] = [position_m.x, position_m.y]
	components[index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(_current_stage(), components)
	selected_component_index = index
	_changed()

func _on_component_rotated(index: int, rotation_deg: float) -> void:
	if index < 0 or index >= _current_stage().get("components", []).size():
		return
	var components: Array = _current_stage().get("components", []).duplicate(true)
	var component: Dictionary = components[index]
	component["rotation_deg"] = rotation_deg
	components[index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(_current_stage(), components)
	selected_component_index = index
	_changed(false)

func _on_component_moved(from_index: int, to_index: int) -> void:
	var components: Array = _current_stage().get("components", []).duplicate(true)
	if from_index < 0 or from_index >= components.size() or to_index < 0 or to_index > components.size():
		return
	_push_undo()
	var item: Variant = components.pop_at(from_index)
	var destination := clampi(to_index, 0, components.size())
	if item is Dictionary and str(item.get("attachment", "stack")) != "stack":
		var item_mount := int(item.get("mount_index", -1))
		if from_index < destination and item_mount > from_index and item_mount <= destination:
			item["mount_index"] = item_mount - 1
		elif destination < from_index and item_mount >= destination and item_mount < from_index:
			item["mount_index"] = item_mount + 1
	for index in range(components.size()):
		var component: Dictionary = components[index]
		if str(component.get("attachment", "stack")) == "stack":
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
	var group_label := Label.new()
	group_label.text = "Detachable subassembly group"
	_inspector.add_child(group_label)
	var group_input := LineEdit.new()
	group_input.placeholder_text = "main"
	group_input.text = RocketAssembly.component_group_id(component)
	group_input.text_submitted.connect(func(value: String): _update_component_property("subassembly_id", value.strip_edges().to_lower().replace(" ", "_")))
	group_input.focus_exited.connect(func():
		var value := group_input.text.strip_edges().to_lower().replace(" ", "_")
		if value != RocketAssembly.component_group_id(component):
			_update_component_property("subassembly_id", value)
	)
	_inspector.add_child(group_input)
	var group_note := Label.new()
	group_note.text = "Parts with the same group stay together. Put opposing docking ports on different groups to create a release action within this stage. The group is released as its own spacecraft."
	group_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector.add_child(group_note)
	var mirror_selected := CheckButton.new()
	mirror_selected.text = "MIRROR THIS PART"
	mirror_selected.disabled = not ["radial", "side"].has(str(component.get("attachment", "stack")))
	mirror_selected.button_pressed = bool(component.get("mirror", false))
	var side_selector: OptionButton
	mirror_selected.toggled.connect(func(enabled: bool):
		_update_component_property("mirror", enabled)
		if is_instance_valid(side_selector):
			side_selector.disabled = enabled
	)
	_inspector.add_child(mirror_selected)
	if str(component.get("attachment", "stack")) in ["radial", "side"]:
		var side_label := Label.new()
		side_label.text = "Mount side"
		_inspector.add_child(side_label)
		side_selector = OptionButton.new()
		side_selector.add_item("Left")
		side_selector.set_item_metadata(0, -1)
		side_selector.add_item("Right")
		side_selector.set_item_metadata(1, 1)
		side_selector.select(0 if int(component.get("side", 1)) < 0 else 1)
		side_selector.disabled = bool(component.get("mirror", false))
		side_selector.item_selected.connect(func(index: int):
			_update_component_property("side", int(side_selector.get_item_metadata(index)))
		)
		_inspector.add_child(side_selector)
		var mount_label := Label.new()
		mount_label.text = "Attachment node  •  %s" % ("automatic centre" if int(component.get("mount_index", -1)) < 0 else "stack segment %d" % (int(component.get("mount_index", -1)) + 1))
		mount_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector.add_child(mount_label)
	if str(component.get("kind", "")) == "docking_port":
		var facing_label := Label.new()
		facing_label.text = "Port direction"
		_inspector.add_child(facing_label)
		var facing_selector := OptionButton.new()
		facing_selector.add_item("Forward")
		facing_selector.set_item_metadata(0, 1)
		facing_selector.add_item("Aft")
		facing_selector.set_item_metadata(1, -1)
		facing_selector.select(0 if int(component.get("port_facing", 1)) >= 0 else 1)
		facing_selector.item_selected.connect(func(index: int):
			_update_component_property("port_facing", int(facing_selector.get_item_metadata(index)))
		)
		_inspector.add_child(facing_selector)
		var connector_note := Label.new()
		connector_note.text = "A docking port is a reusable spacecraft connection, not a stage separator. To release a built module, place a matching port on the adjoining stage, facing this one. The upper section then gets a module-release staging action."
		connector_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector.add_child(connector_note)
	var rotation_label := Label.new()
	rotation_label.text = "Part rotation (degrees)"
	_inspector.add_child(rotation_label)
	var rotation_input := SpinBox.new()
	rotation_input.min_value = -180.0
	rotation_input.max_value = 180.0
	rotation_input.step = 5.0
	rotation_input.value = wrapf(float(component.get("rotation_deg", 0.0)), -180.0, 180.0)
	rotation_input.suffix = "°"
	rotation_input.value_changed.connect(func(value: float): _update_component_property("rotation_deg", value))
	_inspector.add_child(rotation_input)
	if str(component.get("kind", "")) in ["engine", "radial"]:
		var engine_active := CheckButton.new()
		engine_active.text = "IN ACTIVE ENGINE SET"
		engine_active.button_pressed = bool(component.get("engine_enabled", true))
		engine_active.toggled.connect(func(enabled: bool): _update_component_property("engine_enabled", enabled))
		_inspector.add_child(engine_active)
	if str(component.get("kind", "")) == "tank":
		var fuel_supply := CheckButton.new()
		fuel_supply.text = "SUPPLY FUEL TO CONNECTED ENGINES"
		fuel_supply.button_pressed = bool(component.get("fuel_supply_enabled", true))
		fuel_supply.toggled.connect(func(enabled: bool): _update_component_property("fuel_supply_enabled", enabled))
		_inspector.add_child(fuel_supply)
	var staging_label := Label.new()
	staging_label.text = "Stage assignment"
	_inspector.add_child(staging_label)
	var staging_assignment := SpinBox.new()
	staging_assignment.min_value = 1
	staging_assignment.max_value = 16
	staging_assignment.step = 1
	staging_assignment.value = int(component.get("staging_stage", selected_stage_index)) + 1
	staging_assignment.value_changed.connect(func(value: float): _update_component_property("staging_stage", int(value) - 1))
	_inspector.add_child(staging_assignment)
	var action_label := Label.new()
	action_label.text = "Staging action"
	_inspector.add_child(action_label)
	var action_selector := OptionButton.new()
	var action_options: Array = []
	match str(component.get("kind", "")):
		"engine", "radial":
			action_options = [{"id":"activate_engine","label":"Activate engine"},{"id":"deactivate_engine","label":"Shut down engine"}]
		"tank":
			action_options = [{"id":"enable_fuel_supply","label":"Enable fuel supply"},{"id":"disable_fuel_supply","label":"Disable fuel supply"}]
		"rcs":
			action_options = [{"id":"activate_rcs","label":"Activate RCS"},{"id":"deactivate_rcs","label":"Deactivate RCS"}]
		"decoupler":
			action_options = [{"id":"separate","label":"Separate stage"},{"id":"attach","label":"Attach stage"}]
		"docking_port":
			action_options = [{"id":"undock_module","label":"Release docked module"}]
		_:
			if bool(component.get("deployable", false)):
				action_options = [{"id":"deploy","label":"Deploy"},{"id":"retract","label":"Retract"}]
			else:
				action_options = [{"id":"activate","label":"Activate"},{"id":"deactivate","label":"Deactivate"}]
	var default_action := "undock_module" if str(component.get("kind", "")) == "docking_port" else str(component.get("staging_action", action_options[0].id if not action_options.is_empty() else "activate"))
	for option in action_options:
		action_selector.add_item(str(option.label))
		action_selector.set_item_metadata(action_selector.item_count - 1, str(option.id))
		if str(option.id) == default_action:
			action_selector.select(action_selector.item_count - 1)
	action_selector.item_selected.connect(func(index: int): _update_component_property("staging_action", str(action_selector.get_item_metadata(index))))
	_inspector.add_child(action_selector)
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
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = str(field.label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var duplicate := Button.new()
	duplicate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate.text = "DUPLICATE"
	duplicate.pressed.connect(_duplicate_selected_component)
	actions.add_child(duplicate)
	var remove := Button.new()
	remove.text = "REMOVE PART"
	remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		if str(component.get("attachment", "stack")) != "stack" and int(component.get("mount_index", -1)) >= destination:
			component["mount_index"] = int(component.get("mount_index", -1)) + 1
			components[index] = component
	if str(duplicate.get("attachment", "stack")) != "stack" and int(duplicate.get("mount_index", -1)) >= destination:
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
	var removed_component: Dictionary = components[selected_component_index]
	components.remove_at(selected_component_index)
	if str(removed_component.get("attachment", "stack")) == "stack":
		var axial_indices: Array[int] = []
		for index in range(components.size()):
			if str(components[index].get("attachment", "stack")) == "stack":
				axial_indices.append(index)
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) == "stack":
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
	var errors := RocketDesign.validation_errors(design)
	var status := "DESIGN VALID" if errors.is_empty() else "CHECK: %s" % str(errors[0])
	_stats.text = "TOTAL MASS  %.1f t     STAGE TWR  %.2f     IDEAL ΔV  %.2f km/s     STAGES  %d\n%s" % [mass / 1000.0, twr, RocketDesign.total_delta_v(design) / 1000.0, design.get("stages", []).size(), status]
	_stats.add_theme_color_override("font_color", Color(0.95, 0.48, 0.38) if not errors.is_empty() else Color(0.76, 0.85, 0.94))

func performance_summary_text() -> String:
	return _stats.text if is_instance_valid(_stats) else ""

func _changed(refresh_inspector: bool = true) -> void:
	if refresh_inspector:
		_refresh()
	else:
		_canvas.stage = _current_stage()
		_canvas.design = design
		_canvas.selected_stage_index = selected_stage_index
		_canvas.queue_redraw()
		_refresh_stats()
	_emit_design()

func _emit_design() -> void:
	design_changed.emit(design.duplicate(true))

func _show_preset_dialog() -> void:
	var presets := RocketDesign.preset_options()
	if presets.is_empty():
		return
	var window := Window.new()
	window.title = "LOAD VEHICLE PRESET"
	window.size = Vector2i(540, 300)
	window.min_size = Vector2i(440, 260)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	window.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var intro := Label.new()
	intro.text = "Presets are optional starting points. Every part can be changed after loading."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in presets:
		selector.add_item(str(preset.get("label", preset.get("id", "Preset"))))
		selector.set_item_metadata(selector.item_count - 1, str(preset.get("id", "")))
	content.add_child(selector)
	var description := Label.new()
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	var update_description := func(index: int) -> void:
		description.text = RocketDesign.preset_description(str(selector.get_item_metadata(index)))
	selector.item_selected.connect(update_description)
	selector.select(0)
	update_description.call(0)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(buttons)
	var cancel_button := Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.pressed.connect(window.queue_free)
	buttons.add_child(cancel_button)
	var load_button := Button.new()
	load_button.text = "LOAD PRESET"
	load_button.pressed.connect(func():
		var preset_design := RocketDesign.create_preset(str(selector.get_selected_metadata()))
		if preset_design.is_empty():
			return
		_push_undo()
		design = preset_design
		var stages: Array = design.get("stages", [])
		for index in range(stages.size()):
			stages[index] = RocketAssembly.ensure_stage_components(stages[index])
		design["stages"] = stages
		_vehicle_name.text = str(design.get("name", "Custom Vehicle"))
		_payload_mass_input.set_value_no_signal(float(design.get("payload_mass", 500.0)))
		for index in range(_payload_selector.item_count):
			var payload_option: Dictionary = _payload_selector.get_item_metadata(index)
			if str(payload_option.get("id", "")) == str(design.get("payload_type", "")):
				_payload_selector.select(index)
				break
		selected_stage_index = 0
		selected_component_index = -1
		_changed()
		window.queue_free()
	)
	buttons.add_child(load_button)
	window.popup_centered()

func _finish() -> void:
	_emit_design()
	back_requested.emit()
	queue_free()
