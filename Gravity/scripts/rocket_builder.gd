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
		if is_inside_tree():
			set_drag_preview(preview)
		else:
			preview.free()
		return {"source": "catalog", "id": str(component.get("id", "")), "kind": str(component.get("kind", "")), "component": component.duplicate(true)}

class AssemblyCanvas extends Control:
	signal component_dropped(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int, position_m: Vector2, parent_uid: String, parent_node_id: String)
	signal component_moved(from_index: int, to_index: int)
	signal component_position_changed(index: int, position_m: Vector2)
	signal component_repositioned(index: int, attachment: String, side: int, insert_index: int, parent_uid: String, parent_node_id: String, position_m: Vector2)
	signal component_rotation_started(index: int)
	signal component_rotated(index: int, rotation_deg: float)
	signal component_selected(index: int)
	signal component_group_position_changed(indices: Array, positions: Array)
	signal component_stage_selected(stage_index: int, component_index: int)
	signal component_group_rotation_started(indices: Array)
	signal component_group_rotated(indices: Array, positions: Array, rotations: Array)

	var stage: Dictionary = {}
	var design: Dictionary = {}
	var selected_stage_index := 0
	var selected_index := -1
	var selected_indices: Array[int] = []
	var zoom := 1.0
	var view_offset := Vector2.ZERO
	var _panning := false
	var _pan_origin := Vector2.ZERO
	var _pan_start_offset := Vector2.ZERO
	var snap_mode := "Off"
	var rotation_snap_degrees := 15.0
	var _component_rects: Array[Dictionary] = []
	var _rotating_index := -1
	var _rotation_center := Vector2.ZERO
	var _rotation_start_angle := 0.0
	var _rotation_start_degrees := 0.0
	var _group_rotation_indices: Array[int] = []
	var _group_rotation_centers: Array[Vector2] = []
	var _group_rotation_degrees: Array[float] = []
	var _group_rotation_stage_center_y := 0.0
	var _drawing_scale := 1.0
	var _drawing_width_scale := 1.0
	var _drawing_stage_center_y := 0.0
	var _drag_data: Dictionary = {}
	var _drag_position := Vector2.ZERO
	var _drag_active := false
	var _snap_target: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(420.0, 500.0)
		queue_redraw()

	func _get_drag_data(at_position: Vector2) -> Variant:
		for item in _component_rects:
			if item.get("rotation_handle", false) and _rect_hit(item, at_position):
				return null
		for item in _component_rects:
			if not item.get("rotation_handle", false) and _rect_hit(item, at_position):
				var item_stage := int(item.get("stage_index", selected_stage_index))
				if item_stage != selected_stage_index:
					selected_stage_index = item_stage
					stage = (design.get("stages", []) as Array)[selected_stage_index]
					selected_indices.clear()
					selected_index = -1
					component_stage_selected.emit(selected_stage_index, int(item.index))
				var index := int(item.index)
				if not selected_indices.has(index):
					selected_indices = [index]
				selected_index = index
				component_selected.emit(selected_index)
				var components: Array = stage.get("components", [])
				var dragged_indices: Array[int] = []
				var start_rects: Array[Dictionary] = []
				for selected in selected_indices:
					for selected_item in _component_rects:
						if int(selected_item.get("stage_index", selected_stage_index)) == selected_stage_index and int(selected_item.get("index", -1)) == selected and not selected_item.get("rotation_handle", false):
							dragged_indices.append(selected)
							start_rects.append({"index": selected, "rect": selected_item.rect, "component": components[selected].duplicate(true)})
							break
				var preview := Label.new()
				preview.text = "%d parts" % dragged_indices.size() if dragged_indices.size() > 1 else str(components[index].get("label", "Part"))
				if is_inside_tree():
					set_drag_preview(preview)
				else:
					preview.free()
				return {"source": "placed", "index": index, "indices": dragged_indices, "start_rects": start_rects, "start_position": at_position, "component": components[index].duplicate(true)}
		return null

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		if not data is Dictionary or str(data.get("source", "")) not in ["catalog", "placed"]:
			return false
		_drag_data = data.duplicate(true)
		_drag_position = at_position
		_drag_active = true
		_snap_target = _find_attachment_target(at_position) if snap_mode == "Attach" else {}
		queue_redraw()
		return true

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			_clear_drag_preview()

	func _clear_drag_preview() -> void:
		_drag_data.clear()
		_snap_target.clear()
		_drag_active = false
		queue_redraw()

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		_drag_data = data.duplicate(true)
		var target := _find_attachment_target(at_position) if snap_mode == "Attach" else {}
		var preview_position := _preview_position_for_target(at_position, target, data)
		var position_m := _canvas_to_metres(preview_position)
		_clear_drag_preview()
		if str(data.get("source", "")) == "catalog":
			var attachment := "free"
			var mirrored := false
			var side := 1
			var insert_index := -1
			if not target.is_empty():
				attachment = str(target.attachment)
				mirrored = bool(get_meta("mirror_enabled", false)) if attachment == "side" else false
				side = int(target.get("side", 1))
				insert_index = int(target.get("insert_index", -1))
			var parent_uid := ""
			var parent_node_id := ""
			if not target.is_empty():
				var target_stage_index := int(target.get("target_stage_index", selected_stage_index))
				var target_components: Array = (design.get("stages", []) as Array)[target_stage_index].get("components", [])
				var target_index := int(target.get("component_index", -1))
				if target_index >= 0 and target_index < target_components.size():
					parent_uid = str(target_components[target_index].get("part_uid", ""))
					parent_node_id = str(target.get("node_id", ""))
			component_dropped.emit(str(data.get("id", "")), attachment, mirrored, side, insert_index, position_m, parent_uid, parent_node_id)
		else:
			var from_index := int(data.get("index", -1))
			var components: Array = stage.get("components", [])
			if from_index < 0 or from_index >= components.size():
				return
			var dragged_indices: Array = data.get("indices", [from_index])
			if dragged_indices.size() > 1:
				var delta := at_position - Vector2(data.get("start_position", at_position))
				var positions: Array[Vector2] = []
				for start_rect in data.get("start_rects", []):
					positions.append(_canvas_to_metres(start_rect.rect.get_center() + delta))
				component_group_position_changed.emit(dragged_indices, positions)
			elif not target.is_empty():
				var target_uid := ""
				var target_index := int(target.get("component_index", -1))
				var target_stage_index := int(target.get("target_stage_index", selected_stage_index))
				var target_components: Array = (design.get("stages", []) as Array)[target_stage_index].get("components", [])
				if target_index >= 0 and target_index < target_components.size():
					target_uid = str(target_components[target_index].get("part_uid", ""))
				component_repositioned.emit(from_index, str(target.attachment), int(target.get("side", 1)), int(target.get("insert_index", -1)), target_uid, str(target.get("node_id", "")), position_m)
			else:
				component_position_changed.emit(from_index, position_m)

	func _preview_position_for_target(at_position: Vector2, target: Dictionary, data: Variant) -> Vector2:
		if target.is_empty():
			return at_position
		var component: Dictionary = data.get("component", {})
		var length := maxf(16.0, float(component.get("length_m", 2.0)) * _drawing_scale)
		var width := maxf(14.0, float(component.get("collision_radius_m", 0.5)) * _drawing_width_scale * 2.0)
		var target_position: Vector2 = target.position
		var source_rect := Rect2(Vector2.ZERO, Vector2(width, length))
		for source_node in _component_attachment_nodes(source_rect, component):
			if str(source_node.get("type", "structural")) != str(target.get("node_type", "structural")):
				continue
			if Vector2(source_node.direction).dot(Vector2(target.get("direction", Vector2.UP))) > -0.95:
				continue
			return target_position - (Vector2(source_node.position) - source_rect.get_center())
		match str(target.get("edge", "")):
			"top":
				return target_position + Vector2(0.0, -length * 0.5)
			"bottom":
				return target_position + Vector2(0.0, length * 0.5)
			"left":
				return target_position + Vector2(-width * 0.5, 0.0)
			"right":
				return target_position + Vector2(width * 0.5, 0.0)
		match str(target.get("attachment", "")):
			"stack":
				return target_position + Vector2(0.0, -length * 0.5 if int(target.get("insert_index", 0)) <= int(target.get("component_index", 0)) else length * 0.5)
			"side":
				return target_position + Vector2(float(int(target.get("side", 1))) * width * 0.5, 0.0)
		return at_position

	func _has_matching_attachment_node(component: Dictionary, target_direction: Vector2, target_type: String) -> bool:
		var probe_rect := Rect2(Vector2.ZERO, Vector2(1.0, 1.0))
		for node in _component_attachment_nodes(probe_rect, component):
			if str(node.get("type", "structural")) == target_type and Vector2(node.direction).dot(target_direction) <= -0.95:
				return true
		return false

	func _find_attachment_target(position: Vector2) -> Dictionary:
		var best_distance := 36.0
		var best_target: Dictionary = {}
		for item in _component_rects:
			if item.get("rotation_handle", false):
				continue
			var index := int(item.index)
			var target_stage_index := int(item.get("stage_index", selected_stage_index))
			var is_separator := str(item.get("component", {}).get("preset_hardware_role", "")) == "separator"
			var is_adjacent_separator := is_separator and target_stage_index == selected_stage_index - 1
			if target_stage_index != selected_stage_index and not is_adjacent_separator:
				continue
			if is_adjacent_separator and int(item.get("stage_index", -1)) + 1 != selected_stage_index:
				continue
			if str(_drag_data.get("source", "")) == "placed" and index in _drag_data.get("indices", [_drag_data.get("index", -1)]) and target_stage_index == selected_stage_index:
				continue
			var component: Dictionary = item.get("component", {})
			for node in _component_attachment_nodes(item.rect, component):
				if is_separator:
					var node_direction: Vector2 = node.direction
					if is_adjacent_separator and node_direction.y >= -0.5:
						continue
					if not is_adjacent_separator and node_direction.y <= 0.5:
						continue
				var dragged_component: Dictionary = _drag_data.get("component", {})
				if not dragged_component.is_empty() and not _has_matching_attachment_node(dragged_component, Vector2(node.direction), str(node.type)):
					continue
				var distance := position.distance_to(Vector2(node.position))
				if distance >= best_distance:
					continue
				var direction: Vector2 = node.direction
				var edge := "top" if direction.y < -0.5 else "bottom" if direction.y > 0.5 else "left" if direction.x < 0.0 else "right"
				var attachment := "stack" if absf(direction.y) >= absf(direction.x) else "side"
				if str(item.get("attachment", "stack")) == "free":
					attachment = "free"
				best_distance = distance
				var insert_index := index if direction.y < 0.0 else index + 1
				if is_adjacent_separator:
					insert_index = 0
				best_target = {"position": node.position, "direction": direction, "node_id": node.id, "node_type": node.type, "attachment": attachment, "edge": edge, "side": -1 if direction.x < 0.0 else 1, "insert_index": insert_index, "component_index": index, "target_stage_index": target_stage_index, "separator_boundary": is_separator}
		if best_target.get("attachment", "") == "stack":
			best_target["insert_index"] = clampi(int(best_target.insert_index), 0, (stage.get("components", []) as Array).size())
		return best_target
	func _canvas_to_metres(position: Vector2) -> Vector2:
		var scale := maxf(1.0, _drawing_scale)
		var width_scale := maxf(1.0, _drawing_width_scale)
		return Vector2((position.x - size.x * 0.5 - view_offset.x) / width_scale, (_drawing_stage_center_y - position.y) / scale)

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
		if grid > 0.0:
			position.x = snappedf(position.x, grid)
			position.y = snappedf(position.y, grid)
		return position

	func _insert_index(y_position: float) -> int:
		for item in _component_rects:
			var rect: Rect2 = item.rect
			if int(item.get("stage_index", selected_stage_index)) == selected_stage_index and str(item.get("attachment", "stack")) == "stack" and y_position < rect.get_center().y:
				return int(item.index)
		return (stage.get("components", []) as Array).size()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_panning = event.pressed
			if _panning:
				_pan_origin = event.position
				_pan_start_offset = view_offset
			accept_event()
			return
		if event is InputEventMouseMotion and _panning:
			view_offset = _pan_start_offset + event.position - _pan_origin
			queue_redraw()
			accept_event()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				for item in _component_rects:
					if item.get("rotation_handle", false) and _rect_hit(item, event.position):
						var item_stage := int(item.get("stage_index", selected_stage_index))
						if item_stage != selected_stage_index:
							selected_stage_index = item_stage
							stage = (design.get("stages", []) as Array)[selected_stage_index]
							component_stage_selected.emit(selected_stage_index, int(item.index))
						_rotating_index = int(item.index)
						_rotation_center = Vector2(item.center)
						_rotation_start_angle = (event.position - _rotation_center).angle()
						_group_rotation_indices.clear()
						_group_rotation_centers.clear()
						_group_rotation_degrees.clear()
						if selected_indices.size() > 1 and selected_indices.has(_rotating_index):
							var group_center := Vector2.ZERO
							var group_items: Array[Dictionary] = []
							for selected in selected_indices:
								for part_item in _component_rects:
									if not part_item.get("rotation_handle", false) and int(part_item.get("stage_index", selected_stage_index)) == selected_stage_index and int(part_item.index) == selected:
										group_items.append(part_item)
										group_center += part_item.rect.get_center()
										break
							if group_items.size() > 1:
								_rotation_start_degrees = 0.0
								group_center /= float(group_items.size())
								_rotation_center = group_center
								_rotation_start_angle = (event.position - _rotation_center).angle()
								var group_components: Array = stage.get("components", [])
								for part_item in group_items:
									var part_index := int(part_item.index)
									_group_rotation_indices.append(part_index)
									_group_rotation_centers.append(part_item.rect.get_center())
									_group_rotation_degrees.append(float(group_components[part_index].get("rotation_deg", 0.0)))
								_group_rotation_stage_center_y = float(group_items[0].get("stage_center_y", _drawing_stage_center_y))
								component_group_rotation_started.emit(_group_rotation_indices)
						else:
							var selected_component: Dictionary = (stage.get("components", []) as Array)[_rotating_index]
							_rotation_start_degrees = float(selected_component.get("rotation_deg", 0.0))
							component_rotation_started.emit(_rotating_index)
						accept_event()
						return
					if not item.get("rotation_handle", false) and _rect_hit(item, event.position):
						var item_stage := int(item.get("stage_index", selected_stage_index))
						if item_stage != selected_stage_index:
							selected_stage_index = item_stage
							stage = (design.get("stages", []) as Array)[selected_stage_index]
							selected_indices.clear()
							selected_index = -1
							component_stage_selected.emit(selected_stage_index, int(item.index))
						var index := int(item.index)
						if event.ctrl_pressed or event.shift_pressed:
							if selected_indices.has(index):
								selected_indices.erase(index)
							else:
								selected_indices.append(index)
							selected_index = selected_indices.back() if not selected_indices.is_empty() else -1
						else:
							if not selected_indices.has(index) or selected_indices.size() <= 1:
								selected_indices = [index]
							selected_index = index
						component_selected.emit(selected_index)
						queue_redraw()
						if event.double_click:
							_frame_selected()
						accept_event()
						return
			else:
				_rotating_index = -1
		elif event is InputEventMouseMotion and _rotating_index >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var angle_delta := rad_to_deg((event.position - _rotation_center).angle() - _rotation_start_angle)
			var rotation := wrapf(_rotation_start_degrees + angle_delta, -180.0, 180.0)
			if rotation_snap_degrees > 0.0 and not Input.is_key_pressed(KEY_CTRL):
				rotation = snappedf(rotation, rotation_snap_degrees)
			elif Input.is_key_pressed(KEY_SHIFT):
				rotation = snappedf(rotation, 15.0)
			if _group_rotation_indices.size() > 1:
				var group_positions: Array[Vector2] = []
				var group_rotations: Array[float] = []
				for group_index in range(_group_rotation_indices.size()):
					var rotated_center := _rotate_point(_group_rotation_centers[group_index], _rotation_center, deg_to_rad(rotation - _rotation_start_degrees))
					var scale_value := maxf(1.0, _drawing_scale)
					var width_value := maxf(1.0, _drawing_width_scale)
					group_positions.append(Vector2((rotated_center.x - size.x * 0.5 - view_offset.x) / width_value, (_group_rotation_stage_center_y - rotated_center.y) / scale_value))
					group_rotations.append(wrapf(_group_rotation_degrees[group_index] + rotation - _rotation_start_degrees, -180.0, 180.0))
				component_group_rotated.emit(_group_rotation_indices, group_positions, group_rotations)
			else:
				component_rotated.emit(_rotating_index, rotation)
			accept_event()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(1.15, event.position)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / 1.15, event.position)
				accept_event()

	func _zoom_at(factor: float, anchor: Vector2) -> void:
		var previous_zoom := zoom
		zoom = clampf(zoom * factor, 0.1, 12.0)
		var ratio := zoom / previous_zoom
		view_offset = anchor - size * 0.5 - (anchor - size * 0.5 - view_offset) * ratio
		queue_redraw()

	func _frame_selected() -> void:
		for item in _component_rects:
			if int(item.get("index", -1)) != selected_index or item.get("rotation_handle", false):
				continue
			var rect: Rect2 = item.rect
			var factor := minf(size.x * 0.38 / maxf(1.0, rect.size.x), size.y * 0.38 / maxf(1.0, rect.size.y))
			var previous_zoom := zoom
			zoom = clampf(zoom * clampf(factor, 0.5, 8.0), 0.1, 12.0)
			var ratio := zoom / previous_zoom
			view_offset = size * 0.5 - (rect.get_center() - view_offset) * ratio
			queue_redraw()
			return

	func _draw() -> void:
		_component_rects.clear()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.028, 0.05))
		var grid_step := 24.0 * zoom
		var grid_x := fposmod(size.x * 0.5 + view_offset.x, grid_step)
		var grid_y := fposmod(size.y * 0.5 + view_offset.y, grid_step)
		for x in range(int(size.x / grid_step) + 2):
			var px := grid_x + float(x) * grid_step
			draw_line(Vector2(px, 0.0), Vector2(px, size.y), Color(0.12, 0.17, 0.24, 0.5), 1.0)
		for y in range(int(size.y / grid_step) + 2):
			var py := grid_y + float(y) * grid_step
			draw_line(Vector2(0.0, py), Vector2(size.x, py), Color(0.12, 0.17, 0.24, 0.5), 1.0)
		var center_x := size.x * 0.5 + view_offset.x
		draw_line(Vector2(center_x, 12.0 + view_offset.y), Vector2(center_x, size.y - 12.0 + view_offset.y), Color(0.3, 0.58, 0.8, 0.55), 1.2)
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
			var stack_length := 0.0
			var stage_extent := 0.0
			var free_radius := 0.0
			for component in stage_data.get("components", []):
				var attachment := str(component.get("attachment", "stack"))
				if attachment == "radial":
					continue
				if attachment == "side":
					var mount_index := int(component.get("mount_index", -1))
					side_mount_radii[mount_index] = float(side_mount_radii.get(mount_index, 0.0)) + float(component.get("collision_radius_m", 1.0)) * 1.75
					continue
				if attachment == "free":
					var position_data: Variant = component.get("position_m", [0.0, 0.0])
					if position_data is Array and position_data.size() >= 2:
						stage_extent = maxf(stage_extent, absf(float(position_data[1])) * 2.0 + float(component.get("length_m", 1.0)))
						free_radius = maxf(free_radius, absf(float(position_data[0])) + float(component.get("collision_radius_m", 0.5)))
				else:
					stack_length += maxf(0.5, float(component.get("length_m", 1.0)))
					core_radius = maxf(core_radius, float(component.get("collision_radius_m", 1.0)))
			total_length += maxf(stack_length, stage_extent)
			var widest_side_mount := 0.0
			for mount_radius in side_mount_radii.values():
				widest_side_mount = maxf(widest_side_mount, float(mount_radius))
			max_radius = maxf(max_radius, maxf(core_radius + widest_side_mount, free_radius))
		var gap := 0.0
		var scale := minf(5.0, (size.y - 72.0 - gap * float(maxi(0, stages.size() - 1))) / maxf(1.0, total_length)) * zoom
		var total_height := total_length * scale + gap * float(maxi(0, stages.size() - 1))
		var current_y := (size.y - total_height) * 0.5 + view_offset.y
		var width_scale := minf(15.0, maxf(4.0, (size.x * 0.22) / max_radius)) * zoom
		for stage_index in range(stages.size() - 1, -1, -1):
			var stage_data: Dictionary = stages[stage_index]
			draw_string(ThemeDB.fallback_font, Vector2(12.0, current_y + 14.0), "STAGE %02d%s" % [stage_index + 1, "  EDITING" if stage_index == selected_stage_index else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.48, 0.82, 1.0) if stage_index == selected_stage_index else Color(0.48, 0.58, 0.68))
			current_y = _draw_stage(stage_data, stage_index, center_x, current_y, scale, width_scale, max_radius, true)
			if stage_index > 0:
				current_y += gap
		_draw_drag_preview()
		draw_string(ThemeDB.fallback_font, Vector2(12.0, 22.0), "PAYLOAD END", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.9))
		draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0), "ENGINE END", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.72, 0.9))

	func _draw_stage(stage_data: Dictionary, stage_index: int, center_x: float, start_y: float, scale: float, width_scale: float, max_radius: float, editable: bool) -> float:
		var components: Array = stage_data.get("components", [])
		var stack_length := 0.0
		var stage_extent := 0.0
		for component in components:
			var attachment := str(component.get("attachment", "stack"))
			if attachment == "stack":
				stack_length += maxf(0.5, float(component.get("length_m", 1.0)))
			elif attachment == "free":
				var position_data: Variant = component.get("position_m", [0.0, 0.0])
				if position_data is Array and position_data.size() >= 2:
					stage_extent = maxf(stage_extent, absf(float(position_data[1])) * 2.0 + float(component.get("length_m", 1.0)))
		stage_extent = maxf(stage_extent, stack_length)
		var current_y := start_y + (stage_extent - stack_length) * scale * 0.5
		var axial_centers: Dictionary = {}
		for index in range(components.size()):
			var component: Dictionary = components[index]
			if str(component.get("attachment", "stack")) != "stack":
				continue
			var height := maxf(12.0, float(component.get("length_m", 1.0)) * scale)
			var half_width := clampf(float(component.get("collision_radius_m", 1.0)) * width_scale, 9.0, size.x * 0.2)
			var rect := Rect2(Vector2(center_x - half_width, current_y), Vector2(half_width * 2.0, height))
			_draw_part(rect, component, stage_index == selected_stage_index and selected_indices.has(index), 1.0 if stage_index == selected_stage_index else 0.72)
			axial_centers[index] = rect.get_center().y
			if editable:
				_register_component_rect(index, rect, "stack", component, stage_index, start_y + stage_extent * scale * 0.5)
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
				_draw_part(rect, component, editable and selected_indices.has(index), 1.0 if editable else 0.34)
				if editable:
					_register_component_rect(index, rect, "side", component, stage_index, start_y + stage_extent * scale * 0.5)
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
				_draw_part(rect, component, editable and selected_indices.has(index), 1.0 if editable else 0.34)
				if editable:
					_register_component_rect(index, rect, "radial", component, stage_index, start_y + stage_extent * scale * 0.5)
				draw_line(Vector2(center_x + float(direction) * max_radius * width_scale, y + height * 0.5), Vector2(center_x + float(direction) * (offset - width * 0.5), y + height * 0.5), Color(0.6, 0.72, 0.84, 1.0 if editable else 0.34), 2.0)
		var stage_center_y := start_y + stage_extent * scale * 0.5
		if editable and stage_index == selected_stage_index:
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
			_draw_part(rect, component, editable and selected_indices.has(index), 1.0 if editable else 0.34)
			if editable:
				_register_component_rect(index, rect, "free", component, stage_index, stage_center_y)
		return start_y + stage_extent * scale

	func _draw_drag_preview() -> void:
		if not _drag_active:
			return
		var component: Dictionary = _drag_data.get("component", {})
		if component.is_empty():
			return
		if str(_drag_data.get("source", "")) == "placed" and _drag_data.get("indices", []).size() > 1:
			var delta := _drag_position - Vector2(_drag_data.get("start_position", _drag_position))
			for start_rect in _drag_data.get("start_rects", []):
				var preview_rect: Rect2 = start_rect.rect
				preview_rect.position += delta
				_draw_part(preview_rect, start_rect.component, true, 0.72)
				draw_rect(preview_rect, Color(0.45, 0.86, 1.0, 0.9), false, 1.5)
			return
		var length := maxf(16.0, float(component.get("length_m", 2.0)) * _drawing_scale)
		var width := maxf(14.0, float(component.get("collision_radius_m", 0.5)) * _drawing_width_scale * 2.0)
		var target := _find_attachment_target(_drag_position) if snap_mode == "Attach" else {}
		var preview_position := _preview_position_for_target(_drag_position, target, _drag_data)
		if not target.is_empty():
			var target_position: Vector2 = target.position
			draw_circle(target_position, 13.0, Color(0.12, 0.62, 0.9, 0.22))
			draw_arc(target_position, 12.0, 0.0, TAU, 32, Color(0.35, 0.88, 1.0, 0.95), 2.5)
			draw_line(preview_position, target_position, Color(0.35, 0.88, 1.0, 0.7), 1.5)
		var preview_rect := Rect2(preview_position - Vector2(width, length) * 0.5, Vector2(width, length))
		_draw_part(preview_rect, component, false, 0.62)
		draw_rect(preview_rect, Color(0.45, 0.86, 1.0, 0.9), false, 1.5)
		if snap_mode == "Attach" and target.is_empty():
			draw_string(ThemeDB.fallback_font, _drag_position + Vector2(14.0, -14.0), "No attachment nearby", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.72, 0.4))

	func _register_component_rect(index: int, rect: Rect2, attachment: String, component: Dictionary, stage_index: int, stage_center_y: float) -> void:
		var center := rect.get_center()
		var rotation := deg_to_rad(float(component.get("rotation_deg", 0.0)))
		_component_rects.append({"index": index, "rect": rect, "attachment": attachment, "center": center, "rotation": rotation, "component": component.duplicate(true), "stage_index": stage_index, "stage_center_y": stage_center_y})
		if snap_mode == "Attach":
			for node in _component_attachment_nodes(rect, component):
				draw_circle(Vector2(node.position), 4.5, Color(0.35, 0.82, 1.0, 0.9))
		if stage_index == selected_stage_index and index == selected_index:
			var handle_center := _rotate_point(Vector2(rect.get_center().x, rect.position.y - 20.0), center, rotation)
			draw_line(_rotate_point(Vector2(rect.get_center().x, rect.position.y), center, rotation), handle_center, Color(0.45, 0.82, 1.0), 1.5)
			draw_circle(handle_center, 7.0, Color(0.12, 0.22, 0.32))
			draw_arc(handle_center, 6.0, 0.0, TAU, 24, Color(0.55, 0.88, 1.0), 2.0)
			_component_rects.append({"index": index, "rect": Rect2(handle_center - Vector2(9.0, 9.0), Vector2(18.0, 18.0)), "rotation_handle": true, "center": center, "stage_index": stage_index})

	func _rotate_point(point: Vector2, center: Vector2, angle: float) -> Vector2:
		return center + (point - center).rotated(angle)

	func _component_attachment_nodes(rect: Rect2, component: Dictionary) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		var definitions: Array = component.get("attachment_nodes", [])
		if definitions.is_empty():
			definitions = [
				{"id": "top", "position": [0.0, -0.5], "direction": [0.0, -1.0]},
				{"id": "bottom", "position": [0.0, 0.5], "direction": [0.0, 1.0]},
				{"id": "left", "position": [-0.5, 0.0], "direction": [-1.0, 0.0]},
				{"id": "right", "position": [0.5, 0.0], "direction": [1.0, 0.0]}
			]
		var center := rect.get_center()
		var angle := deg_to_rad(float(component.get("rotation_deg", 0.0)))
		for definition in definitions:
			if not definition is Dictionary:
				continue
			var local_position: Variant = definition.get("position", [0.0, 0.0])
			var local_direction: Variant = definition.get("direction", [0.0, -1.0])
			if not local_position is Array or local_position.size() < 2 or not local_direction is Array or local_direction.size() < 2:
				continue
			var point := Vector2(rect.size.x * float(local_position[0]), rect.size.y * float(local_position[1]))
			var direction := Vector2(float(local_direction[0]), float(local_direction[1])).rotated(angle).normalized()
			result.append({"id": str(definition.get("id", "node")), "position": _rotate_point(center + point, center, angle), "direction": direction, "type": str(definition.get("type", "structural"))})
		return result

	func _rcs_mount_direction(rect: Rect2, component: Dictionary, centerline: float) -> Vector2:
		if str(component.get("attachment", "stack")) in ["side", "radial"]:
			return Vector2.LEFT if rect.get_center().x > centerline else Vector2.RIGHT
		return Vector2.DOWN

	func _rect_hit(item: Dictionary, point: Vector2) -> bool:
		if item.get("rotation_handle", false):
			return item.rect.has_point(point)
		var center: Vector2 = item.get("center", item.rect.get_center())
		var local_point := center + (point - center).rotated(-float(item.get("rotation", 0.0)))
		return item.rect.has_point(local_point)
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
		if kind == "rcs":
			var mount_direction := _rcs_mount_direction(rect, component, size.x * 0.5 + view_offset.x).rotated(-angle)
			var arrow_length := minf(rect.size.x, rect.size.y) * 0.34
			var arrow_start := rect.get_center() - mount_direction * arrow_length * 0.35
			var arrow_end := rect.get_center() + mount_direction * arrow_length * 0.65
			var arrow_color := Color(0.08, 0.18, 0.28, opacity)
			draw_line(arrow_start, arrow_end, arrow_color, 2.4)
			var arrow_back := -mount_direction * minf(rect.size.x, rect.size.y) * 0.12
			draw_line(arrow_end, arrow_end + arrow_back.rotated(0.65), arrow_color, 2.4)
			draw_line(arrow_end, arrow_end + arrow_back.rotated(-0.65), arrow_color, 2.4)
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
	root.add_theme_constant_override("separation", 6)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 10)
	root.add_theme_constant_override("margin_right", 10)
	root.add_theme_constant_override("margin_top", 8)
	root.add_theme_constant_override("margin_bottom", 8)
	add_child(root)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)
	var title := Label.new()
	title.text = "VEHICLE BUILDER"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	toolbar.add_child(title)
	var name_input := LineEdit.new()
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.placeholder_text = "Vehicle name"
	name_input.text = str(design.get("name", "Custom Vehicle"))
	name_input.text_changed.connect(func(value: String):
		design["name"] = value
		_emit_design()
	)
	toolbar.add_child(name_input)
	_vehicle_name = name_input
	var preset_button := Button.new()
	preset_button.text = "PRESETS"
	preset_button.pressed.connect(_show_preset_dialog)
	toolbar.add_child(preset_button)
	var undo_button := Button.new()
	undo_button.text = "UNDO"
	undo_button.pressed.connect(_undo_change)
	toolbar.add_child(undo_button)
	var redo_button := Button.new()
	redo_button.text = "REDO"
	redo_button.pressed.connect(_redo_change)
	toolbar.add_child(redo_button)

	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 6)
	root.add_child(workspace)

	var parts_panel := PanelContainer.new()
	parts_panel.custom_minimum_size.x = 245.0
	parts_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_panel.name = "PARTS"
	workspace.add_child(parts_panel)
	var parts_column := VBoxContainer.new()
	parts_column.add_theme_constant_override("separation", 6)
	parts_panel.add_child(parts_column)
	var parts_heading := Label.new()
	parts_heading.text = "PARTS"
	parts_heading.add_theme_font_size_override("font_size", 16)
	parts_heading.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	parts_column.add_child(parts_heading)
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search parts..."
	_search_input.text_changed.connect(func(value: String):
		_search = value.to_lower()
		_refresh_parts()
	)
	parts_column.add_child(_search_input)
	_part_filter = OptionButton.new()
	_part_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for category in ["all", "tank", "engine", "decoupler", "structure", "rcs", "docking_port", "power", "payload", "radial"]:
		_part_filter.add_item("All parts" if category == "all" else category.replace("_", " ").capitalize())
		_part_filter.set_item_metadata(_part_filter.item_count - 1, category)
	_part_filter.item_selected.connect(func(index: int):
		_category = str(_part_filter.get_item_metadata(index))
		_refresh_parts()
	)
	parts_column.add_child(_part_filter)
	var parts_scroll := ScrollContainer.new()
	parts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parts_column.add_child(parts_scroll)
	_parts_list = VBoxContainer.new()
	_parts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_list.add_theme_constant_override("separation", 4)
	parts_scroll.add_child(_parts_list)

	var center_panel := PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_panel.custom_minimum_size.x = 420.0
	center_panel.name = "BUILD SPACE"
	workspace.add_child(center_panel)
	var center_column := VBoxContainer.new()
	center_column.add_theme_constant_override("separation", 4)
	center_panel.add_child(center_column)
	var canvas_tools := HBoxContainer.new()
	canvas_tools.add_theme_constant_override("separation", 6)
	center_column.add_child(canvas_tools)
	var canvas_heading := Label.new()
	canvas_heading.text = "ASSEMBLY"
	canvas_heading.add_theme_font_size_override("font_size", 16)
	canvas_heading.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	canvas_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_tools.add_child(canvas_heading)
	var snap_label := Label.new()
	snap_label.text = "Placement"
	canvas_tools.add_child(snap_label)
	_snap_selector = OptionButton.new()
	_snap_selector.tooltip_text = "Parts snaps a part directly onto another part connection point. Free allows unrestricted placement."
	for mode in ["Free", "Parts"]:
		_snap_selector.add_item(mode)
	_snap_selector.select(0)
	_snap_selector.item_selected.connect(func(index: int):
		_canvas.snap_mode = "Attach" if _snap_selector.get_item_text(index) == "Parts" else "Off"
		_canvas.queue_redraw()
	)
	canvas_tools.add_child(_snap_selector)
	var rotation_snap_label := Label.new()
	rotation_snap_label.text = "Angle"
	rotation_snap_label.tooltip_text = "Rotation increment for the selected part"
	canvas_tools.add_child(rotation_snap_label)
	var rotation_snap_selector := OptionButton.new()
	rotation_snap_selector.tooltip_text = "Choose the angle increment used while rotating parts. Hold Ctrl to rotate freely."
	for angle in ["Off", "1°", "5°", "15°", "30°", "45°", "90°"]:
		rotation_snap_selector.add_item(angle)
	rotation_snap_selector.select(3)
	rotation_snap_selector.item_selected.connect(func(index: int):
		var selected_angle := rotation_snap_selector.get_item_text(index)
		_canvas.rotation_snap_degrees = 0.0 if selected_angle == "Off" else float(selected_angle.replace("°", ""))
	)
	canvas_tools.add_child(rotation_snap_selector)
	_canvas = AssemblyCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.component_dropped.connect(_on_component_dropped)
	_canvas.component_moved.connect(_on_component_moved)
	_canvas.component_position_changed.connect(_on_component_position_changed)
	_canvas.component_repositioned.connect(_on_component_repositioned)
	_canvas.component_rotation_started.connect(_on_component_rotation_started)
	_canvas.component_rotated.connect(_on_component_rotated)
	_canvas.component_selected.connect(_on_component_selected)
	_canvas.component_group_position_changed.connect(_on_components_position_changed)
	_canvas.component_stage_selected.connect(_on_canvas_stage_selected)
	_canvas.component_group_rotation_started.connect(_on_component_group_rotation_started)
	_canvas.component_group_rotated.connect(_on_components_group_rotated)
	center_column.add_child(_canvas)
	var view_tools := HBoxContainer.new()
	view_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	center_column.add_child(view_tools)
	var zoom_out := Button.new()
	zoom_out.text = "−"
	zoom_out.tooltip_text = "Zoom out"
	zoom_out.pressed.connect(func():
		_canvas._zoom_at(1.0 / 1.15, _canvas.size * 0.5)
	)
	view_tools.add_child(zoom_out)
	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.tooltip_text = "Zoom in"
	zoom_in.pressed.connect(func():
		_canvas._zoom_at(1.15, _canvas.size * 0.5)
	)
	view_tools.add_child(zoom_in)
	var selected_view_button := Button.new()
	selected_view_button.text = "FRAME PART"
	selected_view_button.tooltip_text = "Zoom to the selected part"
	selected_view_button.pressed.connect(_canvas._frame_selected)
	view_tools.add_child(selected_view_button)
	var fit_button := Button.new()
	fit_button.text = "FIT VEHICLE"
	fit_button.tooltip_text = "Fit the complete vehicle in view"
	fit_button.pressed.connect(func():
		_canvas.zoom = 1.0
		_canvas.view_offset = Vector2.ZERO
		_canvas.queue_redraw()
	)
	view_tools.add_child(fit_button)
	var navigation_hint := Label.new()
	navigation_hint.text = "Ctrl/Shift+click: select parts  •  Drag any selected part: move group  •  Middle/right drag: pan"
	navigation_hint.add_theme_font_size_override("font_size", 10)
	view_tools.add_child(navigation_hint)

	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size.x = 290.0
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.name = "VEHICLE TOOLS"
	workspace.add_child(right_panel)
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(tabs)

	var staging_page := VBoxContainer.new()
	staging_page.name = "Stages"
	staging_page.add_theme_constant_override("separation", 6)
	tabs.add_child(staging_page)
	var stage_heading := Label.new()
	stage_heading.text = "PHYSICAL STAGES"
	stage_heading.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	staging_page.add_child(stage_heading)
	var stage_scroll := ScrollContainer.new()
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	staging_page.add_child(stage_scroll)
	_stage_list = VBoxContainer.new()
	_stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_scroll.add_child(_stage_list)
	var stage_tools := GridContainer.new()
	stage_tools.columns = 2
	staging_page.add_child(stage_tools)
	var add_stage := Button.new()
	add_stage.text = "ADD EMPTY STAGE"
	add_stage.pressed.connect(func():
		_push_undo()
		var stages: Array = design.get("stages", [])
		stages.append(RocketDesign.create_empty_stage())
		design["stages"] = stages
		selected_stage_index = stages.size() - 1
		selected_component_index = -1
		_changed()
	)
	stage_tools.add_child(add_stage)
	var duplicate_stage := Button.new()
	duplicate_stage.text = "DUPLICATE"
	duplicate_stage.pressed.connect(_duplicate_selected_stage)
	stage_tools.add_child(duplicate_stage)
	var delete_stage := Button.new()
	delete_stage.text = "DELETE"
	delete_stage.pressed.connect(_delete_selected_stage)
	stage_tools.add_child(delete_stage)
	var stage_up := Button.new()
	stage_up.text = "MOVE TO TOP"
	stage_up.pressed.connect(func(): _move_stage(1))
	stage_tools.add_child(stage_up)
	var stage_down := Button.new()
	stage_down.text = "MOVE TO BOTTOM"
	stage_down.pressed.connect(func(): _move_stage(-1))
	stage_tools.add_child(stage_down)
	var action_heading := Label.new()
	action_heading.text = "ACTION STAGING"
	action_heading.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	staging_page.add_child(action_heading)
	var action_header := HBoxContainer.new()
	staging_page.add_child(action_header)
	var add_action_stage := Button.new()
	add_action_stage.text = "ADD ACTION STAGE"
	add_action_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_action_stage.pressed.connect(func():
		_push_undo()
		var labels: Array = design.get("staging_stage_labels", []).duplicate(true)
		while labels.size() < _action_stage_list.get_child_count():
			labels.append("Stage %d" % (labels.size() + 1))
		labels.append("Stage %d" % (labels.size() + 1))
		design["staging_stage_labels"] = labels
		design["staging_stage_count"] = labels.size()
		_changed()
	)
	action_header.add_child(add_action_stage)
	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size.y = 130.0
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	staging_page.add_child(action_scroll)
	_action_stage_list = VBoxContainer.new()
	action_scroll.add_child(_action_stage_list)

	var inspector_page := ScrollContainer.new()
	inspector_page.name = "Part"
	inspector_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(inspector_page)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 7)
	inspector_page.add_child(_inspector)

	var vehicle_page := VBoxContainer.new()
	vehicle_page.name = "Vehicle"
	vehicle_page.add_theme_constant_override("separation", 8)
	tabs.add_child(vehicle_page)
	var payload_heading := Label.new()
	payload_heading.text = "PAYLOAD"
	payload_heading.add_theme_color_override("font_color", Color(0.62, 0.84, 1.0))
	vehicle_page.add_child(payload_heading)
	var payload_selector := OptionButton.new()
	payload_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		_payload_mass_input.set_value_no_signal(float(option.get("mass", 500.0)))
		_refresh_stats()
		_emit_design()
	)
	vehicle_page.add_child(payload_selector)
	_payload_selector = payload_selector
	var payload_limits := RocketDesign.payload_mass_limits()
	var payload_mass_input := SpinBox.new()
	payload_mass_input.min_value = float(payload_limits.get("minimum", 0.001))
	payload_mass_input.max_value = float(payload_limits.get("maximum", 1.0e300))
	payload_mass_input.step = float(payload_limits.get("step", 1.0))
	payload_mass_input.value = float(design.get("payload_mass", 500.0))
	payload_mass_input.tooltip_text = "Payload mass in kilograms"
	vehicle_page.add_child(payload_mass_input)
	payload_mass_input.value_changed.connect(func(value: float):
		design["payload_mass"] = value
		design["payload_type"] = "custom"
		_refresh_stats()
		_emit_design()
	)
	_payload_mass_input = payload_mass_input
	var payload_group_input := LineEdit.new()
	payload_group_input.placeholder_text = "Payload subassembly group"
	payload_group_input.text = str(design.get("payload_subassembly_id", "main"))
	payload_group_input.text_submitted.connect(func(value: String):
		design["payload_subassembly_id"] = value.strip_edges().to_lower().replace(" ", "_")
		_emit_design()
	)
	vehicle_page.add_child(payload_group_input)
	_payload_group_input = payload_group_input
	var mirror := CheckButton.new()
	mirror.text = "Mirror side-mounted parts"
	mirror.button_pressed = mirror_enabled
	mirror.toggled.connect(func(enabled: bool):
		mirror_enabled = enabled
		if is_instance_valid(_canvas):
			_canvas.set_meta("mirror_enabled", enabled)
	)
	vehicle_page.add_child(mirror)
	_mirror_button = mirror
	var payload_edit := Button.new()
	payload_edit.text = "EDIT PAYLOAD DETAILS"
	payload_edit.pressed.connect(func(): payload_edit_requested.emit())
	vehicle_page.add_child(payload_edit)
	var vehicle_hint := Label.new()
	vehicle_hint.text = "Placement: Free or Parts. Parts mode snaps directly to connection points on existing parts. Rotate with the handle; Ctrl temporarily disables angle snapping."
	vehicle_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vehicle_page.add_child(vehicle_hint)

	_refresh_inspector()
	var stats := Label.new()
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_theme_color_override("font_color", Color(0.82, 0.89, 0.96))
	root.add_child(stats)
	_stats = stats
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)
	var save_button := Button.new()
	save_button.text = "SAVE"
	save_button.pressed.connect(func(): save_requested.emit())
	footer.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "LOAD"
	load_button.pressed.connect(func(): load_requested.emit())
	footer.add_child(load_button)
	var launch_button := Button.new()
	launch_button.text = "LAUNCH"
	launch_button.custom_minimum_size.x = 130.0
	launch_button.pressed.connect(func(): launch_requested.emit())
	footer.add_child(launch_button)
	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.pressed.connect(func(): back_requested.emit())
	footer.add_child(back_button)


