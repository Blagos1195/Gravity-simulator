extends Window

const FlightComputer = preload("res://scripts/flight_computer.gd")

var simulation: Control
var rocket_design: Dictionary = {}
var orbit_plot: OrbitPlot
var current_path := PackedVector2Array()
var node_list: ItemList
var time_input: SpinBox
var prograde_input: SpinBox
var radial_input: SpinBox
var state_report: RichTextLabel
var burn_report: Label
var autopilot_button: Button
var current_body: Dictionary = {}
var relative_position := Vector2.ZERO
var relative_velocity := Vector2.ZERO
var gravitational_parameter := 0.0
var available_delta_v := 0.0
var initial_available_delta_v := 0.0
var nodes: Array[Dictionary] = []
var selected_node_index := -1
var loading_node := false
var current_orbit_duration := 7200.0
var refresh_elapsed := 0.0
var route_target := Vector2.ZERO
var has_route_target := false
var route_duration := 3600.0
var route_delta_v := 0.0
var route_status := "NO DESTINATION SELECTED"
var route_time_input: SpinBox
var route_report: Label

class OrbitPlot extends Control:
	signal node_dragged(index: int, world_position: Vector2)
	signal target_dragged(world_position: Vector2)
	var body_radius := 0.0
	var current_path := PackedVector2Array()
	var planned_path := PackedVector2Array()
	var node_positions := PackedVector2Array()
	var rocket_position := Vector2.ZERO
	var dragging_node := -1
	var dragging_target := false
	var target_position := Vector2.ZERO
	var has_target := false
	var plot_scale := 1.0
	var plot_center := Vector2.ZERO

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging_node = _nearest_node(event.position)
				dragging_target = dragging_node < 0
				if dragging_node >= 0:
					node_dragged.emit(dragging_node, _screen_to_world(event.position))
				elif dragging_target:
					target_dragged.emit(_screen_to_world(event.position))
				accept_event()
			else:
				if dragging_node >= 0:
					node_dragged.emit(dragging_node, _screen_to_world(event.position))
				elif dragging_target:
					target_dragged.emit(_screen_to_world(event.position))
				dragging_node = -1
				dragging_target = false
				accept_event()
		elif event is InputEventMouseMotion:
			if dragging_node >= 0:
				node_dragged.emit(dragging_node, _screen_to_world(event.position))
				accept_event()
			elif dragging_target:
				target_dragged.emit(_screen_to_world(event.position))
				accept_event()

	func _screen_to_world(screen_position: Vector2) -> Vector2:
		return Vector2((screen_position.x - plot_center.x) / plot_scale, -(screen_position.y - plot_center.y) / plot_scale)

	func _nearest_node(mouse_position: Vector2) -> int:
		if node_positions.is_empty() or plot_scale <= 0.0:
			return -1
		var nearest_index := -1
		var nearest_distance := 16.0 * 16.0
		for index in range(node_positions.size()):
			var screen_position := plot_center + Vector2(node_positions[index].x, -node_positions[index].y) * plot_scale
			var distance: float = mouse_position.distance_squared_to(screen_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = index
		return nearest_index

	func set_paths(current: PackedVector2Array, planned: PackedVector2Array, markers: PackedVector2Array, radius: float, initial_position: Vector2, destination: Vector2, destination_enabled: bool) -> void:
		current_path = current
		planned_path = planned
		node_positions = markers
		body_radius = radius
		rocket_position = initial_position
		target_position = destination
		has_target = destination_enabled
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0 or current_path.is_empty():
			return
		var extent: float = maxf(rocket_position.length(), body_radius * 1.2)
		for point in current_path:
			extent = maxf(extent, point.length())
		for point in planned_path:
			extent = maxf(extent, point.length())
		extent = maxf(1.0, extent * 1.08)
		plot_scale = minf(size.x, size.y) * 0.46 / extent
		plot_center = size * 0.5
		var center: Vector2 = plot_center
		var body_screen_radius: float = maxf(4.0, body_radius * plot_scale)
		draw_circle(center, body_screen_radius, Color(0.16, 0.39, 0.72))
		draw_arc(center, body_screen_radius, 0.0, TAU, 96, Color(0.45, 0.72, 1.0), 1.5)
		var current_screen := PackedVector2Array()
		for point in current_path:
			current_screen.append(center + Vector2(point.x, -point.y) * plot_scale)
		var planned_screen := PackedVector2Array()
		for point in planned_path:
			planned_screen.append(center + Vector2(point.x, -point.y) * plot_scale)
		if current_screen.size() > 1:
			draw_polyline(current_screen, Color(0.55, 0.7, 0.82, 0.8), 1.5, true)
		if planned_screen.size() > 1:
			draw_polyline(planned_screen, Color(0.25, 0.9, 0.68), 2.2, true)
		if has_target:
			var target_screen: Vector2 = center + Vector2(target_position.x, -target_position.y) * plot_scale
			draw_circle(target_screen, 8.0, Color(0.25, 0.78, 1.0))
			draw_arc(target_screen, 12.0, 0.0, TAU, 48, Color(0.55, 0.88, 1.0), 1.8)
		var rocket_screen: Vector2 = center + Vector2(rocket_position.x, -rocket_position.y) * plot_scale
		draw_circle(rocket_screen, 4.5, Color(1.0, 0.86, 0.35))
		for index in range(node_positions.size()):
			var node_screen: Vector2 = center + Vector2(node_positions[index].x, -node_positions[index].y) * plot_scale
			draw_circle(node_screen, 7.0, Color(1.0, 0.48, 0.25))
			draw_arc(node_screen, 9.0, 0.0, TAU, 32, Color(1.0, 0.8, 0.5), 1.5)
			draw_string(ThemeDB.fallback_font, node_screen + Vector2(10.0, -8.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.72, 0.42))

func configure(simulation_node: Control, design: Dictionary) -> void:
	simulation = simulation_node
	rocket_design = design.duplicate(true)
	var initial_stages: Array = rocket_design.get("stages", [])
	if not initial_stages.is_empty():
		initial_available_delta_v = FlightComputer.available_delta_v(rocket_design, 0, float(initial_stages[0].get("fuel_capacity", 0.0)))
	title = "FLIGHT COMPUTER  •  ORBITAL ROUTE PLANNER"
	size = Vector2i(980, 820)
	min_size = Vector2i(760, 650)
	close_requested.connect(queue_free)
	_build_interface()
	_refresh_state()

func _build_interface() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 7)
	add_child(root)

	var heading := Label.new()
	heading.text = "ORBITAL ROUTE PLANNER"
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(heading)

	var description := Label.new()
	description.text = "Drag anywhere on the orbital map to set or move a destination. Choose a transfer time and the computer solves the two-body transfer, calculates departure ΔV and previews the route. Drag orange burn nodes to edit additional manoeuvres."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)

	orbit_plot = OrbitPlot.new()
	orbit_plot.custom_minimum_size = Vector2(0, 340)
	orbit_plot.mouse_filter = Control.MOUSE_FILTER_STOP
	orbit_plot.node_dragged.connect(_drag_node_to_orbit_position)
	orbit_plot.target_dragged.connect(_set_route_target)
	orbit_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orbit_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(orbit_plot)

	var destination_row := HBoxContainer.new()
	destination_row.add_theme_constant_override("separation", 8)
	root.add_child(destination_row)
	var duration_label := Label.new()
	duration_label.text = "TRANSFER TIME (HOURS)"
	duration_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	destination_row.add_child(duration_label)
	route_time_input = SpinBox.new()
	route_time_input.min_value = 0.1
	route_time_input.max_value = 8760.0
	route_time_input.step = 0.5
	route_time_input.value = route_duration / 3600.0
	route_time_input.custom_minimum_size.x = 110.0
	route_time_input.value_changed.connect(_change_route_duration)
	destination_row.add_child(route_time_input)
	var clear_target_button := Button.new()
	clear_target_button.text = "CLEAR DESTINATION"
	clear_target_button.pressed.connect(_clear_route_target)
	destination_row.add_child(clear_target_button)
	route_report = Label.new()
	route_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(route_report)

	var legend := Label.new()
	legend.text = "GREY  CURRENT ORBIT     GREEN  PREDICTED ROUTE     BLUE  DESTINATION     ORANGE  BURN NODES"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 11)
	root.add_child(legend)

	state_report = RichTextLabel.new()
	state_report.bbcode_enabled = false
	state_report.fit_content = true
	state_report.custom_minimum_size.y = 66
	state_report.scroll_active = false
	root.add_child(state_report)

	var node_heading := Label.new()
	node_heading.text = "MANOEUVRE SEQUENCE"
	node_heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(node_heading)

	var node_row := HBoxContainer.new()
	node_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(node_row)

	node_list = ItemList.new()
	node_list.custom_minimum_size = Vector2(220, 112)
	node_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_list.item_selected.connect(_select_node)
	node_row.add_child(node_list)

	var node_controls := VBoxContainer.new()
	node_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_row.add_child(node_controls)

	var timing_label := Label.new()
	timing_label.text = "BURN TIME FROM NOW (MINUTES)"
	node_controls.add_child(timing_label)
	time_input = SpinBox.new()
	time_input.min_value = 0.0
	time_input.max_value = 10080.0
	time_input.step = 1.0
	time_input.custom_minimum_size.x = 150.0
	node_controls.add_child(time_input)

	var controls := GridContainer.new()
	controls.columns = 2
	controls.add_theme_constant_override("h_separation", 12)
	controls.add_theme_constant_override("v_separation", 5)
	node_controls.add_child(controls)

	var prograde_label := Label.new()
	prograde_label.text = "PROGRADE ΔV (m/s)"
	controls.add_child(prograde_label)
	prograde_input = _create_burn_input()
	controls.add_child(prograde_input)

	var radial_label := Label.new()
	radial_label.text = "RADIAL ΔV (m/s)"
	controls.add_child(radial_label)
	radial_input = _create_burn_input()
	controls.add_child(radial_input)

	var node_actions := HBoxContainer.new()
	node_actions.add_theme_constant_override("separation", 8)
	node_controls.add_child(node_actions)
	var add_button := Button.new()
	add_button.text = "ADD NODE"
	add_button.pressed.connect(_add_node)
	node_actions.add_child(add_button)
	var remove_button := Button.new()
	remove_button.text = "REMOVE NODE"
	remove_button.pressed.connect(_remove_node)
	node_actions.add_child(remove_button)

	burn_report = Label.new()
	burn_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(burn_report)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var refresh_button := Button.new()
	refresh_button.text = "REFRESH ORBIT"
	refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_button.pressed.connect(_refresh_state)
	actions.add_child(refresh_button)
	autopilot_button = Button.new()
	autopilot_button.text = "SEND ROUTE TO AUTOPILOT"
	autopilot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autopilot_button.pressed.connect(_send_to_autopilot)
	actions.add_child(autopilot_button)
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.pressed.connect(queue_free)
	actions.add_child(close_button)

	time_input.value_changed.connect(_update_selected_node)
	prograde_input.value_changed.connect(_update_selected_node)
	radial_input.value_changed.connect(_update_selected_node)

