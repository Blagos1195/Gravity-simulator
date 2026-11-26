extends RefCounted
class_name RocketVisual

const RocketDesign = preload("res://scripts/rocket_design.gd")

static func camera_scale(camera_zoom: float, visual_scale: float = 1.0) -> float:
	return clampf(camera_zoom * visual_scale * 10.0, 0.002, 5.0)

static func _point(origin: Vector2, local: Vector2, rotation: float, scale: float) -> Vector2:
	return origin + local.rotated(rotation) * scale

static func _polygon(canvas: CanvasItem, origin: Vector2, points: Array[Vector2], rotation: float, scale: float, color: Color) -> void:
	var transformed := PackedVector2Array()
	for point in points:
		transformed.append(_point(origin, point, rotation, scale))
	canvas.draw_colored_polygon(transformed, color)

static func _line(canvas: CanvasItem, origin: Vector2, a: Vector2, b: Vector2, rotation: float, scale: float, color: Color, width: float = 1.0) -> void:
	canvas.draw_line(_point(origin, a, rotation, scale), _point(origin, b, rotation, scale), color, maxf(0.7, width * scale), true)

static func draw_vehicle(canvas: CanvasItem, design: Dictionary, origin: Vector2, rotation: float, scale: float, active_stage_index: int = 0, throttle: float = 0.0, engine_enabled: bool = false, show_stage_labels: bool = false) -> void:
	if scale < 0.025:
		var marker_color := Color(0.48, 0.82, 1.0)
		canvas.draw_circle(origin, 1.1, marker_color)
		canvas.draw_line(origin, origin + Vector2.UP.rotated(rotation) * 2.5, marker_color, 1.0)
		return
	var stages: Array = design.get("stages", [])
	if stages.is_empty():
		return
	var visible_stages: Array[Dictionary] = []
	for i in range(clampi(active_stage_index, 0, stages.size() - 1), stages.size()):
		visible_stages.append(stages[i])
	if visible_stages.is_empty():
		return
	var stack_mass := 0.0
	for stage in visible_stages:
		stack_mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
	var heights: Array[float] = []
	for stage in visible_stages:
		var mass := float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
		var length_factor := maxf(0.25, float(stage.get("visual_length_factor", 1.0)))
		heights.append(clampf((15.0 + 12.0 * sqrt(mass / maxf(1.0, stack_mass))) * length_factor, 8.0, 60.0))
	var widest_stage := 0.0
	for i in range(visible_stages.size()):
		var stage: Dictionary = visible_stages[i]
		var mass := float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
		var engine_count := maxi(1, int(stage.get("engine_count", 1)))
		var diameter_factor := maxf(0.25, float(stage.get("visual_diameter_factor", 1.0)))
		var width := clampf((9.0 + 7.0 * sqrt(mass / maxf(1.0, stack_mass)) + 1.5 * sqrt(float(engine_count - 1))) * diameter_factor, 8.0, 40.0)
		widest_stage = maxf(widest_stage, width)
	var payload_visual: Dictionary = design.get("payload_visual", {})
	var payload_type := str(payload_visual.get("visual_type", design.get("payload_type", "probe")))
	if payload_type == "heavy_cargo":
		payload_type = "cargo"
	var physical_payload_component := bool(payload_visual.get("physical_payload_component", false))
	var payload_width_factor := clampf(float(payload_visual.get("visual_width_factor", 1.0)), 0.25, 4.0)
	var payload_height_factor := clampf(float(payload_visual.get("visual_height_factor", 1.0)), 0.25, 4.0)
	var payload_height := 0.0 if physical_payload_component else 13.0 * payload_height_factor
	var payload_width := widest_stage * 0.66 * payload_width_factor
	var payload_color := Color(0.82, 0.87, 0.93)
	var payload_color_data: Variant = payload_visual.get("visual_color_rgb", [])
	if payload_color_data is Array and payload_color_data.size() == 3:
		payload_color = Color(float(payload_color_data[0]), float(payload_color_data[1]), float(payload_color_data[2]))
	var total_height := payload_height
	for height in heights:
		total_height += height
	var y := -total_height * 0.5
	if not physical_payload_component:
		if payload_type == "crew":
			_polygon(canvas, origin, [Vector2(0.0, y), Vector2(-payload_width, y + payload_height), Vector2(payload_width, y + payload_height)], rotation, scale, payload_color)
			_polygon(canvas, origin, [Vector2(0.0, y + 2.0), Vector2(-payload_width * 0.65, y + payload_height * 0.82), Vector2(payload_width * 0.65, y + payload_height * 0.82)], rotation, scale, Color(0.36, 0.65, 0.82))
		elif payload_type == "satellite":
			_polygon(canvas, origin, [Vector2(-payload_width * 2.2, y + 4.0), Vector2(-payload_width * 0.7, y + 4.0), Vector2(-payload_width * 0.7, y + 8.0), Vector2(-payload_width * 2.2, y + 8.0)], rotation, scale, Color(0.16, 0.42, 0.72))
			_polygon(canvas, origin, [Vector2(payload_width * 0.7, y + 4.0), Vector2(payload_width * 2.2, y + 4.0), Vector2(payload_width * 2.2, y + 8.0), Vector2(payload_width * 0.7, y + 8.0)], rotation, scale, Color(0.16, 0.42, 0.72))
			_polygon(canvas, origin, [Vector2(-payload_width * 0.55, y + 2.0), Vector2(payload_width * 0.55, y + 2.0), Vector2(payload_width * 0.55, y + payload_height - 1.0), Vector2(-payload_width * 0.55, y + payload_height - 1.0)], rotation, scale, payload_color)
		elif payload_type == "cargo":
			_polygon(canvas, origin, [Vector2(-payload_width, y + 1.0), Vector2(payload_width, y + 1.0), Vector2(payload_width * 0.88, y + payload_height), Vector2(-payload_width * 0.88, y + payload_height)], rotation, scale, payload_color)
			_line(canvas, origin, Vector2(-payload_width * 0.8, y + payload_height * 0.32), Vector2(payload_width * 0.8, y + payload_height * 0.32), rotation, scale, Color(0.2, 0.3, 0.4), 1.2)
			_line(canvas, origin, Vector2(-payload_width * 0.8, y + payload_height * 0.72), Vector2(payload_width * 0.8, y + payload_height * 0.72), rotation, scale, Color(0.2, 0.3, 0.4), 1.2)
		else:
			_polygon(canvas, origin, [Vector2(0.0, y), Vector2(-payload_width, y + payload_height), Vector2(payload_width, y + payload_height)], rotation, scale, payload_color)
			_line(canvas, origin, Vector2(-payload_width * 0.65, y + payload_height * 0.7), Vector2(payload_width * 0.65, y + payload_height * 0.7), rotation, scale, Color(0.24, 0.55, 0.75), 1.2)
		y += payload_height
	for i in range(visible_stages.size() - 1, -1, -1):
		var stage: Dictionary = visible_stages[i]
		var height := heights[i]
		var mass := float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
		var engine_count := maxi(1, int(stage.get("engine_count", 1)))
		var diameter_factor := maxf(0.25, float(stage.get("visual_diameter_factor", 1.0)))
		var width := clampf((9.0 + 7.0 * sqrt(mass / maxf(1.0, stack_mass)) + 1.5 * sqrt(float(engine_count - 1))) * diameter_factor, 8.0, 40.0)
		var half := width * 0.5
		var body_color := Color(0.35, 0.57, 0.71) if i % 2 == 0 else Color(0.43, 0.63, 0.75)
		var visual_color: Variant = stage.get("visual_color_rgb", [])
		if visual_color is Array and visual_color.size() == 3:
			body_color = Color(float(visual_color[0]), float(visual_color[1]), float(visual_color[2]))
		var components: Array = stage.get("components", [])
		if not components.is_empty():
			if show_stage_labels:
				canvas.draw_string(ThemeDB.fallback_font, _point(origin, Vector2(half + 4.0, y + height * 0.65), rotation, scale), "S%d" % (active_stage_index + i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.8, 0.92))
			_draw_component_stack(canvas, origin, rotation, scale, components, stage.get("boosters", []), y, height, width, i == 0 and engine_enabled, throttle)
			y += height + 4.0
			continue
		_polygon(canvas, origin, [Vector2(-half, y), Vector2(half, y), Vector2(half * 0.92, y + height), Vector2(-half * 0.92, y + height)], rotation, scale, body_color)
		_polygon(canvas, origin, [Vector2(-half * 0.62, y + 2.0), Vector2(half * 0.62, y + 2.0), Vector2(half * 0.62, y + height * 0.62), Vector2(-half * 0.62, y + height * 0.62)], rotation, scale, Color(0.58, 0.73, 0.81, 0.8))
		_line(canvas, origin, Vector2(-half, y + height * 0.78), Vector2(half, y + height * 0.78), rotation, scale, Color(0.9, 0.68, 0.3), 1.5)
		_line(canvas, origin, Vector2(-half, y), Vector2(-half * 0.92, y + height), rotation, scale, Color(0.18, 0.32, 0.43), 0.9)
		_line(canvas, origin, Vector2(half, y), Vector2(half * 0.92, y + height), rotation, scale, Color(0.18, 0.32, 0.43), 0.9)
		var booster_entries: Array = stage.get("boosters", [])
		for booster_index in range(booster_entries.size()):
			var booster_entry: Dictionary = booster_entries[booster_index]
			var booster := RocketDesign.booster_definition_for_entry(booster_entry)
			if booster.is_empty():
				continue
			var booster_width := clampf(width * float(booster.get("visual_width_factor", 0.5)), 4.0, 20.0)
			var booster_height := clampf(height * float(booster.get("visual_length_factor", 0.9)), 8.0, 64.0)
			var booster_half := booster_width * 0.5
			var booster_offset := half + booster_width * 0.7 + 2.0 + float(booster_index) * (booster_width + 2.0)
			var booster_y := y + (height - booster_height) * 0.5
			var booster_color := Color(0.72, 0.74, 0.78)
			var booster_color_data: Variant = booster.get("visual_color_rgb", [])
			if booster_color_data is Array and booster_color_data.size() == 3:
				booster_color = Color(float(booster_color_data[0]), float(booster_color_data[1]), float(booster_color_data[2]))
			for side in [-1.0, 1.0]:
				var booster_x: float = float(side) * booster_offset
				_polygon(canvas, origin, [Vector2(booster_x - booster_half, booster_y), Vector2(booster_x + booster_half, booster_y), Vector2(booster_x + booster_half * 0.88, booster_y + booster_height), Vector2(booster_x - booster_half * 0.88, booster_y + booster_height)], rotation, scale, booster_color)
				_line(canvas, origin, Vector2(booster_x - booster_half, booster_y + booster_height * 0.76), Vector2(booster_x + booster_half, booster_y + booster_height * 0.76), rotation, scale, Color(0.18, 0.32, 0.43), 1.0)
				_polygon(canvas, origin, [Vector2(booster_x - booster_half * 0.55, booster_y + booster_height), Vector2(booster_x + booster_half * 0.55, booster_y + booster_height), Vector2(booster_x + booster_half * 0.38, booster_y + booster_height + 3.0), Vector2(booster_x - booster_half * 0.38, booster_y + booster_height + 3.0)], rotation, scale, Color(0.56, 0.61, 0.68))
				if engine_enabled and i == 0 and throttle > 0.0:
					var booster_flame_length := 7.0 + 8.0 * clampf(throttle, 0.0, 1.0)
					_polygon(canvas, origin, [Vector2(booster_x - booster_half * 0.38, booster_y + booster_height + 3.0), Vector2(booster_x, booster_y + booster_height + 3.0 + booster_flame_length), Vector2(booster_x + booster_half * 0.38, booster_y + booster_height + 3.0)], rotation, scale, Color(1.0, 0.48, 0.12, 0.92))
		if show_stage_labels:
			canvas.draw_string(ThemeDB.fallback_font, _point(origin, Vector2(half + 4.0, y + height * 0.65), rotation, scale), "S%d" % (active_stage_index + i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.8, 0.92))
		var engines := maxi(1, int(stage.get("engine_count", 1)))
		var visible_engines := mini(engines, 64)
		var engine_layout := str(stage.get("engine_layout", "linear"))
		var engine_positions: Array[Vector2] = []
		var minimum_spacing := width * 0.76 / float(maxi(1, visible_engines - 1))
		if engine_layout == "cluster":
			var columns := ceili(sqrt(float(visible_engines)))
			var rows := ceili(float(visible_engines) / float(columns))
			var spacing_x := width * 0.62 / float(maxi(1, columns - 1))
			var spacing_y := minf(2.4, height * 0.12) / float(maxi(1, rows - 1))
			minimum_spacing = minf(spacing_x, maxf(0.1, spacing_y))
			for engine_index in range(visible_engines):
				var column := engine_index % columns
				var engine_row := int(engine_index / columns)
				var engine_x := (float(column) - float(columns - 1) * 0.5) * spacing_x
				var engine_y := (float(engine_row) - float(rows - 1) * 0.5) * spacing_y
				engine_positions.append(Vector2(engine_x, engine_y))
		elif engine_layout == "radial" and visible_engines > 1:
			var radius := width * 0.22
			minimum_spacing = maxf(0.1, 2.0 * radius * sin(PI / float(visible_engines)))
			for engine_index in range(visible_engines):
				var angle := TAU * float(engine_index) / float(visible_engines)
				engine_positions.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.18))
		else:
			for engine_index in range(visible_engines):
				var engine_x := (float(engine_index) - float(visible_engines - 1) * 0.5) * minimum_spacing
				engine_positions.append(Vector2(engine_x, 0.0))
		var nozzle_width := minf(minf(2.5, width * 0.13), maxf(0.1, minimum_spacing * 0.38))
		for engine_position in engine_positions:
			var engine_y := y + height + engine_position.y
			var engine_x := engine_position.x
			_polygon(canvas, origin, [Vector2(engine_x - nozzle_width, engine_y), Vector2(engine_x + nozzle_width, engine_y), Vector2(engine_x + nozzle_width * 0.7, engine_y + 4.0), Vector2(engine_x - nozzle_width * 0.7, engine_y + 4.0)], rotation, scale, Color(0.56, 0.61, 0.68))
			if engine_enabled and i == 0 and throttle > 0.0:
				var flame_length := 7.0 + 8.0 * clampf(throttle, 0.0, 1.0)
				_polygon(canvas, origin, [Vector2(engine_x - nozzle_width * 0.7, engine_y + 4.0), Vector2(engine_x, engine_y + 4.0 + flame_length), Vector2(engine_x + nozzle_width * 0.7, engine_y + 4.0)], rotation, scale, Color(1.0, 0.48, 0.12, 0.92))
		if engines > visible_engines:
			canvas.draw_string(ThemeDB.fallback_font, _point(origin, Vector2(half + 4.0, y + height), rotation, scale), "×%d" % engines, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.8, 0.92))
		y += height + 4.0