func _refresh() -> void:
	if not is_instance_valid(_canvas):
		return
	_canvas.stage = _current_stage()
	_canvas.design = design
	_canvas.selected_stage_index = selected_stage_index
	_canvas.selected_index = selected_component_index
	_canvas.set_meta("mirror_enabled", mirror_enabled)
	_canvas.snap_mode = "Attach" if is_instance_valid(_snap_selector) and _snap_selector.get_item_text(_snap_selector.selected) == "Parts" else "Off"
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
	var labels: Array = design.get("staging_stage_labels", []).duplicate(true)
	while labels.size() < plan.size():
		labels.append("Stage %d" % (labels.size() + 1))
	if labels.size() > plan.size():
		labels.resize(plan.size())
	design["staging_stage_labels"] = labels
	design["staging_stage_count"] = plan.size()
	for index in range(plan.size()):
		var stage: Dictionary = plan[index]
		var actions: Array = stage.get("actions", [])
		var row := VBoxContainer.new()
		var heading_row := HBoxContainer.new()
		var heading := LineEdit.new()
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.placeholder_text = "Action stage name"
		heading.text = str(labels[index])
		heading.text_submitted.connect(func(value: String): _set_action_stage_label(index, value))
		heading.focus_exited.connect(func():
			if heading.text != str(design.get("staging_stage_labels", [])[index]):
				_set_action_stage_label(index, heading.text)
		)
		heading_row.add_child(heading)
		var move_up := Button.new()
		move_up.text = "↑"
		move_up.disabled = index == 0
		move_up.pressed.connect(func(): _move_action_stage(index, -1))
		heading_row.add_child(move_up)
		var move_down := Button.new()
		move_down.text = "↓"
		move_down.disabled = index >= plan.size() - 1
		move_down.pressed.connect(func(): _move_action_stage(index, 1))
		heading_row.add_child(move_down)
		var delete_stage := Button.new()
		delete_stage.text = "×"
		delete_stage.disabled = plan.size() <= 1
		delete_stage.tooltip_text = "Remove action stage"
		delete_stage.pressed.connect(func(): _delete_action_stage(index))
		heading_row.add_child(delete_stage)
		row.add_child(heading_row)
		var add_action := Button.new()
		add_action.text = "ADD SELECTED PART"
		add_action.disabled = selected_component_index < 0 or selected_component_index >= _current_stage().get("components", []).size()
		add_action.pressed.connect(func(): _add_action_for_selected_part(index))
		row.add_child(add_action)
		for action_variant in actions:
			if not action_variant is Dictionary:
				continue
			var action: Dictionary = action_variant
			var part_uid := str(action.get("part_id", ""))
			var item_row := VBoxContainer.new()
			var item := Label.new()
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item.text = "%s  %s" % [str(action.get("action", "ACTION")).replace("_", " ").to_upper(), _staging_part_label(part_uid)]
			item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item.add_theme_color_override("font_color", Color(0.68, 0.77, 0.86))
			item_row.add_child(item)
			var action_controls := HBoxContainer.new()
			var assignment := OptionButton.new()
			assignment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for target_index in range(plan.size()):
				assignment.add_item(str(labels[target_index]))
				assignment.set_item_metadata(target_index, target_index)
			assignment.select(index)
			assignment.item_selected.connect(func(option_index: int): _set_action_stage(part_uid, int(assignment.get_item_metadata(option_index))))
			action_controls.add_child(assignment)
			var action_up := Button.new()
			action_up.text = "↑"
			action_up.disabled = actions.find(action_variant) == 0
			action_up.pressed.connect(func(): _move_action(part_uid, index, -1))
			action_controls.add_child(action_up)
			var action_down := Button.new()
			action_down.text = "↓"
			action_down.disabled = actions.find(action_variant) == actions.size() - 1
			action_down.pressed.connect(func(): _move_action(part_uid, index, 1))
			action_controls.add_child(action_down)
			var remove_action := Button.new()
			remove_action.text = "×"
			remove_action.tooltip_text = "Remove action"
			remove_action.pressed.connect(func(): _remove_action(part_uid))
			action_controls.add_child(remove_action)
			item_row.add_child(action_controls)
			row.add_child(item_row)
		if actions.is_empty():
			var empty := Label.new()
			empty.text = "No actions assigned"
			empty.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62))
			row.add_child(empty)
		_action_stage_list.add_child(row)