func _process(delta: float) -> void:
	refresh_elapsed += delta
	if refresh_elapsed >= 0.5 and is_instance_valid(simulation):
		refresh_elapsed = 0.0
		_refresh_state()

func _create_burn_input() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -10000.0
	spin.max_value = 10000.0
	spin.step = 1.0
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 150.0
	return spin

func _refresh_state() -> void:
	if not is_instance_valid(simulation):
		return
	var rocket_position: Vector2 = simulation.get("rocket_position")
	var rocket_velocity: Vector2 = simulation.get("velocity")
	current_body = simulation.call("_nearest_body_state", rocket_position)
	var body_position: Vector2 = current_body.get("position", Vector2.ZERO)
	var body_velocity: Vector2 = current_body.get("velocity", Vector2.ZERO)
	relative_position = rocket_position - body_position
	relative_velocity = rocket_velocity - body_velocity
	gravitational_parameter = FlightComputer.G * float(current_body.get("mass", 0.0))
	if has_route_target:
		_calculate_route()
	else:
		_update_manoeuvre()

func _add_node() -> void:
	if not is_instance_valid(simulation):
		return
	var next_time := 0.0
	if not nodes.is_empty():
		next_time = float(nodes[nodes.size() - 1].get("time_offset", 0.0)) + 30.0
	nodes.append({"time_offset": next_time, "prograde": 0.0, "radial": 0.0})
	selected_node_index = nodes.size() - 1
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _remove_node() -> void:
	if selected_node_index < 0 or selected_node_index >= nodes.size():
		return
	nodes.remove_at(selected_node_index)
	selected_node_index = mini(selected_node_index, nodes.size() - 1)
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _change_route_duration(hours: float) -> void:
	route_duration = hours * 3600.0
	if has_route_target:
		_calculate_route()