static func draw_wreck(canvas: CanvasItem, origin: Vector2, rotation: float, scale: float) -> void:
	var size := clampf(scale, 0.002, 5.0)
	if size < 0.025:
		canvas.draw_circle(origin, 1.1, Color(0.22, 0.24, 0.27))
		canvas.draw_circle(origin, 0.55, Color(1.0, 0.42, 0.12))
		return
	var hull := Color(0.18, 0.2, 0.23)
	var scorched := Color(0.34, 0.22, 0.16)
	_polygon(canvas, origin, [Vector2(-7.0, -24.0), Vector2(3.0, -19.0), Vector2(6.0, -8.0), Vector2(2.0, 3.0), Vector2(8.0, 17.0), Vector2(-4.0, 22.0), Vector2(-9.0, 8.0), Vector2(-5.0, -4.0)], rotation, size, hull)
	_polygon(canvas, origin, [Vector2(-5.0, -18.0), Vector2(2.0, -15.0), Vector2(4.0, -7.0), Vector2(-3.0, -4.0)], rotation, size, scorched)
	_polygon(canvas, origin, [Vector2(2.0, 4.0), Vector2(7.0, 15.0), Vector2(0.0, 18.0), Vector2(-3.0, 9.0)], rotation, size, Color(0.12, 0.14, 0.17))
	_line(canvas, origin, Vector2(-6.0, -5.0), Vector2(7.0, 1.0), rotation, size, Color(0.72, 0.35, 0.16), 1.8)
	_line(canvas, origin, Vector2(-3.0, 16.0), Vector2(-13.0, 25.0), rotation, size, Color(0.38, 0.42, 0.48), 1.4)
	_line(canvas, origin, Vector2(4.0, -12.0), Vector2(13.0, -18.0), rotation, size, Color(0.38, 0.42, 0.48), 1.4)
	canvas.draw_circle(_point(origin, Vector2(0.0, -8.0), rotation, size), maxf(1.0, 2.0 * size), Color(1.0, 0.42, 0.12, 0.9))