func _staging_part_label(part_uid: String) -> String:
	for stage in design.get("stages", []):
		for component in stage.get("components", []):
			if str(component.get("part_uid", "")) == part_uid:
				return str(component.get("display_name", component.get("name", component.get("id", part_uid))))
	return part_uid

func _set_action_stage_label(stage_index: int, value: String) -> void:
	var labels: Array = design.get("staging_stage_labels", []).duplicate(true)
	if stage_index < 0 or stage_index >= labels.size():
		return
	labels[stage_index] = value.strip_edges()
	design["staging_stage_labels"] = labels
	_changed()

func _update_staging_component(part_uid: String, properties: Dictionary) -> void:
	var stages: Array = design.get("stages", []).duplicate(true)
	for stage_index in range(stages.size()):
		var stage: Dictionary = stages[stage_index]
		var components: Array = stage.get("components", []).duplicate(true)
		var changed_component := false
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			if str(component.get("part_uid", "")) != part_uid:
				continue
			for key in properties:
				component[key] = properties[key]
			components[component_index] = component
			changed_component = true
			break
		if changed_component:
			stages[stage_index] = RocketAssembly.compile_stage(stage, components)
			design["stages"] = stages
			return

func _set_action_stage(part_uid: String, target_stage: int) -> void:
	var plan := StagingSystem.create_plan([design])
	if target_stage < 0 or target_stage >= plan.size():
		return
	_push_undo()
	_update_staging_component(part_uid, {"staging_stage": target_stage, "staging_order": plan[target_stage].actions.size()})
	_changed()