func _clear_route_target() -> void:
	has_route_target = false
	route_delta_v = 0.0
	route_status = "NO DESTINATION SELECTED"
	nodes.clear()
	selected_node_index = -1
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _set_route_target(world_position: Vector2) -> void:
	if gravitational_parameter <= 0.0 or relative_position.length() <= 1.0:
		return
	route_target = world_position
	has_route_target = true
	_calculate_route()

func _stumpff_c(value: float) -> float:
	if absf(value) < 0.0001:
		return 0.5 - value / 24.0 + value * value / 720.0
	if value > 0.0:
		var root := sqrt(value)
		return (1.0 - cos(root)) / value
	var hyperbolic_root := sqrt(-value)
	if hyperbolic_root > 50.0:
		return INF
	return (cosh(hyperbolic_root) - 1.0) / (-value)

func _stumpff_s(value: float) -> float:
	if absf(value) < 0.0001:
		return 1.0 / 6.0 - value / 120.0 + value * value / 5040.0
	if value > 0.0:
		var root := sqrt(value)
		return (root - sin(root)) / pow(root, 3.0)
	var hyperbolic_root := sqrt(-value)
	if hyperbolic_root > 50.0:
		return INF
	return (sinh(hyperbolic_root) - hyperbolic_root) / pow(hyperbolic_root, 3.0)