static func _draw_component_stack(canvas: CanvasItem, origin: Vector2, rotation: float, scale: float, components: Array, boosters: Array, y: float, stage_height: float, stage_width: float, engine_enabled: bool, throttle: float) -> void:
	var ordered: Array = components.duplicate(true)
	var total_length := 0.0
	var widest_radius := 0.1
	var side_radius := 0.0
	var side_mount_radii: Dictionary = {}
	for component in ordered:
		var attachment := str(component.get("attachment", "stack"))
		if attachment == "radial":
			continue
		if attachment == "side":
			var mount_index := int(component.get("mount_index", -1))
			side_mount_radii[mount_index] = float(side_mount_radii.get(mount_index, 0.0)) + float(component.get("collision_radius_m", 1.0))
			continue
		total_length += maxf(0.1, float(component.get("length_m", 1.0)))
		widest_radius = maxf(widest_radius, float(component.get("collision_radius_m", 1.0)))
	for mount_radius in side_mount_radii.values():
		side_radius = maxf(side_radius, float(mount_radius))
	var current_y := y
	var mount_positions: Dictionary = {}
	for component_index in range(ordered.size()):
		var component: Dictionary = ordered[component_index]
		if str(component.get("attachment", "stack")) != "stack":
			continue
		var segment_height := stage_height * maxf(0.1, float(component.get("length_m", 1.0))) / maxf(0.1, total_length)
		mount_positions[component_index] = current_y + segment_height * 0.5
		var radius := maxf(0.1, float(component.get("collision_radius_m", widest_radius)))
		var half_width := stage_width * 0.5 * clampf(radius / widest_radius, 0.48, 1.0)
		var kind := str(component.get("kind", "structure"))
		var component_color := Color(0.43, 0.63, 0.75)
		var color_data: Variant = component.get("color_rgb", [])
		if color_data is Array and color_data.size() == 3:
			component_color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]))
		match kind:
			"tank":
				_polygon(canvas, origin, [Vector2(-half_width * 0.9, current_y), Vector2(half_width * 0.9, current_y), Vector2(half_width, current_y + segment_height), Vector2(-half_width, current_y + segment_height)], rotation, scale, component_color)
				_line(canvas, origin, Vector2(-half_width * 0.86, current_y + segment_height * 0.28), Vector2(half_width * 0.86, current_y + segment_height * 0.28), rotation, scale, Color(0.8, 0.86, 0.91), 0.8)
				_line(canvas, origin, Vector2(-half_width * 0.9, current_y + segment_height * 0.78), Vector2(half_width * 0.9, current_y + segment_height * 0.78), rotation, scale, Color(0.2, 0.34, 0.46), 0.8)
			"engine":
				_polygon(canvas, origin, [Vector2(-half_width * 0.62, current_y), Vector2(half_width * 0.62, current_y), Vector2(half_width, current_y + segment_height), Vector2(-half_width, current_y + segment_height)], rotation, scale, component_color)
				_polygon(canvas, origin, [Vector2(-half_width * 0.72, current_y + segment_height * 0.72), Vector2(half_width * 0.72, current_y + segment_height * 0.72), Vector2(half_width * 0.88, current_y + segment_height), Vector2(-half_width * 0.88, current_y + segment_height)], rotation, scale, Color(0.34, 0.39, 0.46))
				if engine_enabled and throttle > 0.0:
					var flame_length := 7.0 + 8.0 * clampf(throttle, 0.0, 1.0)
					_polygon(canvas, origin, [Vector2(-half_width * 0.32, current_y + segment_height), Vector2(0.0, current_y + segment_height + flame_length), Vector2(half_width * 0.32, current_y + segment_height)], rotation, scale, Color(1.0, 0.48, 0.12, 0.92))
			"decoupler":
				_polygon(canvas, origin, [Vector2(-half_width, current_y), Vector2(half_width, current_y), Vector2(half_width, current_y + segment_height), Vector2(-half_width, current_y + segment_height)], rotation, scale, component_color)
				_line(canvas, origin, Vector2(-half_width, current_y + segment_height * 0.5), Vector2(half_width, current_y + segment_height * 0.5), rotation, scale, Color(0.9, 0.76, 0.42), 1.0)
			"docking_port":
				_polygon(canvas, origin, [Vector2(-half_width, current_y + segment_height * 0.2), Vector2(half_width, current_y + segment_height * 0.2), Vector2(half_width, current_y + segment_height * 0.8), Vector2(-half_width, current_y + segment_height * 0.8)], rotation, scale, component_color)
				_line(canvas, origin, Vector2(-half_width * 0.85, current_y + segment_height * 0.5), Vector2(half_width * 0.85, current_y + segment_height * 0.5), rotation, scale, Color(0.12, 0.18, 0.24), 1.4)
			"rcs":
				_polygon(canvas, origin, [Vector2(-half_width * 0.8, current_y + segment_height * 0.2), Vector2(half_width * 0.8, current_y + segment_height * 0.2), Vector2(half_width, current_y + segment_height * 0.5), Vector2(half_width * 0.8, current_y + segment_height * 0.8), Vector2(-half_width * 0.8, current_y + segment_height * 0.8), Vector2(-half_width, current_y + segment_height * 0.5)], rotation, scale, component_color)
			_:
				_polygon(canvas, origin, [Vector2(0.0, current_y), Vector2(half_width, current_y + segment_height * 0.5), Vector2(half_width * 0.72, current_y + segment_height), Vector2(-half_width * 0.72, current_y + segment_height), Vector2(-half_width, current_y + segment_height * 0.5)], rotation, scale, component_color)
		current_y += segment_height
	if side_radius > 0.0:
		var combined_radius := widest_radius + side_radius * 1.75
		var core_half_width := stage_width * 0.5 * widest_radius / combined_radius
		var side_half_width_base := stage_width * 0.5 * (side_radius * 1.75 / combined_radius) / 1.9
		var side_mount_offsets: Dictionary = {}
		for component_index in range(ordered.size()):
			var component: Dictionary = ordered[component_index]
			if str(component.get("attachment", "stack")) != "side":
				continue
			var mount_index := int(component.get("mount_index", -1))
			var component_y := y + (stage_height - stage_height * float(component.get("length_m", 1.0)) / maxf(0.1, total_length)) * 0.5
			if mount_positions.has(mount_index):
				component_y = float(mount_positions[mount_index]) - stage_height * float(component.get("length_m", 1.0)) / maxf(0.1, total_length) * 0.5
			var component_height := maxf(6.0, stage_height * float(component.get("length_m", 1.0)) / maxf(0.1, total_length))
			var component_radius := maxf(0.1, float(component.get("collision_radius_m", side_radius)))
			var component_half_width := maxf(2.0, side_half_width_base * component_radius / side_radius)
			var mount_offset := float(side_mount_offsets.get(mount_index, core_half_width))
			var offset := mount_offset + component_half_width * 0.9
			side_mount_offsets[mount_index] = offset + component_half_width
			var color := Color(0.43, 0.63, 0.75)
			var color_data: Variant = component.get("color_rgb", [])
			if color_data is Array and color_data.size() == 3:
				color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]))
			var kind := str(component.get("kind", "structure"))
			var sides: Array = [-1.0, 1.0] if bool(component.get("mirror", true)) else [float(component.get("side", 1))]
			for side in sides:
				var left := float(side) * offset
				match kind:
					"tank":
						_polygon(canvas, origin, [Vector2(left - component_half_width * 0.9, component_y), Vector2(left + component_half_width * 0.9, component_y), Vector2(left + component_half_width, component_y + component_height), Vector2(left - component_half_width, component_y + component_height)], rotation, scale, color)
						_line(canvas, origin, Vector2(left - component_half_width * 0.86, component_y + component_height * 0.28), Vector2(left + component_half_width * 0.86, component_y + component_height * 0.28), rotation, scale, Color(0.8, 0.86, 0.91), 0.8)
						_line(canvas, origin, Vector2(left - component_half_width * 0.9, component_y + component_height * 0.78), Vector2(left + component_half_width * 0.9, component_y + component_height * 0.78), rotation, scale, Color(0.2, 0.34, 0.46), 0.8)
					"engine":
						_polygon(canvas, origin, [Vector2(left - component_half_width * 0.62, component_y), Vector2(left + component_half_width * 0.62, component_y), Vector2(left + component_half_width, component_y + component_height), Vector2(left - component_half_width, component_y + component_height)], rotation, scale, color)
						if engine_enabled and throttle > 0.0:
							var flame_length := 7.0 + 8.0 * clampf(throttle, 0.0, 1.0)
							_polygon(canvas, origin, [Vector2(left - component_half_width * 0.32, component_y + component_height), Vector2(left, component_y + component_height + flame_length), Vector2(left + component_half_width * 0.32, component_y + component_height)], rotation, scale, Color(1.0, 0.48, 0.12, 0.92))
					_:
						_polygon(canvas, origin, [Vector2(left, component_y), Vector2(left + component_half_width, component_y + component_height * 0.5), Vector2(left + component_half_width * 0.72, component_y + component_height), Vector2(left - component_half_width * 0.72, component_y + component_height), Vector2(left - component_half_width, component_y + component_height * 0.5)], rotation, scale, color)
	for booster_index in range(boosters.size()):
		var booster_entry: Dictionary = boosters[booster_index]
		var booster := RocketDesign.booster_definition_for_entry(booster_entry)
		if booster.is_empty():
			continue
		var booster_width := clampf(stage_width * float(booster.get("visual_width_factor", 0.5)), 4.0, 20.0)
		var booster_height := clampf(stage_height * float(booster.get("visual_length_factor", 0.9)), 8.0, 64.0)
		var booster_half := booster_width * 0.5
		var booster_offset := stage_width * 0.5 + booster_width * 0.7 + 2.0 + float(booster_index) * (booster_width + 2.0)
		var booster_y := y + (stage_height - booster_height) * 0.5
		var mount_index := int(booster_entry.get("mount_index", -1))
		if mount_positions.has(mount_index):
			booster_y = float(mount_positions[mount_index]) - booster_height * 0.5
		var booster_color := Color(0.72, 0.74, 0.78)
		var booster_color_data: Variant = booster.get("visual_color_rgb", [])
		if booster_color_data is Array and booster_color_data.size() == 3:
			booster_color = Color(float(booster_color_data[0]), float(booster_color_data[1]), float(booster_color_data[2]))
		var booster_sides: Array = [-1.0, 1.0] if int(booster.get("pair_count", 2)) == 2 else [float(booster_entry.get("side", 1))]
		for side in booster_sides:
			var booster_x: float = float(side) * booster_offset
			_polygon(canvas, origin, [Vector2(booster_x - booster_half, booster_y), Vector2(booster_x + booster_half, booster_y), Vector2(booster_x + booster_half * 0.88, booster_y + booster_height), Vector2(booster_x - booster_half * 0.88, booster_y + booster_height)], rotation, scale, booster_color)
			if engine_enabled and throttle > 0.0:
				var flame_length := 7.0 + 8.0 * clampf(throttle, 0.0, 1.0)
				_polygon(canvas, origin, [Vector2(booster_x - booster_half * 0.38, booster_y + booster_height), Vector2(booster_x, booster_y + booster_height + flame_length), Vector2(booster_x + booster_half * 0.38, booster_y + booster_height)], rotation, scale, Color(1.0, 0.48, 0.12, 0.92))