func _move_action(part_uid: String, stage_index: int, direction: int) -> void:
	var plan := StagingSystem.create_plan([design])
	if stage_index < 0 or stage_index >= plan.size():
		return
	var actions: Array = plan[stage_index].get("actions", [])
	var current_index := -1
	for index in range(actions.size()):
		if str(actions[index].get("part_id", "")) == part_uid:
			current_index = index
			break
	var destination := current_index + direction
	if current_index < 0 or destination < 0 or destination >= actions.size():
		return
	_push_undo()
	var ordered_uids: Array[String] = []
	for action in actions:
		ordered_uids.append(str(action.get("part_id", "")))
	var moved_uid: String = ordered_uids.pop_at(current_index)
	ordered_uids.insert(destination, moved_uid)
	var order_by_uid: Dictionary = {}
	for index in range(ordered_uids.size()):
		order_by_uid[ordered_uids[index]] = index
	var stages: Array = design.get("stages", []).duplicate(true)
	for index in range(stages.size()):
		var stage: Dictionary = stages[index]
		var components: Array = stage.get("components", []).duplicate(true)
		var changed_stage := false
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			var uid := str(component.get("part_uid", ""))
			if order_by_uid.has(uid):
				component["staging_order"] = int(order_by_uid[uid])
				components[component_index] = component
				changed_stage = true
		if changed_stage:
			stages[index] = RocketAssembly.compile_stage(stage, components)
	design["stages"] = stages
	_changed()