func _lambert_time_function(z: float, radius_start: float, radius_end: float, parameter_a: float) -> float:
	var c_value := _stumpff_c(z)
	var s_value := _stumpff_s(z)
	if not is_finite(c_value) or not is_finite(s_value) or c_value <= 0.0:
		return INF
	var y_value := radius_start + radius_end + parameter_a * (z * s_value - 1.0) / sqrt(c_value)
	if y_value <= 0.0:
		return INF
	return pow(y_value / c_value, 1.5) * s_value + parameter_a * sqrt(y_value)

func _solve_lambert(start_position: Vector2, finish_position: Vector2, duration: float) -> Dictionary:
	var radius_start := start_position.length()
	var radius_end := finish_position.length()
	if radius_start <= 1.0 or radius_end <= 1.0 or duration <= 0.0:
		return {"valid": false, "reason": "Invalid transfer geometry."}
	var cosine := clampf(start_position.dot(finish_position) / (radius_start * radius_end), -1.0, 1.0)
	var sine := start_position.cross(finish_position) / (radius_start * radius_end)
	if absf(1.0 - cosine) < 0.000001 or absf(sine) < 0.000001:
		return {"valid": false, "reason": "Destination is too close to a zero- or half-turn geometry."}
	var parameter_a := sine * sqrt(radius_start * radius_end / (1.0 - cosine))
	if absf(parameter_a) < 0.000001:
		return {"valid": false, "reason": "Transfer geometry is singular."}
	var target_time := sqrt(gravitational_parameter) * duration
	var lower := 0.0
	var upper := 0.0
	var lower_value := _lambert_time_function(0.0, radius_start, radius_end, parameter_a) - target_time
	var upper_value := lower_value
	var bracket_found := false
	var search_direction := 1.0 if lower_value < 0.0 else -1.0
	var previous_z := 0.0
	var previous_value := lower_value
	for search_index in range(1, 391):
		var candidate_z := search_direction * float(search_index) * 0.1
		var candidate_value := _lambert_time_function(candidate_z, radius_start, radius_end, parameter_a) - target_time
		if is_finite(candidate_value) and is_finite(previous_value) and previous_value * candidate_value <= 0.0:
			lower = minf(previous_z, candidate_z)
			upper = maxf(previous_z, candidate_z)
			if lower == previous_z:
				lower_value = previous_value
				upper_value = candidate_value
			else:
				lower_value = candidate_value
				upper_value = previous_value
			bracket_found = true
			break
		if is_finite(candidate_value):
			previous_z = candidate_z
			previous_value = candidate_value
	if not bracket_found:
		return {"valid": false, "reason": "No single-revolution transfer solution exists for that destination and time."}
	for iteration in range(90):
		var middle := (lower + upper) * 0.5
		var middle_value := _lambert_time_function(middle, radius_start, radius_end, parameter_a) - target_time
		if not is_finite(middle_value):
			upper = middle
			continue
		if absf(middle_value) < 0.0001:
			lower = middle
			upper = middle
			break
		if lower_value * middle_value <= 0.0:
			upper = middle
			upper_value = middle_value
		else:
			lower = middle
			lower_value = middle_value
	var z_value := (lower + upper) * 0.5
	var c_value := _stumpff_c(z_value)
	var s_value := _stumpff_s(z_value)
	var y_value := radius_start + radius_end + parameter_a * (z_value * s_value - 1.0) / sqrt(c_value)
	if y_value <= 0.0:
		return {"valid": false, "reason": "Transfer solution is geometrically invalid."}
	var f_value := 1.0 - y_value / radius_start
	var g_value := parameter_a * sqrt(y_value / gravitational_parameter)
	var g_dot := 1.0 - y_value / radius_end
	if absf(g_value) < 0.000001:
		return {"valid": false, "reason": "Transfer time is singular for this geometry."}
	var departure_velocity: Vector2 = (finish_position - f_value * start_position) / g_value
	var arrival_velocity: Vector2 = (g_dot * finish_position - start_position) / g_value
	return {"valid": true, "departure_velocity": departure_velocity, "arrival_velocity": arrival_velocity}

