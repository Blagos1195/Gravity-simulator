extends RefCounted
class_name RocketVisual

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
		heights.append(clampf(15.0 + 12.0 * sqrt(mass / maxf(1.0, stack_mass)), 16.0, 27.0))
	var payload_height := 13.0
	var total_height := payload_height
	for height in heights:
		total_height += height
	var y := -total_height * 0.5
	var widest_stage := 0.0
	for i in range(visible_stages.size()):
		var stage: Dictionary = visible_stages[i]
		var mass := float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
		var engine_count := maxi(1, int(stage.get("engine_count", 1)))
		var width := clampf(9.0 + 7.0 * sqrt(mass / maxf(1.0, stack_mass)) + 1.5 * sqrt(float(engine_count - 1)), 10.0, 28.0)
		widest_stage = maxf(widest_stage, width)
	var payload_type := str(design.get("payload_type", "probe"))
	var payload_width := widest_stage * 0.66
	if payload_type == "crew":
		_polygon(canvas, origin, [Vector2(0.0, y), Vector2(-payload_width, y + payload_height), Vector2(payload_width, y + payload_height)], rotation, scale, Color(0.84, 0.88, 0.94))
		_polygon(canvas, origin, [Vector2(0.0, y + 2.0), Vector2(-payload_width * 0.65, y + payload_height * 0.82), Vector2(payload_width * 0.65, y + payload_height * 0.82)], rotation, scale, Color(0.36, 0.65, 0.82))
	elif payload_type == "satellite":
		_polygon(canvas, origin, [Vector2(-payload_width * 2.2, y + 4.0), Vector2(-payload_width * 0.7, y + 4.0), Vector2(-payload_width * 0.7, y + 8.0), Vector2(-payload_width * 2.2, y + 8.0)], rotation, scale, Color(0.16, 0.42, 0.72))
		_polygon(canvas, origin, [Vector2(payload_width * 0.7, y + 4.0), Vector2(payload_width * 2.2, y + 4.0), Vector2(payload_width * 2.2, y + 8.0), Vector2(payload_width * 0.7, y + 8.0)], rotation, scale, Color(0.16, 0.42, 0.72))
		_polygon(canvas, origin, [Vector2(-payload_width * 0.55, y + 2.0), Vector2(payload_width * 0.55, y + 2.0), Vector2(payload_width * 0.55, y + payload_height - 1.0), Vector2(-payload_width * 0.55, y + payload_height - 1.0)], rotation, scale, Color(0.78, 0.7, 0.42))
	else:
		_polygon(canvas, origin, [Vector2(0.0, y), Vector2(-payload_width, y + payload_height), Vector2(payload_width, y + payload_height)], rotation, scale, Color(0.82, 0.87, 0.93))
		_line(canvas, origin, Vector2(-payload_width * 0.65, y + payload_height * 0.7), Vector2(payload_width * 0.65, y + payload_height * 0.7), rotation, scale, Color(0.24, 0.55, 0.75), 1.2)
	y += payload_height
	for i in range(visible_stages.size() - 1, -1, -1):
		var stage: Dictionary = visible_stages[i]
		var height := heights[i]
		var mass := float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
		var engine_count := maxi(1, int(stage.get("engine_count", 1)))
		var width := clampf(9.0 + 7.0 * sqrt(mass / maxf(1.0, stack_mass)) + 1.5 * sqrt(float(engine_count - 1)), 10.0, 28.0)
		var half := width * 0.5
		var body_color := Color(0.35, 0.57, 0.71) if i % 2 == 0 else Color(0.43, 0.63, 0.75)
		_polygon(canvas, origin, [Vector2(-half, y), Vector2(half, y), Vector2(half * 0.92, y + height), Vector2(-half * 0.92, y + height)], rotation, scale, body_color)
		_polygon(canvas, origin, [Vector2(-half * 0.62, y + 2.0), Vector2(half * 0.62, y + 2.0), Vector2(half * 0.62, y + height * 0.62), Vector2(-half * 0.62, y + height * 0.62)], rotation, scale, Color(0.58, 0.73, 0.81, 0.8))
		_line(canvas, origin, Vector2(-half, y + height * 0.78), Vector2(half, y + height * 0.78), rotation, scale, Color(0.9, 0.68, 0.3), 1.5)
		_line(canvas, origin, Vector2(-half, y), Vector2(-half * 0.92, y + height), rotation, scale, Color(0.18, 0.32, 0.43), 0.9)
		_line(canvas, origin, Vector2(half, y), Vector2(half * 0.92, y + height), rotation, scale, Color(0.18, 0.32, 0.43), 0.9)
		if show_stage_labels:
			canvas.draw_string(ThemeDB.fallback_font, _point(origin, Vector2(half + 4.0, y + height * 0.65), rotation, scale), "S%d" % (active_stage_index + i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.8, 0.92))
		var engines := maxi(1, int(stage.get("engine_count", 1)))
		var spacing := width * 0.76 / float(maxi(1, engines - 1))
		var nozzle_width := minf(2.5, width * 0.13, maxf(0.35, spacing * 0.38))
		for engine_index in range(engines):
			var engine_x := (float(engine_index) - float(engines - 1) * 0.5) * spacing
			_polygon(canvas, origin, [Vector2(engine_x - nozzle_width, y + height), Vector2(engine_x + nozzle_width, y + height), Vector2(engine_x + nozzle_width * 0.7, y + height + 4.0), Vector2(engine_x - nozzle_width * 0.7, y + height + 4.0)], rotation, scale, Color(0.56, 0.61, 0.68))
			if engine_enabled and i == 0 and throttle > 0.0:
				var flame_length := 7.0 + 8.0 * clampf(throttle, 0.0, 1.0)
				_polygon(canvas, origin, [Vector2(engine_x - nozzle_width * 0.7, y + height + 4.0), Vector2(engine_x, y + height + 4.0 + flame_length), Vector2(engine_x + nozzle_width * 0.7, y + height + 4.0)], rotation, scale, Color(1.0, 0.48, 0.12, 0.92))
		y += height + 4.0