func _remove_action(part_uid: String) -> void:
	_push_undo()
	_update_staging_component(part_uid, {"staging_action_disabled": true})
	_changed()

func _add_action_for_selected_part(stage_index: int) -> void:
	var components: Array = _current_stage().get("components", [])
	if selected_component_index < 0 or selected_component_index >= components.size():
		return
	var component: Dictionary = components[selected_component_index]
	var part_uid := str(component.get("part_uid", ""))
	if part_uid.is_empty():
		return
	_push_undo()
	var action := str(component.get("staging_action", ""))
	if action.is_empty() or action == "none":
		match str(component.get("kind", "")):
			"engine", "radial":
				action = "activate_engine"
			"tank":
				action = "enable_fuel_supply"
			"rcs":
				action = "activate_rcs"
			"decoupler":
				action = "separate"
			_:
				action = "deploy" if bool(component.get("deployable", false)) else "activate"
	_update_staging_component(part_uid, {"staging_action_disabled": false, "staging_stage": stage_index, "staging_action": action})
	_changed()

func _move_action_stage(stage_index: int, direction: int) -> void:
	var labels: Array = design.get("staging_stage_labels", []).duplicate(true)
	var destination := stage_index + direction
	if stage_index < 0 or stage_index >= labels.size() or destination < 0 or destination >= labels.size():
		return
	_push_undo()
	var moved_label: Variant = labels.pop_at(stage_index)
	labels.insert(destination, moved_label)
	var stages: Array = design.get("stages", []).duplicate(true)
	for index in range(stages.size()):
		var stage: Dictionary = stages[index]
		var components: Array = stage.get("components", []).duplicate(true)
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			var assigned := int(component.get("staging_stage", index))
			if assigned == stage_index:
				assigned = destination
			elif stage_index < destination and assigned > stage_index and assigned <= destination:
				assigned -= 1
			elif destination < stage_index and assigned >= destination and assigned < stage_index:
				assigned += 1
			component["staging_stage"] = assigned
			components[component_index] = component
		stages[index] = RocketAssembly.compile_stage(stage, components)
	design["stages"] = stages
	design["staging_stage_labels"] = labels
	design["staging_stage_count"] = labels.size()
	_changed()