func _calculate_route() -> void:
	if not has_route_target or gravitational_parameter <= 0.0:
		return
	var solution := _solve_lambert(relative_position, route_target, route_duration)
	if not bool(solution.get("valid", false)):
		route_delta_v = INF
		route_status = str(solution.get("reason", "No transfer solution."))
		_update_manoeuvre()
		return
	var required_velocity: Vector2 = solution.departure_velocity
	var required_delta_v: Vector2 = required_velocity - relative_velocity
	var radial := relative_position.normalized()
	var tangent := Vector2(-radial.y, radial.x)
	if relative_position.cross(relative_velocity) < 0.0:
		tangent = -tangent
	route_delta_v = required_delta_v.length()
	route_status = "TRANSFER SOLVED  •  ARRIVAL SPEED %.1f m/s" % Vector2(solution.arrival_velocity).length()
	var route_node := {
		"time_offset": 0.0,
		"prograde": required_delta_v.dot(tangent),
		"radial": required_delta_v.dot(radial)
	}
	if nodes.is_empty():
		nodes.append(route_node)
	else:
		nodes[0] = route_node
	selected_node_index = 0
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _drag_node_to_orbit_position(index: int, world_position: Vector2) -> void:
	if index < 0 or index >= nodes.size() or current_path.size() < 2:
		return
	var nearest_index := 0
	var nearest_distance := INF
	for point_index in range(current_path.size()):
		var distance: float = current_path[point_index].distance_squared_to(world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = point_index
	var fraction := float(nearest_index) / float(current_path.size() - 1)
	var time_offset := fraction * current_orbit_duration
	var step_time := current_orbit_duration / float(current_path.size() - 1)
	var before_index := maxi(0, nearest_index - 1)
	var after_index := mini(current_path.size() - 1, nearest_index + 1)
	var burn_position: Vector2 = current_path[nearest_index]
	var burn_velocity: Vector2 = (current_path[after_index] - current_path[before_index]) / maxf(0.001, float(after_index - before_index) * step_time)
	var radial: Vector2 = burn_position.normalized()
	var tangent := Vector2(-radial.y, radial.x)
	if burn_position.cross(burn_velocity) < 0.0:
		tangent = -tangent
	var circular_velocity := tangent * sqrt(gravitational_parameter / maxf(1.0, burn_position.length()))
	var required_burn: Vector2 = circular_velocity - burn_velocity
	var node: Dictionary = nodes[index]
	node["time_offset"] = time_offset
	node["prograde"] = required_burn.dot(tangent)
	node["radial"] = required_burn.dot(radial)
	nodes[index] = node
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time_offset", 0.0)) < float(b.get("time_offset", 0.0))
	)
	selected_node_index = 0
	for node_index in range(nodes.size()):
		if is_equal_approx(float(nodes[node_index].get("time_offset", 0.0)), time_offset):
			selected_node_index = node_index
			break
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _select_node(index: int) -> void:
	selected_node_index = index
	_load_selected_node()