func _delete_action_stage(stage_index: int) -> void:
	var labels: Array = design.get("staging_stage_labels", []).duplicate(true)
	if labels.size() <= 1 or stage_index < 0 or stage_index >= labels.size():
		return
	_push_undo()
	labels.remove_at(stage_index)
	var stages: Array = design.get("stages", []).duplicate(true)
	for index in range(stages.size()):
		var stage: Dictionary = stages[index]
		var components: Array = stage.get("components", []).duplicate(true)
		for component_index in range(components.size()):
			var component: Dictionary = components[component_index]
			var assigned := int(component.get("staging_stage", index))
			if assigned == stage_index:
				assigned = maxi(0, stage_index - 1)
			elif assigned > stage_index:
				assigned -= 1
			component["staging_stage"] = assigned
			components[component_index] = component
		stages[index] = RocketAssembly.compile_stage(stage, components)
	design["stages"] = stages
	design["staging_stage_labels"] = labels
	design["staging_stage_count"] = labels.size()
	_changed()

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
		card.pressed.connect(func(): _add_component(str(option.get("id", "")), "free", false, 1, -1, Vector2.ZERO, "", "", true))
		_parts_list.add_child(card)

func _on_component_dropped(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int, position_m: Vector2, parent_uid: String = "", parent_node_id: String = "") -> void:
	_add_component(component_id, attachment, mirrored, side, insert_index, position_m, parent_uid, parent_node_id)

func _add_component(component_id: String, attachment: String, mirrored: bool, side: int, insert_index: int, position_m: Vector2 = Vector2.ZERO, parent_uid: String = "", parent_node_id: String = "", auto_place: bool = false) -> void:
	var stage := _current_stage()
	if stage.is_empty():
		return
	_push_undo()
	var updated := RocketAssembly.add_component(stage, component_id, attachment, mirrored, side, insert_index)
	if updated.is_empty():
		return
	var components: Array = updated.get("components", [])
	if not components.is_empty() and not parent_uid.is_empty():
		var added_component: Dictionary = components.back()
		added_component["structural_parent_uid"] = parent_uid
		added_component["structural_parent_node_id"] = parent_node_id
		components[components.size() - 1] = added_component
		updated = RocketAssembly.compile_stage(updated, components)
	if attachment == "free" and not components.is_empty():
		var free_component: Dictionary = components.back()
		if auto_place:
			position_m = _next_free_component_position(components, free_component)
		free_component["position_m"] = [position_m.x, position_m.y]
		components[components.size() - 1] = free_component
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


func _next_free_component_position(components: Array, added_component: Dictionary) -> Vector2:
	var core_radius := 0.5
	var side_extent := 0.0
	var rightmost := 0.0
	for component in components:
		var radius := maxf(0.5, float(component.get("collision_radius_m", 0.5)))
		match str(component.get("attachment", "stack")):
			"stack":
				core_radius = maxf(core_radius, radius)
			"side":
				side_extent += radius * 2.5
			"radial":
				rightmost = maxf(rightmost, core_radius + radius * 2.5)
			"free":
				var position_data: Variant = component.get("position_m", [0.0, 0.0])
				if position_data is Array and position_data.size() >= 2:
					rightmost = maxf(rightmost, float(position_data[0]) + radius)
	rightmost = maxf(rightmost, core_radius + side_extent)
	var added_radius := maxf(0.5, float(added_component.get("collision_radius_m", 0.5)))
	return Vector2(rightmost + added_radius + 1.0, 0.0)