func _load_selected_node() -> void:
	loading_node = true
	var has_selection: bool = selected_node_index >= 0 and selected_node_index < nodes.size()
	time_input.editable = has_selection
	prograde_input.editable = has_selection
	radial_input.editable = has_selection
	if has_selection:
		var node: Dictionary = nodes[selected_node_index]
		time_input.value = float(node.get("time_offset", 0.0))
		prograde_input.value = float(node.get("prograde", 0.0))
		radial_input.value = float(node.get("radial", 0.0))
	else:
		time_input.value = 0.0
		prograde_input.value = 0.0
		radial_input.value = 0.0
	loading_node = false

func _update_selected_node(_value: float = 0.0) -> void:
	if loading_node or selected_node_index < 0 or selected_node_index >= nodes.size():
		return
	var node: Dictionary = nodes[selected_node_index]
	node["time_offset"] = time_input.value * 60.0
	node["prograde"] = prograde_input.value
	node["radial"] = radial_input.value
	nodes[selected_node_index] = node
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("time_offset", 0.0)) < float(b.get("time_offset", 0.0))
	)
	selected_node_index = 0
	for index in range(nodes.size()):
		if is_equal_approx(float(nodes[index].get("time_offset", 0.0)), time_input.value * 60.0) and is_equal_approx(float(nodes[index].get("prograde", 0.0)), prograde_input.value) and is_equal_approx(float(nodes[index].get("radial", 0.0)), radial_input.value):
			selected_node_index = index
			break
	_rebuild_node_list()
	_update_manoeuvre()

func _rebuild_node_list() -> void:
	node_list.clear()
	for index in range(nodes.size()):
		var node: Dictionary = nodes[index]
		node_list.add_item("NODE %d   T+ %.1f MIN   ΔV %.0f M/S" % [index + 1, float(node.get("time_offset", 0.0)) / 60.0, Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length()])
	if selected_node_index >= 0 and selected_node_index < nodes.size():
		node_list.select(selected_node_index)

func _acceleration(position: Vector2) -> Vector2:
	var radius: float = maxf(1.0, position.length())
	return -position / radius * gravitational_parameter / (radius * radius)

func _append_integrated_path(path: PackedVector2Array, position: Vector2, velocity_value: Vector2, duration: float, max_steps: int) -> Dictionary:
	var steps: int = clampi(int(ceil(duration / 120.0)), 1, max_steps)
	var step: float = duration / float(steps)
	var sample_position: Vector2 = position
	var sample_velocity: Vector2 = velocity_value
	for index in range(steps):
		var first_acceleration: Vector2 = _acceleration(sample_position)
		var half_velocity: Vector2 = sample_velocity + first_acceleration * step * 0.5
		var next_position: Vector2 = sample_position + half_velocity * step
		var second_acceleration: Vector2 = _acceleration(next_position)
		sample_velocity = half_velocity + second_acceleration * step * 0.5
		sample_position = next_position
		path.append(sample_position)
	return {"path": path, "position": sample_position, "velocity": sample_velocity}

func _build_prediction_paths() -> void:
	current_path = PackedVector2Array()
	var planned_path := PackedVector2Array()
	var markers := PackedVector2Array()
	var current_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, gravitational_parameter)
	var orbit_duration: float = 7200.0
	if bool(current_orbit.get("bound", false)):
		var semi_major_axis: float = float(current_orbit.get("semi_major_axis", 0.0))
		if semi_major_axis > 0.0:
			orbit_duration = TAU * sqrt(pow(semi_major_axis, 3.0) / gravitational_parameter)
	orbit_duration = clampf(orbit_duration, 60.0, 30.0 * 86400.0)
	current_orbit_duration = orbit_duration
	var current_result: Dictionary = _append_integrated_path(current_path, relative_position, relative_velocity, orbit_duration, 180)
	current_path = current_result.get("path", PackedVector2Array())
	var plan_position: Vector2 = relative_position
	var plan_velocity: Vector2 = relative_velocity
	var elapsed := 0.0
	var integrated_steps := 0
	for node in nodes:
		var node_time: float = maxf(elapsed, float(node.get("time_offset", 0.0)))
		var coast_duration: float = node_time - elapsed
		if coast_duration > 0.0:
			var coast_steps: int = mini(5500 - integrated_steps, maxi(1, int(ceil(coast_duration / 120.0))))
			if coast_steps <= 0:
				break
			var coast_result: Dictionary = _append_integrated_path(planned_path, plan_position, plan_velocity, coast_duration, coast_steps)
			planned_path = coast_result.get("path", planned_path)
			plan_position = coast_result.get("position", plan_position)
			plan_velocity = coast_result.get("velocity", plan_velocity)
			integrated_steps += coast_steps
		var radial: Vector2 = plan_position.normalized()
		var tangent := Vector2(-radial.y, radial.x)
		if plan_position.cross(plan_velocity) < 0.0:
			tangent = -tangent
		plan_velocity += tangent * float(node.get("prograde", 0.0)) + radial * float(node.get("radial", 0.0))
		markers.append(plan_position)
		elapsed = node_time
	var final_orbit: Dictionary = FlightComputer.orbital_state(plan_position, plan_velocity, gravitational_parameter)
	var final_duration: float = route_duration if has_route_target else 7200.0
	if bool(final_orbit.get("bound", false)):
		var final_axis: float = float(final_orbit.get("semi_major_axis", 0.0))
		if final_axis > 0.0:
			final_duration = TAU * sqrt(pow(final_axis, 3.0) / gravitational_parameter)
	final_duration = route_duration if has_route_target else clampf(final_duration, 60.0, 30.0 * 86400.0)
	var remaining_steps: int = 180
	var final_result: Dictionary = _append_integrated_path(planned_path, plan_position, plan_velocity, final_duration, remaining_steps)
	planned_path = final_result.get("path", planned_path)
	orbit_plot.set_paths(current_path, planned_path, markers, float(current_body.get("radius", 0.0)), relative_position, route_target, has_route_target)
	if not nodes.is_empty():
		var periapsis_altitude: float = (float(final_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0
		var apoapsis_altitude: float = (float(final_orbit.get("apoapsis", INF)) - float(current_body.get("radius", 0.0))) / 1000.0
		state_report.text = "BODY: %s   ALTITUDE: %.1f km   SPEED: %.0f m/s\nCURRENT ORBIT: Pe %.1f km   Ap %s\nFINAL PLANNED ORBIT: Pe %.1f km   Ap %s\nVEHICLE ΔV: %.2f km/s" % [
			str(current_body.get("name", "Unknown")),
			(relative_position.length() - float(current_body.get("radius", 0.0))) / 1000.0,
			relative_velocity.length(),
			(float(current_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0,
			"UNBOUND" if not bool(current_orbit.get("bound", false)) else "%.1f km" % ((float(current_orbit.get("apoapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0),
			periapsis_altitude,
			"UNBOUND" if not bool(final_orbit.get("bound", false)) else "%.1f km" % apoapsis_altitude,
			available_delta_v / 1000.0
		]
	else:
		state_report.text = "BODY: %s   ALTITUDE: %.1f km   SPEED: %.0f m/s\nCURRENT ORBIT: Pe %.1f km   Ap %s\nNO MANOEUVRE NODES PLANNED\nVEHICLE ΔV: %.2f km/s" % [
			str(current_body.get("name", "Unknown")),
			(relative_position.length() - float(current_body.get("radius", 0.0))) / 1000.0,
			relative_velocity.length(),
			(float(current_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0,
			"UNBOUND" if not bool(current_orbit.get("bound", false)) else "%.1f km" % ((float(current_orbit.get("apoapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0),
			available_delta_v / 1000.0
		]

func _update_manoeuvre() -> void:
	if not is_instance_valid(simulation) or gravitational_parameter <= 0.0:
		return
	var active_stage: int = int(simulation.get("stage_index"))
	var remaining_fuel: float = float(simulation.get("fuel"))
	available_delta_v = FlightComputer.available_delta_v(rocket_design, active_stage, remaining_fuel)
	var total_planned_delta_v := 0.0
	for node in nodes:
		total_planned_delta_v += Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length()
	_build_prediction_paths()
	var landed_state: bool = bool(simulation.get("landed"))
	var crashed_state: bool = bool(simulation.get("crashed"))
	var valid_nodes: bool = not nodes.is_empty() and (not has_route_target or is_finite(route_delta_v))
	for node in nodes:
		if Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length() < 0.1:
			valid_nodes = false
	autopilot_button.disabled = landed_state or crashed_state or not valid_nodes or total_planned_delta_v > available_delta_v
	var delta_v_used := maxf(0.0, initial_available_delta_v - available_delta_v)
	burn_report.text = "PLANNED NODES: %d   •   PLANNED ΔV: %.1f m/s   •   ROUTE ΔV: %s   •   USED: %.1f m/s   •   REMAINING: %.1f m/s   •   %s" % [
		nodes.size(),
		total_planned_delta_v,
		"NO SOLUTION" if not is_finite(route_delta_v) else "%.1f m/s" % route_delta_v if has_route_target else "N/A",
		delta_v_used,
		available_delta_v,
		"LAUNCH BEFORE EXECUTING" if landed_state else "CRAFT CRASHED" if crashed_state else "NO VALID ROUTE SOLUTION" if has_route_target and not is_finite(route_delta_v) else "ADD A NON-ZERO BURN" if not valid_nodes else "EXCEEDS VEHICLE ΔV" if total_planned_delta_v > available_delta_v else "READY TO SEND TO AUTOPILOT"
	]
	if is_instance_valid(route_report):
		if has_route_target:
			route_report.text = "%s   •   FLIGHT TIME %.2f HOURS   •   TARGET ALTITUDE %.1f km" % [route_status, route_duration / 3600.0, (route_target.length() - float(current_body.get("radius", 0.0))) / 1000.0]
		else:
			route_report.text = route_status

func _send_to_autopilot() -> void:
	if not is_instance_valid(simulation) or autopilot_button.disabled:
		return
	var route: Array[Dictionary] = []
	var now: float = float(simulation.get("sim_time"))
	for node in nodes:
		route.append({
			"time": now + float(node.get("time_offset", 0.0)),
			"prograde": float(node.get("prograde", 0.0)),
			"radial": float(node.get("radial", 0.0))
		})
	simulation.set("autopilot_enabled", true)
	simulation.set("autopilot_complete", false)
	simulation.set("autopilot_target_mode", "MANEUVER")
	simulation.set("autopilot_route_nodes", route)
	simulation.set("autopilot_route_node_index", 0)
	simulation.set("autopilot_phase", "ROUTE_COAST")
	simulation.set("guidance_enabled", true)
	simulation.set("thrust_key_down", false)
	burn_report.text += "   •   ROUTE SENT TO AUTOPILOT"