func _on_component_position_changed(index: int, position_m: Vector2) -> void:
	var components: Array = _current_stage().get("components", []).duplicate(true)
	if index < 0 or index >= components.size():
		return
	_push_undo()
	var component: Dictionary = components[index]
	component["attachment"] = "free"
	component.erase("mirror")
	component.erase("side")
	component.erase("mount_index")
	component.erase("structural_parent_uid")
	component.erase("structural_parent_node_id")
	component.erase("structural_root")
	component["position_m"] = [position_m.x, position_m.y]
	components[index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(_current_stage(), components)
	selected_component_index = index
	_changed()

func _on_component_repositioned(index: int, attachment: String, side: int, insert_index: int, parent_uid: String = "", parent_node_id: String = "", position_m: Vector2 = Vector2.ZERO) -> void:
	var stage := _current_stage()
	var components: Array = stage.get("components", []).duplicate(true)
	if index < 0 or index >= components.size():
		return
	_push_undo()
	var component: Dictionary = components[index]
	var moved_children: Array[int] = []
	for candidate in range(components.size()):
		if candidate == index:
			continue
		var mounted: Dictionary = components[candidate]
		if str(mounted.get("attachment", "stack")) in ["side", "radial"] and int(mounted.get("mount_index", -1)) == index:
			moved_children.append(candidate - (1 if candidate > index else 0))
	components.remove_at(index)
	for candidate in range(components.size()):
		var mounted: Dictionary = components[candidate]
		if str(mounted.get("attachment", "stack")) not in ["side", "radial"]:
			continue
		var mount_index := int(mounted.get("mount_index", -1))
		if mount_index > index:
			mounted["mount_index"] = mount_index - 1
		elif mount_index == index:
			mounted["mount_index"] = -1
		components[candidate] = mounted
	component.erase("position_m")
	component.erase("mirror")
	component.erase("side")
	component.erase("mount_index")
	component["attachment"] = attachment
	if not parent_uid.is_empty():
		component["structural_parent_uid"] = parent_uid
		component["structural_parent_node_id"] = parent_node_id
		component.erase("structural_root")
	else:
		component.erase("structural_parent_uid")
		component.erase("structural_parent_node_id")
		if attachment != "free":
			component.erase("structural_root")
	if attachment == "stack":
		var stack_indices: Array[int] = []
		for candidate in range(components.size()):
			if str(components[candidate].get("attachment", "stack")) == "stack":
				stack_indices.append(candidate)
		var insert_at := components.size()
		if not stack_indices.is_empty():
			var adjusted_target := insert_index - (1 if index < insert_index else 0)
			insert_at = clampi(adjusted_target, stack_indices[0], stack_indices[-1] + 1)
		components.insert(insert_at, component)
		for candidate in range(components.size()):
			if candidate == insert_at:
				continue
			var mounted: Dictionary = components[candidate]
			if str(mounted.get("attachment", "stack")) not in ["side", "radial"]:
				continue
			var old_candidate := candidate - 1 if candidate > insert_at else candidate
			if moved_children.has(old_candidate):
				mounted["mount_index"] = insert_at
			elif int(mounted.get("mount_index", -1)) >= insert_at:
				mounted["mount_index"] = int(mounted.get("mount_index", -1)) + 1
			components[candidate] = mounted
	elif attachment == "side":
		var axial_indices: Array[int] = []
		for candidate in range(components.size()):
			if str(components[candidate].get("attachment", "stack")) == "stack":
				axial_indices.append(candidate)
		if not axial_indices.is_empty():
			var mount_index := axial_indices[0]
			for candidate in axial_indices:
				if absi(candidate - insert_index) < absi(mount_index - insert_index):
					mount_index = candidate
			component["mount_index"] = mount_index
			component["side"] = side
			components.append(component)
			for candidate in range(components.size() - 1):
				var mounted: Dictionary = components[candidate]
				if str(mounted.get("attachment", "stack")) in ["side", "radial"] and int(mounted.get("mount_index", -1)) < 0:
					mounted["mount_index"] = mount_index
					components[candidate] = mounted
		else:
			component["attachment"] = "free"
			component["position_m"] = [position_m.x, position_m.y]
			components.append(component)
	else:
		component["attachment"] = "free"
		component["position_m"] = [position_m.x, position_m.y]
		components.append(component)
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(stage, components)
	selected_component_index = components.find(component)
	_changed()

func _on_canvas_stage_selected(stage_index: int, component_index: int) -> void:
	selected_stage_index = clampi(stage_index, 0, maxi(0, design.get("stages", []).size() - 1))
	selected_component_index = component_index
	_canvas.stage = _current_stage()
	_canvas.selected_stage_index = selected_stage_index
	_canvas.selected_index = component_index
	_canvas.selected_indices = [component_index]
	_refresh()

func _on_component_rotation_started(_index: int) -> void:
	_push_undo()

func _on_component_group_rotation_started(_indices: Array) -> void:
	_push_undo()

func _on_components_group_rotated(indices: Array, positions: Array, rotations: Array) -> void:
	var stage := _current_stage()
	var components: Array = stage.get("components", []).duplicate(true)
	if indices.size() != positions.size() or indices.size() != rotations.size() or indices.is_empty():
		return
	var selected: Dictionary = {}
	for value in indices:
		selected[int(value)] = true
	var parent_indices: Dictionary = {}
	var previous_stack := -1
	for component_index in range(components.size()):
		var component: Dictionary = components[component_index]
		var parent_index := -1
		var parent_uid := str(component.get("structural_parent_uid", ""))
		if not parent_uid.is_empty():
			for candidate in range(components.size()):
				if str(components[candidate].get("part_uid", "")) == parent_uid:
					parent_index = candidate
					break
		elif str(component.get("attachment", "stack")) == "stack":
			parent_index = previous_stack
		elif str(component.get("attachment", "stack")) in ["side", "radial"]:
			parent_index = int(component.get("mount_index", -1))
		if str(component.get("attachment", "stack")) == "stack":
			previous_stack = component_index
		parent_indices[component_index] = parent_index
	for item in range(indices.size()):
		var index := int(indices[item])
		if index < 0 or index >= components.size():
			continue
		var component: Dictionary = components[index]
		var parent_index := int(parent_indices.get(index, -1))
		if parent_index >= 0 and selected.has(parent_index):
			component["structural_parent_uid"] = str(components[parent_index].get("part_uid", ""))
			component["structural_parent_node_id"] = str(component.get("structural_parent_node_id", "legacy"))
			component.erase("structural_root")
		elif parent_index < 0:
			component.erase("structural_parent_uid")
			component.erase("structural_parent_node_id")
			component["structural_root"] = true
		else:
			component.erase("structural_parent_uid")
			component.erase("structural_parent_node_id")
			component.erase("structural_root")
		component["attachment"] = "free"
		component.erase("mirror")
		component.erase("side")
		component.erase("mount_index")
		var position_m: Vector2 = positions[item]
		component["position_m"] = [position_m.x, position_m.y]
		component["rotation_deg"] = float(rotations[item])
		components[index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(stage, components)
	selected_component_index = int(indices.back())
	_changed(false)

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

func _on_components_position_changed(indices: Array, positions: Array) -> void:
	var stage := _current_stage()
	var components: Array = stage.get("components", []).duplicate(true)
	if indices.size() != positions.size() or indices.is_empty():
		return
	var selected: Dictionary = {}
	for value in indices:
		selected[int(value)] = true
	var parent_indices: Dictionary = {}
	var previous_stack := -1
	for component_index in range(components.size()):
		var component: Dictionary = components[component_index]
		var parent_index := -1
		var parent_uid := str(component.get("structural_parent_uid", ""))
		if not parent_uid.is_empty():
			for candidate in range(components.size()):
				if str(components[candidate].get("part_uid", "")) == parent_uid:
					parent_index = candidate
					break
		elif str(component.get("attachment", "stack")) == "stack":
			parent_index = previous_stack
		elif str(component.get("attachment", "stack")) in ["side", "radial"]:
			parent_index = int(component.get("mount_index", -1))
		if str(component.get("attachment", "stack")) == "stack":
			previous_stack = component_index
		parent_indices[component_index] = parent_index
	_push_undo()
	for item in range(indices.size()):
		var index := int(indices[item])
		if index < 0 or index >= components.size():
			continue
		var component: Dictionary = components[index]
		var parent_index := int(parent_indices.get(index, -1))
		if parent_index >= 0 and selected.has(parent_index):
			component["structural_parent_uid"] = str(components[parent_index].get("part_uid", ""))
			component["structural_parent_node_id"] = str(component.get("structural_parent_node_id", "legacy"))
			component.erase("structural_root")
		elif parent_index < 0:
			component.erase("structural_parent_uid")
			component.erase("structural_parent_node_id")
			component["structural_root"] = true
		else:
			component.erase("structural_parent_uid")
			component.erase("structural_parent_node_id")
			component.erase("structural_root")
		component["attachment"] = "free"
		component.erase("mirror")
		component.erase("side")
		component.erase("mount_index")
		var position_m: Vector2 = positions[item]
		component["position_m"] = [position_m.x, position_m.y]
		components[index] = component
		if not _canvas.selected_indices.has(index):
			_canvas.selected_indices.append(index)
		_canvas.selected_index = index
	selected_component_index = int(indices.back())
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(stage, components)
	_changed()

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
	action_selector.add_item("No action")
	action_selector.set_item_metadata(0, "none")
	var default_action := "none" if bool(component.get("staging_action_disabled", false)) else ("undock_module" if str(component.get("kind", "")) == "docking_port" else str(component.get("staging_action", action_options[0].id if not action_options.is_empty() else "activate")))
	for option in action_options:
		action_selector.add_item(str(option.label))
		action_selector.set_item_metadata(action_selector.item_count - 1, str(option.id))
		if str(option.id) == default_action:
			action_selector.select(action_selector.item_count - 1)
	action_selector.item_selected.connect(func(index: int): _set_component_staging_action(str(action_selector.get_item_metadata(index))))
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

func _set_component_staging_action(value: String) -> void:
	var stage := _current_stage()
	var components: Array = stage.get("components", []).duplicate(true)
	if selected_component_index < 0 or selected_component_index >= components.size():
		return
	_push_undo()
	var component: Dictionary = components[selected_component_index]
	component["staging_action_disabled"] = value == "none"
	if value != "none":
		component["staging_action"] = value
	components[selected_component_index] = component
	design["stages"][selected_stage_index] = RocketAssembly.compile_stage(stage, components)
	_changed()

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
	_changed() if key in ["staging_stage", "staging_action", "staging_order", "staging_action_disabled"] else _changed(false)

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
		design = RocketAssembly.add_preset_hardware(design)
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

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is SpinBox or focus is TextEdit:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_change()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_Y:
		_redo_change()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_D:
		_duplicate_selected_component()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		_remove_selected_component()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F:
		_canvas._frame_selected()
		get_viewport().set_input_as_handled()
		return
	if selected_component_index < 0:
		return
	var components: Array = _current_stage().get("components", [])
	if selected_component_index >= components.size():
		return
	var rotation := float(components[selected_component_index].get("rotation_deg", 0.0))
	if event.keycode == KEY_Q:
		_update_component_property("rotation_deg", rotation - 15.0)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E:
		_update_component_property("rotation_deg", rotation + 15.0)
		get_viewport().set_input_as_handled()


func _finish() -> void:
	_emit_design()
	back_requested.emit()
	queue_free()
