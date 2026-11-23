extends Window

const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

var simulation: Control
var rocket_design: Dictionary = {}
var orbit_plot: OrbitPlot
var current_path := PackedVector2Array()
var planned_path := PackedVector2Array()
var node_list: ItemList
var time_input: SpinBox
var prograde_input: SpinBox
var radial_input: SpinBox
var state_report: RichTextLabel
var burn_report: Label
var autopilot_button: Button
var cancel_route_button: Button
var current_body: Dictionary = {}
var relative_position := Vector2.ZERO
var relative_velocity := Vector2.ZERO
var gravitational_parameter := 0.0
var available_delta_v := 0.0
var initial_available_delta_v := 0.0
var nodes: Array[Dictionary] = []
var planned_path_times := PackedFloat64Array()
var selected_node_index := -1
var loading_node := false
var current_orbit_duration := 7200.0
var refresh_elapsed := 0.0
var route_target := Vector2.ZERO
var has_route_target := false
var route_duration := 3600.0
var route_delta_v := 0.0
var route_solution_dirty := false
var route_status := "NO DESTINATION SELECTED"
var route_time_input: SpinBox
var route_report: Label
var solve_route_button: Button
var target_x_input: SpinBox
var target_y_input: SpinBox
var target_coordinates_loading := false
var interface_scroll: ScrollContainer
var node_editor: Control
var add_node_button: Button
var navigation_planet_dropdown: OptionButton
var navigation_moon_dropdown: OptionButton
var navigation_altitude_input: SpinBox
var route_priority_input: SpinBox
var navigation_report: RichTextLabel
var navigation_progress: Label
var navigation_plot: OrbitPlot
var navigation_engage_button: Button
var manual_navigation_button: Button
var launch_window_button: Button
var replan_button: Button
var navigation_cancel_button: Button
var navigation_plan_valid := false
var navigation_plan: Dictionary = {}
var manual_guidance_report: Label
var manual_guidance_node_index := -1
var manual_guidance_start_time := 0.0
var manual_guidance_burn_vector := Vector2.ZERO
var manual_guidance_target_delta_v := 0.0
var manual_guidance_angle_from_prograde := 0.0
var manual_guidance_completed := false

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
	var interaction_scale := 1.0
	var interaction_center := Vector2.ZERO
	var zoom_factor := 1.0
	var solar_system_mode := false
	var solar_system_bodies: Array[Dictionary] = []
	var solar_system_body_tracks: Array[Dictionary] = []
	var solar_system_target_name := ""

	func _gui_input(event: InputEvent) -> void:
		if solar_system_mode and not (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
			return
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_factor = clampf(zoom_factor * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.25, 4.0)
			queue_redraw()
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				interaction_scale = plot_scale
				interaction_center = plot_center
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
				queue_redraw()
				accept_event()
		elif event is InputEventMouseMotion:
			if dragging_node >= 0:
				node_dragged.emit(dragging_node, _screen_to_world(event.position))
				accept_event()
			elif dragging_target:
				target_dragged.emit(_screen_to_world(event.position))
				accept_event()

	func _screen_to_world(screen_position: Vector2) -> Vector2:
		var scale_value := interaction_scale if dragging_target or dragging_node >= 0 else plot_scale
		var center_value := interaction_center if dragging_target or dragging_node >= 0 else plot_center
		return Vector2((screen_position.x - center_value.x) / scale_value, -(screen_position.y - center_value.y) / scale_value)

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
		solar_system_mode = false
		solar_system_bodies.clear()
		current_path = current
		planned_path = planned
		node_positions = markers
		body_radius = radius
		rocket_position = initial_position
		target_position = destination
		has_target = destination_enabled
		queue_redraw()

	func set_solar_system_path(path: PackedVector2Array, initial_position: Vector2, destination: Vector2, bodies: Array[Dictionary], destination_name: String, body_tracks: Array[Dictionary] = []) -> void:
		solar_system_mode = true
		solar_system_target_name = destination_name
		solar_system_bodies = bodies.duplicate(true)
		solar_system_body_tracks = body_tracks.duplicate(true)
		current_path = PackedVector2Array([initial_position])
		planned_path = path
		node_positions.clear()
		body_radius = 0.0
		rocket_position = initial_position
		target_position = destination
		has_target = true
		queue_redraw()

	func _draw_solar_system() -> void:
		var extent := maxf(rocket_position.length(), target_position.length())
		for point in planned_path:
			extent = maxf(extent, point.length())
		extent = maxf(1.0, extent * 1.08)
		var scale_value := minf(size.x, size.y) * 0.46 / extent * zoom_factor
		var center := size * 0.5
		var path_screen := PackedVector2Array()
		for point in planned_path:
			path_screen.append(center + Vector2(point.x, -point.y) * scale_value)
		if path_screen.size() > 1:
			draw_polyline(path_screen, Color(0.25, 0.9, 0.68), 2.2, true)
		for track in solar_system_body_tracks:
			var track_name := str(track.get("name", ""))
			var positions: PackedVector2Array = track.get("positions", PackedVector2Array())
			var track_screen := PackedVector2Array()
			for body_position in positions:
				track_screen.append(center + Vector2(body_position.x, -body_position.y) * scale_value)
			var track_color := Color(0.92, 0.76, 0.35, 0.55) if track_name == "Sun" else Color(0.25, 0.78, 1.0, 0.55) if track_name == solar_system_target_name else Color(0.55, 0.68, 0.82, 0.4)
			if track_screen.size() > 1:
				draw_polyline(track_screen, track_color, 1.0, true)
			if not track_screen.is_empty():
				draw_circle(track_screen[track_screen.size() - 1], 3.0, track_color)
		for body in solar_system_bodies:
			var body_name := str(body.get("name", ""))
			var body_position: Vector2 = Vector2(body.get("position", Vector2.ZERO))
			var screen_position := center + Vector2(body_position.x, -body_position.y) * scale_value
			var body_color := Color(0.92, 0.76, 0.35) if body_name == "Sun" else Color(0.25, 0.78, 1.0) if body_name == solar_system_target_name else Color(0.55, 0.68, 0.82)
			var screen_radius := maxf(2.5, float(body.get("radius", 0.0)) * scale_value)
			draw_circle(screen_position, screen_radius, body_color)
			draw_string(ThemeDB.fallback_font, screen_position + Vector2(5.0, -5.0), body_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82, 0.88, 0.96))
		var rocket_screen := center + Vector2(rocket_position.x, -rocket_position.y) * scale_value
		var target_screen := center + Vector2(target_position.x, -target_position.y) * scale_value
		draw_circle(rocket_screen, 4.5, Color(1.0, 0.86, 0.35))
		draw_circle(target_screen, 7.0, Color(0.25, 0.78, 1.0))
		draw_arc(target_screen, 11.0, 0.0, TAU, 48, Color(0.55, 0.88, 1.0), 1.8)
		draw_string(ThemeDB.fallback_font, Vector2(8.0, 18.0), "EARTH-CENTRED TRAJECTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.82, 0.92))

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0 or current_path.is_empty():
			return
		if solar_system_mode:
			_draw_solar_system()
			return
		var extent: float = maxf(rocket_position.length(), body_radius * 1.2)
		if has_target:
			extent = maxf(extent, target_position.length())
		for point in current_path:
			extent = maxf(extent, point.length())
		for point in planned_path:
			extent = maxf(extent, point.length())
		extent = maxf(1.0, extent * 1.08)
		var fitted_scale := minf(size.x, size.y) * 0.46 / extent * zoom_factor
		plot_scale = interaction_scale if dragging_target or dragging_node >= 0 else fitted_scale
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
	if not initial_stages.is_empty() and not bool(simulation.get("infinite_weightless_fuel")):
		initial_available_delta_v = FlightComputer.available_delta_v(rocket_design, 0, float(initial_stages[0].get("fuel_capacity", 0.0)))
	elif bool(simulation.get("infinite_weightless_fuel")):
		initial_available_delta_v = FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V
	title = "FLIGHT COMPUTER  •  ORBITAL ROUTE PLANNER"
	size = Vector2i(980, 820)
	min_size = Vector2i(760, 650)
	close_requested.connect(queue_free)
	_build_interface()
	_refresh_state()

func _build_interface() -> void:
	var window_layout := VBoxContainer.new()
	window_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window_layout.offset_left = 12
	window_layout.offset_right = -12
	window_layout.offset_top = 10
	window_layout.offset_bottom = -10
	window_layout.add_theme_constant_override("separation", 6)
	add_child(window_layout)

	interface_scroll = ScrollContainer.new()
	interface_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interface_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	interface_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window_layout.add_child(interface_scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interface_scroll.add_child(root)

	var heading := Label.new()
	heading.text = "ORBITAL ROUTE PLANNER"
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(heading)

	var description := Label.new()
	description.text = "Choose any point inside the current body's sphere of influence by clicking the map or entering body-centred X/Y coordinates. The planner calculates a transfer, previews the path and creates the departure burn. Add or edit further manoeuvre nodes below. Transfers use a simplified two-body model."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)

	var navigation_heading := Label.new()
	navigation_heading.text = "DESTINATION NAVIGATION"
	navigation_heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(navigation_heading)
	var navigation_description := Label.new()
	navigation_description.text = "Plan a transfer to any modeled planet or moon. Choose the fuel-versus-time trade-off, scan future departure windows, then either fly the burns manually with live guidance or hand the route to autopilot."
	navigation_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(navigation_description)
	var navigation_row := HBoxContainer.new()
	root.add_child(navigation_row)
	navigation_planet_dropdown = OptionButton.new()
	navigation_planet_dropdown.add_item("Earth", -2)
	for planet_index in range(FlightComputer.PLANET_TARGETS.size()):
		var planet: Dictionary = FlightComputer.PLANET_TARGETS[planet_index]
		navigation_planet_dropdown.add_item(str(planet.get("name", "Unknown")), planet_index)
	navigation_planet_dropdown.item_selected.connect(func(_index: int):
		_rebuild_navigation_moons(navigation_planet_dropdown.get_selected_id())
		_invalidate_navigation_plan()
	)
	navigation_row.add_child(navigation_planet_dropdown)
	navigation_moon_dropdown = OptionButton.new()
	navigation_moon_dropdown.custom_minimum_size.x = 190.0
	navigation_moon_dropdown.item_selected.connect(func(_index: int): _invalidate_navigation_plan())
	navigation_row.add_child(navigation_moon_dropdown)
	_rebuild_navigation_moons(-2)
	var altitude_row := HBoxContainer.new()
	root.add_child(altitude_row)
	var altitude_label := Label.new()
	altitude_label.text = "TARGET ORBIT ALTITUDE"
	altitude_row.add_child(altitude_label)
	navigation_altitude_input = SpinBox.new()
	navigation_altitude_input.min_value = 1.0
	navigation_altitude_input.max_value = 1000000000.0
	navigation_altitude_input.step = 1.0
	navigation_altitude_input.value = 200.0
	navigation_altitude_input.suffix = " km"
	navigation_altitude_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_altitude_input.value_changed.connect(func(_value: float): _invalidate_navigation_plan())
	altitude_row.add_child(navigation_altitude_input)
	var priority_row := HBoxContainer.new()
	root.add_child(priority_row)
	var priority_label := Label.new()
	priority_label.text = "ROUTE PRIORITY  •  0 = FUEL EFFICIENT, 1 = FAST"
	priority_row.add_child(priority_label)
	route_priority_input = SpinBox.new()
	route_priority_input.min_value = 0.0
	route_priority_input.max_value = 1.0
	route_priority_input.step = 0.05
	route_priority_input.value = float(simulation.get("autopilot_speed_priority"))
	route_priority_input.value_changed.connect(func(value: float):
		simulation.set("autopilot_speed_priority", value)
		_invalidate_navigation_plan()
	)
	priority_row.add_child(route_priority_input)
	var navigation_actions := HBoxContainer.new()
	root.add_child(navigation_actions)
	var calculate_navigation_button := Button.new()
	calculate_navigation_button.text = "CALCULATE DESTINATION TRANSFER"
	calculate_navigation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calculate_navigation_button.pressed.connect(_calculate_destination_plan)
	navigation_actions.add_child(calculate_navigation_button)
	navigation_engage_button = Button.new()
	navigation_engage_button.text = "SEND TO AUTOPILOT"
	navigation_engage_button.disabled = true
	navigation_engage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_engage_button.pressed.connect(_send_destination_to_autopilot)
	navigation_actions.add_child(navigation_engage_button)
	manual_navigation_button = Button.new()
	manual_navigation_button.text = "FLY MANUALLY"
	manual_navigation_button.disabled = true
	manual_navigation_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_navigation_button.pressed.connect(_toggle_manual_destination_plan)
	navigation_actions.add_child(manual_navigation_button)
	launch_window_button = Button.new()
	launch_window_button.text = "SCAN LAUNCH WINDOWS"
	launch_window_button.pressed.connect(_scan_launch_windows)
	navigation_actions.add_child(launch_window_button)
	var manual_actions := HBoxContainer.new()
	root.add_child(manual_actions)
	replan_button = Button.new()
	replan_button.text = "REPLAN FROM CURRENT TRAJECTORY"
	replan_button.disabled = true
	replan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replan_button.pressed.connect(_replan_manual_transfer)
	manual_actions.add_child(replan_button)
	navigation_cancel_button = Button.new()
	navigation_cancel_button.text = "CANCEL MISSION"
	navigation_cancel_button.visible = false
	navigation_cancel_button.pressed.connect(_cancel_destination_autopilot)
	navigation_actions.add_child(navigation_cancel_button)
	navigation_report = RichTextLabel.new()
	navigation_report.bbcode_enabled = false
	navigation_report.fit_content = true
	navigation_report.custom_minimum_size.y = 76
	navigation_report.scroll_active = false
	root.add_child(navigation_report)
	navigation_progress = Label.new()
	navigation_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(navigation_progress)
	navigation_plot = OrbitPlot.new()
	navigation_plot.custom_minimum_size = Vector2(0, 250)
	navigation_plot.mouse_filter = Control.MOUSE_FILTER_STOP
	navigation_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_plot.visible = false
	root.add_child(navigation_plot)

	orbit_plot = OrbitPlot.new()
	orbit_plot.custom_minimum_size = Vector2(0, 250)
	orbit_plot.mouse_filter = Control.MOUSE_FILTER_STOP
	orbit_plot.node_dragged.connect(_drag_node_to_orbit_position)
	orbit_plot.target_dragged.connect(_set_route_target)
	orbit_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orbit_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(orbit_plot)

	var target_coordinate_row := HBoxContainer.new()
	target_coordinate_row.add_theme_constant_override("separation", 8)
	root.add_child(target_coordinate_row)
	var target_x_label := Label.new()
	target_x_label.text = "X (KM)"
	target_x_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target_coordinate_row.add_child(target_x_label)
	target_x_input = _create_coordinate_input()
	target_x_input.tooltip_text = "Target X coordinate relative to the current body's centre."
	target_coordinate_row.add_child(target_x_input)
	var target_y_label := Label.new()
	target_y_label.text = "Y (KM)"
	target_y_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	target_coordinate_row.add_child(target_y_label)
	target_y_input = _create_coordinate_input()
	target_y_input.tooltip_text = "Target Y coordinate relative to the current body's centre."
	target_coordinate_row.add_child(target_y_input)
	var set_target_button := Button.new()
	set_target_button.text = "SET DESTINATION"
	set_target_button.pressed.connect(_apply_target_coordinates)
	target_coordinate_row.add_child(set_target_button)

	var coordinate_hint := Label.new()
	coordinate_hint.text = "Coordinates are relative to the selected body's centre. X points right, Y points up. The destination must be outside the body and inside its sphere of influence."
	coordinate_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(coordinate_hint)

	var destination_row := HBoxContainer.new()
	destination_row.add_theme_constant_override("separation", 8)
	root.add_child(destination_row)
	var duration_label := Label.new()
	duration_label.text = "TIME TO ARRIVAL (HOURS)"
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
	solve_route_button = Button.new()
	solve_route_button.text = "SOLVE TRANSFER"
	solve_route_button.pressed.connect(_calculate_route)
	destination_row.add_child(solve_route_button)
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
	time_input.max_value = 525600.0
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
	var guide_button := Button.new()
	guide_button.text = "ARM / DISARM SELECTED BURN"
	guide_button.pressed.connect(_arm_manual_guidance)
	node_actions.add_child(guide_button)
	var remove_button := Button.new()
	remove_button.text = "REMOVE SELECTED NODE"
	remove_button.pressed.connect(_remove_node)
	node_actions.add_child(remove_button)
	node_editor = node_row

	burn_report = Label.new()
	burn_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(burn_report)
	manual_guidance_report = Label.new()
	manual_guidance_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manual_guidance_report.text = "MANUAL BURN GUIDANCE  •  Select a manoeuvre node and guide its burn here. The flight computer will not steer or fire the engines."
	root.add_child(manual_guidance_report)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	window_layout.add_child(actions)
	add_node_button = Button.new()
	add_node_button.text = "ADD NODE"
	add_node_button.pressed.connect(_add_node)
	actions.add_child(add_node_button)
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
	cancel_route_button = Button.new()
	cancel_route_button.text = "CANCEL ACTIVE ROUTE"
	cancel_route_button.visible = false
	cancel_route_button.pressed.connect(_cancel_route)
	actions.add_child(cancel_route_button)
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.pressed.connect(queue_free)
	actions.add_child(close_button)

	time_input.value_changed.connect(_update_selected_node)
	prograde_input.value_changed.connect(_update_selected_node)
	radial_input.value_changed.connect(_update_selected_node)

func _rebuild_navigation_moons(parent_target_index: int) -> void:
	navigation_moon_dropdown.clear()
	navigation_moon_dropdown.add_item("Planet only", parent_target_index)
	if parent_target_index == -2:
		navigation_moon_dropdown.add_item("Moon", -1)
	else:
		var parent_name := FlightComputer.target_body_name(parent_target_index)
		for satellite in FlightComputer.satellite_targets_for_host(parent_name):
			navigation_moon_dropdown.add_item(str(satellite.get("display_name", satellite.get("name", "Unknown"))), int(satellite.get("id", -1)))
	navigation_moon_dropdown.select(0)
	navigation_moon_dropdown.disabled = navigation_moon_dropdown.item_count <= 1

func _invalidate_navigation_plan() -> void:
	navigation_plan_valid = false
	navigation_plan.clear()
	if is_instance_valid(navigation_plot):
		navigation_plot.visible = false
	if is_instance_valid(navigation_engage_button):
		navigation_engage_button.disabled = true
	if is_instance_valid(navigation_report):
		navigation_report.text = "DESTINATION CHANGED  •  RECALCULATE THE TRANSFER BEFORE SENDING IT TO AUTOPILOT."

func _calculate_destination_plan() -> void:
	if not is_instance_valid(simulation):
		return
	var target_id := navigation_moon_dropdown.get_selected_id()
	var target_name := FlightComputer.target_body_name(target_id)
	var target_altitude := navigation_altitude_input.value * 1000.0
	var target_body: Dictionary = simulation.call("_surface_body_state", target_name)
	if target_body.is_empty():
		_invalidate_navigation_plan()
		navigation_report.text = "TARGET BODY DATA IS UNAVAILABLE."
		return
	var target_radius := float(target_body.get("radius", 0.0)) + target_altitude
	var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(target_name, float(target_body.get("radius", 0.0)))
	var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(float(target_body.get("radius", 0.0)), float(target_body.get("soi", 0.0)))
	if target_altitude < minimum_altitude or target_altitude > maximum_altitude:
		_invalidate_navigation_plan()
		navigation_report.text = "NO STABLE TARGET ORBIT AT THAT ALTITUDE. Valid range: %.1f–%.1f km." % [minimum_altitude / 1000.0, maximum_altitude / 1000.0]
		return
	var rocket_position: Vector2 = simulation.get("rocket_position")
	var current: Dictionary = simulation.call("_nearest_body_state", rocket_position)
	var current_name := str(current.get("name", ""))
	var current_position: Vector2 = rocket_position - Vector2(current.get("position", Vector2.ZERO))
	var current_velocity: Vector2 = Vector2(simulation.get("velocity")) - Vector2(current.get("velocity", Vector2.ZERO))
	var current_mu := FlightComputer.G * float(current.get("mass", 0.0))
	var current_orbit := FlightComputer.orbital_state(current_position, current_velocity, current_mu)
	var current_minimum := FlightComputer.minimum_safe_orbit_altitude(current_name, float(current.get("radius", 0.0)))
	var inside_current_soi := float(current.get("distance", INF)) <= float(current.get("soi", 0.0))
	var current_maximum := FlightComputer.maximum_stable_orbit_altitude(float(current.get("radius", 0.0)), float(current.get("soi", 0.0)))
	var stable_orbit := inside_current_soi and bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current.get("radius", 0.0)) + current_minimum and float(current_orbit.get("apoapsis", INF)) < float(current.get("radius", 0.0)) + current_maximum
	var landed_start := bool(simulation.get("landed"))
	var deep_space_start := not inside_current_soi
	var available: float = FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if bool(simulation.get("infinite_weightless_fuel")) else FlightComputer.available_delta_v(rocket_design, int(simulation.get("stage_index")), float(simulation.get("fuel"))) * (1.0 - float(simulation.get("autopilot_safety_margin")))
	var recovery_plan: Dictionary = {}
	var recovery_is_feasible := false
	if not landed_start and inside_current_soi and not stable_orbit:
		var recovery_altitude := target_altitude if current_name == target_name else clampf(200000.0, current_minimum, maxf(current_minimum, current_maximum))
		recovery_plan = FlightComputer.parking_orbit_recovery_plan(current_position, current_velocity, current_mu, float(current.get("radius", 0.0)), float(current.get("soi", 0.0)), current_name, recovery_altitude)
		if not bool(recovery_plan.get("valid", false)):
			var current_altitude := current_position.length() - float(current.get("radius", 0.0))
			var atmosphere_height := PlanetarySystem.planetary_atmosphere_height(current_name)
			if current_altitude > 0.0 and current_altitude <= maxf(current_minimum, atmosphere_height) and available > 0.0:
				recovery_plan = {"valid": true, "ascent": true, "delta_v": 0.0}
		recovery_is_feasible = bool(recovery_plan.get("valid", false)) and float(recovery_plan.get("delta_v", INF)) <= available
	if current_name == target_name and inside_current_soi:
		if landed_start:
			navigation_plan = {"valid": true, "target_id": target_id, "target_name": target_name, "target_altitude": target_altitude, "local": true, "needs_parking_orbit": true}
		elif stable_orbit:
			var local_plan := FlightComputer.target_radius_burn(current_position, current_velocity, target_radius, current_mu)
			if not bool(local_plan.get("valid", false)) or float(local_plan.get("delta_v", INF)) > available:
				_invalidate_navigation_plan()
				navigation_report.text = "NO FEASIBLE LOCAL ORBIT CHANGE. Check the target orbit and remaining ΔV budget."
				return
			navigation_plan = {"valid": true, "target_id": target_id, "target_name": target_name, "target_altitude": target_altitude, "delta_v": float(local_plan.get("delta_v", 0.0)), "local": true}
		elif recovery_is_feasible:
			navigation_plan = {
				"valid": true,
				"target_id": target_id,
				"target_name": target_name,
				"target_altitude": target_altitude,
				"local": true,
				"needs_parking_orbit": true,
				"recovery_ascent": bool(recovery_plan.get("ascent", false)),
				"recovery_delta_v": float(recovery_plan.delta_v)
			}
		else:
			_invalidate_navigation_plan()
			navigation_report.text = "NO SAFE ORBIT RECOVERY FOUND. " + str(recovery_plan.get("reason", "The current trajectory cannot be captured into the requested orbit within the remaining ΔV."))
			return
	else:
		if landed_start:
			navigation_plan = {"valid": true, "target_id": target_id, "target_name": target_name, "target_altitude": target_altitude, "local": false, "needs_parking_orbit": true}
		elif recovery_is_feasible:
			navigation_plan = {
				"valid": true,
				"target_id": target_id,
				"target_name": target_name,
				"target_altitude": target_altitude,
				"local": false,
				"needs_parking_orbit": true,
				"recovery_ascent": bool(recovery_plan.get("ascent", false)),
				"recovery_delta_v": float(recovery_plan.delta_v)
			}
		else:
			var transfer: Dictionary = FlightComputer.simulated_transfer_search_precise(simulation.get("rocket_position_precise"), simulation.get("velocity"), float(simulation.get("sim_time")), target_id, available, float(simulation.get("autopilot_speed_priority")), false, target_altitude)
			if not bool(transfer.get("valid", false)):
				if not deep_space_start:
					_invalidate_navigation_plan()
					navigation_report.text = "NO FEASIBLE TRANSFER FOUND\n" + str(transfer.get("reason", "No trajectory satisfied the arrival and fuel constraints."))
					return
				navigation_plan = {"valid": true, "target_id": target_id, "target_name": target_name, "target_altitude": target_altitude, "local": false, "needs_window_search": true}
			else:
				navigation_plan = transfer.duplicate(true)
				navigation_plan["target_id"] = target_id
				navigation_plan["target_name"] = target_name
				navigation_plan["target_altitude"] = target_altitude
				navigation_plan["planned_at_time"] = float(simulation.get("sim_time"))
				navigation_plan["planned_position"] = Vector2(simulation.get("rocket_position"))
				navigation_plan["planned_velocity"] = Vector2(simulation.get("velocity"))
				navigation_plan["local"] = false
	navigation_plan["deep_space_start"] = deep_space_start
	navigation_plan_valid = true
	navigation_engage_button.disabled = false
	navigation_plot.visible = not bool(navigation_plan.get("local", false))
	if not bool(navigation_plan.get("local", false)):
		_update_navigation_plot()
	if bool(navigation_plan.get("needs_parking_orbit", false)):
		navigation_report.text = "AUTOPILOT READY  •  %s\nThe vehicle will first establish a safe parking orbit, then calculate the destination transfer." % target_name
	elif bool(navigation_plan.get("local", false)):
		navigation_report.text = "ORBIT CHANGE SOLVED  •  %s\nTarget altitude: %.1f km\nRequired ΔV: %.0f m/s\nThis plan will circularise around the current body." % [target_name, target_altitude / 1000.0, float(navigation_plan.get("delta_v", 0.0))]
	else:
		navigation_report.text = "TRANSFER SOLVED  •  %s\nDeparture: CURRENT ORBIT  •  T+ %.1f s\nDeparture ΔV: %.0f m/s\nArrival capture ΔV: %.0f m/s\nTotal estimated ΔV: %.0f m/s\nFlight time: %.1f days\nClosest approach: %.0f km\nArrival speed: %.0f m/s\nCandidate trajectories: %d\nChoose FLY MANUALLY to execute departure and arrival burns yourself, or SEND TO AUTOPILOT. Finite-burn losses and mid-course corrections remain approximate." % [
			target_name,
			float(navigation_plan.get("planned_at_time", 0.0)),
			float(navigation_plan.get("departure_delta_v", 0.0)),
			float(navigation_plan.get("capture_delta_v", 0.0)),
			float(navigation_plan.get("total_delta_v", 0.0)),
			float(navigation_plan.get("transfer_time", 0.0)) / 86400.0,
			float(navigation_plan.get("closest_approach", 0.0)) / 1000.0,
			float(navigation_plan.get("arrival_speed", 0.0)),
			int(navigation_plan.get("search_candidates", 0))
		]

func _update_navigation_plot() -> void:
	if not is_instance_valid(simulation) or navigation_plan.is_empty():
		return
	var trajectory: PackedVector2Array = navigation_plan.get("trajectory", PackedVector2Array())
	var target_components: PackedFloat64Array = navigation_plan.get("target_position", PackedFloat64Array())
	if trajectory.size() < 2 or target_components.size() < 2:
		navigation_plot.visible = false
		return
	var current_time := float(simulation.get("sim_time"))
	var departure_time := float(navigation_plan.get("departure_time_seconds", navigation_plan.get("planned_at_time", current_time)))
	var transfer_time := maxf(0.0, float(navigation_plan.get("transfer_time", 0.0)))
	var initial_states: Dictionary = PlanetarySystem.gravity_body_states(departure_time)
	var body_names: Array[String] = []
	var bodies: Array[Dictionary] = []
	for body_variant in initial_states.get("surface_bodies", []):
		var body: Dictionary = body_variant
		var body_name := str(body.get("name", "Unknown"))
		body_names.append(body_name)
		var body_position: Vector2 = Vector2(body.get("position", Vector2.ZERO))
		var components: PackedFloat64Array = body.get("position_components", PackedFloat64Array())
		if components.size() >= 2:
			body_position = Vector2(components[0], components[1])
		bodies.append({"name": body_name, "position": body_position, "radius": float(body.get("radius", 0.0))})
	for body_variant in initial_states.get("bodies", []):
		var body: Dictionary = body_variant
		if str(body.get("name", "")) == "Sun":
			var sun_position: Vector2 = Vector2(body.get("position", Vector2.ZERO))
			var sun_components: PackedFloat64Array = body.get("position_components", PackedFloat64Array())
			if sun_components.size() >= 2:
				sun_position = Vector2(sun_components[0], sun_components[1])
			body_names.append("Sun")
			bodies.append({"name": "Sun", "position": sun_position, "radius": float(body.get("radius", 0.0))})
			break
	var body_tracks: Array[Dictionary] = []
	for body_name in body_names:
		body_tracks.append({"name": body_name, "positions": PackedVector2Array()})
	for point_index in range(trajectory.size()):
		var fraction := float(point_index) / float(maxi(1, trajectory.size() - 1))
		var states_at_time: Dictionary = PlanetarySystem.gravity_body_states(departure_time + transfer_time * fraction)
		var positions_by_name: Dictionary = {}
		for body_variant in states_at_time.get("surface_bodies", []):
			var body: Dictionary = body_variant
			var components: PackedFloat64Array = body.get("position_components", PackedFloat64Array())
			if components.size() >= 2:
				positions_by_name[str(body.get("name", ""))] = Vector2(components[0], components[1])
		for body_variant in states_at_time.get("bodies", []):
			var body: Dictionary = body_variant
			if str(body.get("name", "")) == "Sun":
				var components: PackedFloat64Array = body.get("position_components", PackedFloat64Array())
				if components.size() >= 2:
					positions_by_name["Sun"] = Vector2(components[0], components[1])
		for track_index in range(body_tracks.size()):
			var track: Dictionary = body_tracks[track_index]
			var track_positions: PackedVector2Array = track.get("positions", PackedVector2Array())
			track_positions.append(positions_by_name.get(str(track.get("name", "")), Vector2.ZERO))
			track["positions"] = track_positions
			body_tracks[track_index] = track
	navigation_plot.set_solar_system_path(
		trajectory,
		Vector2(simulation.get("rocket_position")),
		Vector2(target_components[0], target_components[1]),
		bodies,
		str(navigation_plan.get("target_name", "")),
		body_tracks
	)

func _refresh_navigation_state() -> void:
	if not is_instance_valid(simulation) or not is_instance_valid(navigation_engage_button):
		return
	var autopilot_enabled := bool(simulation.get("autopilot_enabled"))
	var target_mode := str(simulation.get("autopilot_target_mode"))
	var autopilot_target_id := int(simulation.get("autopilot_planet_index"))
	var phase := str(simulation.get("autopilot_phase"))
	var destination_mission := target_mode == "ORBIT" and (autopilot_enabled or phase in ["COMPLETE", "FAILED", "ARRIVAL_PENDING"])
	navigation_cancel_button.visible = destination_mission
	navigation_cancel_button.text = "CANCEL DESTINATION MISSION" if autopilot_enabled else "CLEAR MISSION STATUS"
	if autopilot_enabled:
		navigation_engage_button.disabled = true
		navigation_engage_button.text = "AUTOPILOT ACTIVE"
	elif destination_mission:
		navigation_engage_button.disabled = not navigation_plan_valid
		navigation_engage_button.text = "SEND NEW PLAN"
	else:
		navigation_engage_button.disabled = not navigation_plan_valid
		navigation_engage_button.text = "SEND TO AUTOPILOT"
	if destination_mission:
		var target_name := FlightComputer.target_body_name(autopilot_target_id)
		var target_state: Dictionary = simulation.call("_surface_body_state", target_name)
		var rocket_position: Vector2 = simulation.get("rocket_position")
		var rocket_velocity: Vector2 = simulation.get("velocity")
		var target_position: Vector2 = target_state.get("position", Vector2.ZERO)
		var target_velocity: Vector2 = target_state.get("velocity", Vector2.ZERO)
		var range_to_target := rocket_position.distance_to(target_position)
		var relative_speed := (rocket_velocity - target_velocity).length()
		navigation_progress.text = "MISSION: %s  •  PHASE: %s  •  RANGE: %.0f km  •  RELATIVE SPEED: %.0f m/s\n%s" % [
			target_name.to_upper(),
			phase.replace("_", " "),
			range_to_target / 1000.0,
			relative_speed,
			str(simulation.get("status_message"))
		]
	elif autopilot_enabled:
		navigation_progress.text = "ANOTHER AUTOPILOT MODE IS ACTIVE. Finish or cancel it before starting destination navigation."
	else:
		navigation_progress.text = "NO DESTINATION MISSION ACTIVE."
	if navigation_plan_valid and not bool(navigation_plan.get("local", false)):
		_update_navigation_plot()
	var manual_plan: Dictionary = simulation.get("manual_flight_plan")
	var manual_active := not manual_plan.is_empty() and bool(manual_plan.get("active", false))
	manual_navigation_button.disabled = not manual_active and (not navigation_plan_valid or autopilot_enabled)
	manual_navigation_button.text = "CANCEL MANUAL PLAN" if manual_active else "FLY MANUALLY"
	navigation_engage_button.disabled = navigation_engage_button.disabled or manual_active
	launch_window_button.disabled = autopilot_enabled or bool(simulation.get("landed")) or bool(simulation.get("crashed"))
	replan_button.disabled = manual_plan.is_empty() or not manual_active or str(manual_plan.get("phase", "")) != "TRANSFER_COAST"
	_update_manual_guidance()

func _cancel_destination_autopilot() -> void:
	if not is_instance_valid(simulation) or str(simulation.get("autopilot_target_mode")) != "ORBIT":
		return
	var was_active := bool(simulation.get("autopilot_enabled"))
	simulation.set("autopilot_enabled", false)
	simulation.set("guidance_enabled", false)
	simulation.set("thrust_key_down", false)
	simulation.set("autopilot_complete", false)
	simulation.set("autopilot_phase", "IDLE")
	simulation.set("autopilot_burn_remaining", 0.0)
	simulation.set("autopilot_burn_direction", Vector2.ZERO)
	simulation.set("autopilot_transfer_start_time", -1.0)
	simulation.set("autopilot_transfer_duration", 0.0)
	simulation.set("autopilot_precomputed_transfer_plan", {})
	simulation.set("status_message", "FLIGHT COMPUTER  •  DESTINATION MISSION %s" % ("CANCELLED" if was_active else "STATUS CLEARED"))
	_refresh_navigation_state()

func _send_destination_to_autopilot() -> void:
	if not navigation_plan_valid or not is_instance_valid(simulation) or bool(simulation.get("crashed")):
		return
	simulation.set("manual_flight_plan", {})
	simulation.set("manual_burn_tracking_enabled", false)
	var target_id := int(navigation_plan.get("target_id", -999))
	var target_name := str(navigation_plan.get("target_name", ""))
	if target_id == -999 or target_name.is_empty():
		return
	if not bool(navigation_plan.get("local", false)):
		var planned_position: Vector2 = navigation_plan.get("planned_position", Vector2.INF)
		var planned_velocity: Vector2 = navigation_plan.get("planned_velocity", Vector2.INF)
		var current_position: Vector2 = simulation.get("rocket_position")
		var current_velocity: Vector2 = simulation.get("velocity")
		var plan_age: float = absf(float(simulation.get("sim_time")) - float(navigation_plan.get("planned_at_time", -INF)))
		if plan_age > 2.0 or planned_position.distance_to(current_position) > 20000.0 or planned_velocity.distance_to(current_velocity) > 5.0:
			_calculate_destination_plan()
			if not navigation_plan_valid:
				return
	var current: Dictionary = simulation.call("_nearest_body_state", simulation.get("rocket_position"))
	var current_name := str(current.get("name", ""))
	var relative_position: Vector2 = Vector2(simulation.get("rocket_position")) - Vector2(current.get("position", Vector2.ZERO))
	var relative_velocity: Vector2 = Vector2(simulation.get("velocity")) - Vector2(current.get("velocity", Vector2.ZERO))
	var current_orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(current.get("mass", 0.0)))
	var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(current_name, float(current.get("radius", 0.0)))
	var inside_current_soi := float(current.get("distance", INF)) <= float(current.get("soi", 0.0))
	var stable_orbit := inside_current_soi and bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current.get("radius", 0.0)) + minimum_altitude
	var landed_start := bool(simulation.get("landed"))
	simulation.set("autopilot_enabled", true)
	simulation.set("autopilot_complete", false)
	simulation.set("autopilot_target_mode", "ORBIT")
	simulation.set("autopilot_planet_index", target_id)
	simulation.set("autopilot_target_altitude", float(navigation_plan.get("target_altitude", 200000.0)))
	simulation.set("autopilot_burn_remaining", 0.0)
	simulation.set("autopilot_burn_direction", Vector2.ZERO)
	simulation.set("autopilot_transfer_corrections", 0)
	simulation.set("autopilot_precomputed_transfer_plan", navigation_plan.duplicate(true) if not bool(navigation_plan.get("local", false)) else {})
	simulation.set("autopilot_apsis_correction_armed", true)
	simulation.set("autopilot_apsis_correction_angle", relative_position.angle())
	var needs_parking_orbit := bool(navigation_plan.get("needs_parking_orbit", false))
	var recovery_ascent := bool(navigation_plan.get("recovery_ascent", false))
	simulation.set("autopilot_phase", "ASCENT" if landed_start or recovery_ascent else "CIRCULARISE" if needs_parking_orbit or (current_name == target_name and stable_orbit) else "ASCENT" if not stable_orbit and inside_current_soi else "PLAN_TRANSFER")
	simulation.set("guidance_enabled", true)
	simulation.set("thrust_key_down", landed_start or (not needs_parking_orbit and not stable_orbit and inside_current_soi))
	simulation.set("status_message", "FLIGHT COMPUTER  •  NAVIGATING TO %s" % target_name.to_upper())
	navigation_engage_button.disabled = true
	navigation_engage_button.text = "AUTOPILOT ACTIVE"
	navigation_report.text += "\n\nAUTOPILOT ENGAGED. The calculated departure solution has been handed to the live guidance system."
	_refresh_navigation_state()

func _process(delta: float) -> void:
	refresh_elapsed += delta
	if refresh_elapsed >= 0.5 and is_instance_valid(simulation):
		refresh_elapsed = 0.0
		_refresh_state()

func _create_coordinate_input() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -1000000000000.0
	spin.max_value = 1000000000000.0
	spin.step = 1.0
	spin.custom_minimum_size.x = 150.0
	return spin

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
	if has_route_target and not route_solution_dirty:
		_calculate_route()
	else:
		_update_manoeuvre()
	_refresh_navigation_state()

func _arm_manual_guidance() -> void:
	if not is_instance_valid(simulation) or selected_node_index < 0 or selected_node_index >= nodes.size():
		return
	if manual_guidance_node_index == selected_node_index:
		manual_guidance_node_index = -1
		manual_guidance_completed = false
		simulation.set("manual_burn_tracking_enabled", false)
		simulation.set("thrust_key_down", false)
		manual_guidance_report.text = "MANUAL NODE GUIDANCE DISARMED."
		_update_manoeuvre()
		return
	var existing_plan: Dictionary = simulation.get("manual_flight_plan")
	if not existing_plan.is_empty() and bool(existing_plan.get("active", false)):
		manual_guidance_report.text = "A MANUAL DESTINATION PLAN IS ALREADY ACTIVE. Complete or cancel it before arming a separate manoeuvre node."
		return
	var node: Dictionary = nodes[selected_node_index]
	var node_time := maxf(0.0, float(node.get("time_offset", 0.0)))
	var predicted_state := _manual_node_state(node_time)
	var guidance := FlightComputer.manoeuvre_burn_guidance(
		Vector2(predicted_state.get("position", relative_position)),
		Vector2(predicted_state.get("velocity", relative_velocity)),
		float(node.get("prograde", 0.0)),
		float(node.get("radial", 0.0))
	)
	if not bool(guidance.get("valid", false)) or float(guidance.get("delta_v", 0.0)) < 0.1:
		manual_guidance_report.text = "THE SELECTED NODE DOES NOT CONTAIN A VALID BURN."
		return
	manual_guidance_node_index = selected_node_index
	manual_guidance_start_time = float(simulation.get("sim_time"))
	manual_guidance_burn_vector = Vector2(guidance.get("burn_vector", Vector2.ZERO))
	manual_guidance_target_delta_v = float(guidance.get("delta_v", 0.0))
	manual_guidance_angle_from_prograde = float(guidance.get("angle_from_prograde", 0.0))
	manual_guidance_completed = false
	simulation.set("manual_burn_tracking_enabled", false)
	simulation.set("manual_burn_target_vector", manual_guidance_burn_vector)
	simulation.set("manual_burn_accumulated_vector", Vector2.ZERO)
	simulation.set("thrust_key_down", false)
	_update_manual_guidance()

func _manual_node_state(node_time: float) -> Dictionary:
	if node_time <= 0.0 or planned_path.size() < 3 or planned_path_times.size() != planned_path.size():
		return {"position": relative_position, "velocity": relative_velocity}
	var nearest_index := 0
	var nearest_difference := INF
	for index in range(planned_path_times.size()):
		var difference := absf(planned_path_times[index] - node_time)
		if difference < nearest_difference:
			nearest_difference = difference
			nearest_index = index
	var before_index := maxi(0, nearest_index - 1)
	var duration := planned_path_times[nearest_index] - planned_path_times[before_index]
	var predicted_velocity := relative_velocity
	if duration > 0.001:
		predicted_velocity = (planned_path[nearest_index] - planned_path[before_index]) / duration
	return {"position": planned_path[nearest_index], "velocity": predicted_velocity}

func _update_manual_guidance() -> void:
	if not is_instance_valid(manual_guidance_report) or not is_instance_valid(simulation):
		return
	var manual_plan: Dictionary = simulation.get("manual_flight_plan")
	if not manual_plan.is_empty():
		_update_manual_flight_plan()
		return
	if manual_guidance_node_index < 0 or manual_guidance_node_index >= nodes.size():
		manual_guidance_report.text = "MANUAL GUIDANCE  •  Select a manoeuvre node and arm its burn. No automatic steering or thrust is used."
		return
	var node: Dictionary = nodes[manual_guidance_node_index]
	var node_time := maxf(0.0, float(node.get("time_offset", 0.0)))
	var remaining_time := manual_guidance_start_time + node_time - float(simulation.get("sim_time"))
	var burn_vector := manual_guidance_burn_vector
	var target_delta_v := manual_guidance_target_delta_v
	var tracking := bool(simulation.get("manual_burn_tracking_enabled"))
	if remaining_time <= 0.0 and not tracking and not manual_guidance_completed:
		simulation.set("manual_burn_target_vector", burn_vector)
		simulation.set("manual_burn_accumulated_vector", Vector2.ZERO)
		simulation.set("manual_burn_tracking_enabled", true)
		tracking = true
	var accumulated: Vector2 = simulation.get("manual_burn_accumulated_vector")
	var achieved := maxf(0.0, accumulated.dot(burn_vector.normalized())) if target_delta_v > 0.0 else 0.0
	var cross_track := absf(accumulated.cross(burn_vector.normalized()))
	var desired_rotation := burn_vector.angle() - Vector2.UP.angle()
	var heading_error := rad_to_deg(angle_difference(float(simulation.get("rotation_angle")), desired_rotation))
	var timing := "BURN IN %.1f s" % remaining_time if remaining_time > 0.0 else "BURN WINDOW OPEN"
	var tolerance := maxf(0.5, target_delta_v * 0.01)
	var cross_track_tolerance := maxf(1.0, target_delta_v * 0.03)
	var vector_complete := achieved >= target_delta_v - tolerance and cross_track <= cross_track_tolerance
	var burn_status := "CUT THRUST  •  TARGET ΔV REACHED" if vector_complete else "OFF-AXIS  •  CORRECT BURN VECTOR" if achieved >= target_delta_v - tolerance else "BURN TRACKING" if tracking else "READY"
	if not bool(simulation.get("thrust_key_down")) and vector_complete:
		simulation.set("manual_burn_tracking_enabled", false)
		manual_guidance_completed = true
		burn_status = "NODE BURN COMPLETE"
	if manual_guidance_completed:
		burn_status = "NODE BURN COMPLETE"
	manual_guidance_report.text = "MANUAL NODE %d  •  %s  •  %s\nREQUIRED ΔV: %.1f m/s  •  DELIVERED: %.1f m/s  •  CROSS-TRACK: %.1f m/s\nHEADING ERROR: %+.1f°  •  BURN VECTOR: %.1f° FROM PROGRADE\nRotate with Q/E to reduce heading error, press W to thrust and S to cut off. The computer never steers or fires the engine." % [
		manual_guidance_node_index + 1,
		timing,
		burn_status,
		target_delta_v,
		achieved,
		cross_track,
		heading_error,
		manual_guidance_angle_from_prograde
	]


func _replan_manual_transfer() -> void:
	if not is_instance_valid(simulation) or bool(simulation.get("autopilot_enabled")):
		return
	var manual_plan: Dictionary = simulation.get("manual_flight_plan")
	if manual_plan.is_empty() or not bool(manual_plan.get("active", false)) or str(manual_plan.get("phase", "")) != "TRANSFER_COAST":
		return
	var target_id := int(manual_plan.get("target_id", -999))
	var target_name := str(manual_plan.get("target_name", ""))
	var target_altitude := float(manual_plan.get("target_altitude", 200000.0))
	var available := FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if bool(simulation.get("infinite_weightless_fuel")) else FlightComputer.available_delta_v(rocket_design, int(simulation.get("stage_index")), float(simulation.get("fuel"))) * (1.0 - float(simulation.get("autopilot_safety_margin")))
	var precise_position: PackedFloat64Array = simulation.get("rocket_position_precise")
	var current_position: Vector2 = simulation.get("rocket_position")
	var current_velocity: Vector2 = simulation.get("velocity")
	var result := FlightComputer.simulated_transfer_search_precise(precise_position, current_velocity, float(simulation.get("sim_time")), target_id, available, float(simulation.get("autopilot_speed_priority")), false, target_altitude)
	if not bool(result.get("valid", false)):
		manual_guidance_report.text = "MID-COURSE REPLAN FAILED  •  " + str(result.get("reason", "No feasible correction trajectory was found."))
		return
	var correction: Dictionary = result.duplicate(true)
	correction["target_id"] = target_id
	correction["target_name"] = target_name
	correction["target_altitude"] = target_altitude
	correction["planned_at_time"] = float(simulation.get("sim_time"))
	correction["planned_position"] = current_position
	correction["planned_velocity"] = current_velocity
	correction["local"] = false
	var direction: Vector2 = Vector2(correction.get("departure_direction", Vector2.ZERO)).normalized()
	var delta_v := float(correction.get("departure_delta_v", 0.0))
	if direction == Vector2.ZERO or delta_v <= 0.0:
		manual_guidance_report.text = "MID-COURSE REPLAN FAILED  •  The solver returned no usable correction burn."
		return
	manual_plan["phase"] = "DEPARTURE_BURN"
	manual_plan["departure_time"] = float(simulation.get("sim_time"))
	manual_plan["departure_direction"] = direction
	manual_plan["departure_delta_v"] = delta_v
	manual_plan["transfer_time"] = float(correction.get("transfer_time", 0.0))
	manual_plan["planned_position"] = current_position
	manual_plan["planned_velocity"] = current_velocity
	manual_plan["transfer_start_time"] = -1.0
	manual_plan.erase("target_radius")
	_arm_manual_plan_burn(manual_plan, "DEPARTURE_BURN", direction * delta_v, delta_v)
	simulation.set("manual_flight_plan", manual_plan)
	navigation_plan = correction
	navigation_plan_valid = true
	_update_navigation_plot()
	manual_guidance_report.text = "MID-COURSE CORRECTION SOLVED  •  NEW ΔV %.1f m/s  •  NEW TRANSFER %.1f DAYS. The correction is armed for manual execution; the previous trajectory has been replaced." % [delta_v, float(correction.get("transfer_time", 0.0)) / 86400.0]
	_refresh_navigation_state()

func _scan_launch_windows() -> void:
	if not is_instance_valid(simulation) or bool(simulation.get("autopilot_enabled")):
		return
	var target_id := navigation_moon_dropdown.get_selected_id()
	var target_name := FlightComputer.target_body_name(target_id)
	var target_altitude := navigation_altitude_input.value * 1000.0
	var current_position: Vector2 = simulation.get("rocket_position")
	var current_body: Dictionary = simulation.call("_nearest_body_state", current_position)
	var relative_position_now := current_position - Vector2(current_body.get("position", Vector2.ZERO))
	var relative_velocity_now: Vector2 = simulation.get("velocity") - Vector2(current_body.get("velocity", Vector2.ZERO))
	var current_orbit := FlightComputer.orbital_state(relative_position_now, relative_velocity_now, FlightComputer.G * float(current_body.get("mass", 0.0)))
	var safe_altitude := FlightComputer.minimum_safe_orbit_altitude(str(current_body.get("name", "")), float(current_body.get("radius", 0.0)))
	var stable_orbit := float(current_body.get("distance", INF)) <= float(current_body.get("soi", 0.0)) and bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current_body.get("radius", 0.0)) + safe_altitude and float(current_orbit.get("apoapsis", INF)) < float(current_body.get("radius", 0.0)) + FlightComputer.maximum_stable_orbit_altitude(float(current_body.get("radius", 0.0)), float(current_body.get("soi", 0.0)))
	if not stable_orbit:
		navigation_report.text = "LAUNCH-WINDOW SEARCH REQUIRES A SAFE PARKING ORBIT AROUND THE CURRENT BODY."
		return
	var available := FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if bool(simulation.get("infinite_weightless_fuel")) else FlightComputer.available_delta_v(rocket_design, int(simulation.get("stage_index")), float(simulation.get("fuel"))) * (1.0 - float(simulation.get("autopilot_safety_margin")))
	navigation_report.text = "SCANNING UP TO 540 DAYS OF DEPARTURE WINDOWS. This is a more expensive search than the immediate-transfer solver."
	launch_window_button.disabled = true
	var precise_position: PackedFloat64Array = simulation.get("rocket_position_precise")
	var result := FlightComputer.scan_launch_windows(
		current_position,
		Vector2(simulation.get("velocity")),
		float(simulation.get("sim_time")),
		target_id,
		available,
		float(simulation.get("autopilot_speed_priority")),
		540,
		30,
		target_altitude,
		precise_position
	)
	launch_window_button.disabled = false
	if not bool(result.get("valid", false)):
		navigation_plan_valid = false
		navigation_engage_button.disabled = true
		manual_navigation_button.disabled = true
		navigation_report.text = "NO FEASIBLE DEPARTURE WINDOW FOUND.\n" + str(result.get("reason", "The scanned windows did not produce a valid route."))
		return
	var best_window: Dictionary = result.get("best", {})
	navigation_plan = best_window.duplicate(true)
	navigation_plan["target_id"] = target_id
	navigation_plan["target_name"] = target_name
	navigation_plan["target_altitude"] = target_altitude
	navigation_plan["local"] = false
	navigation_plan_valid = true
	var wait_days := float(navigation_plan.get("departure_wait_days", 0.0))
	navigation_report.text = "BEST DEPARTURE WINDOW FOUND  •  %s\nWAIT: %.1f DAYS  •  DEPARTURE ΔV: %.0f m/s  •  ARRIVAL CAPTURE: %.0f m/s\nTOTAL ΔV: %.0f m/s  •  TRANSFER: %.1f DAYS  •  DATES CHECKED: %d\nThe manual plan will wait for this window, then guide you through departure and arrival burns. No engine control is automated." % [
		target_name.to_upper(),
		wait_days,
		float(navigation_plan.get("departure_delta_v", 0.0)),
		float(navigation_plan.get("capture_delta_v", 0.0)),
		float(navigation_plan.get("total_delta_v", 0.0)),
		float(navigation_plan.get("transfer_time", 0.0)) / 86400.0,
		int(result.get("dates_checked", 0))
	]
	navigation_plot.visible = true
	_update_navigation_plot()
	_refresh_navigation_state()

func _toggle_manual_destination_plan() -> void:
	if not is_instance_valid(simulation):
		return
	var existing: Dictionary = simulation.get("manual_flight_plan")
	if not existing.is_empty() and bool(existing.get("active", false)):
		simulation.set("manual_flight_plan", {})
		simulation.set("manual_burn_tracking_enabled", false)
		simulation.set("manual_burn_target_vector", Vector2.ZERO)
		simulation.set("manual_burn_accumulated_vector", Vector2.ZERO)
		simulation.set("thrust_key_down", false)
		manual_guidance_report.text = "MANUAL DESTINATION PLAN CANCELLED."
		_refresh_navigation_state()
		return
	_start_manual_destination_plan()

func _start_manual_destination_plan() -> void:
	if not navigation_plan_valid or bool(simulation.get("autopilot_enabled")) or bool(simulation.get("landed")) or bool(simulation.get("crashed")):
		return
	var current: Dictionary = simulation.call("_nearest_body_state", simulation.get("rocket_position"))
	var relative_position_now: Vector2 = simulation.get("rocket_position") - Vector2(current.get("position", Vector2.ZERO))
	var relative_velocity_now: Vector2 = simulation.get("velocity") - Vector2(current.get("velocity", Vector2.ZERO))
	var current_orbit := FlightComputer.orbital_state(relative_position_now, relative_velocity_now, FlightComputer.G * float(current.get("mass", 0.0)))
	var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(str(current.get("name", "")), float(current.get("radius", 0.0)))
	var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(float(current.get("radius", 0.0)), float(current.get("soi", 0.0)))
	var stable_orbit := float(current.get("distance", INF)) <= float(current.get("soi", 0.0)) and bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current.get("radius", 0.0)) + minimum_altitude and float(current_orbit.get("apoapsis", INF)) < float(current.get("radius", 0.0)) + maximum_altitude
	var deep_space_start := bool(navigation_plan.get("deep_space_start", false)) and not bool(navigation_plan.get("needs_parking_orbit", false)) and not bool(navigation_plan.get("needs_window_search", false))
	if not stable_orbit and not deep_space_start:
		manual_guidance_report.text = "MANUAL DESTINATION FLIGHT REQUIRES A SAFE PARKING ORBIT OR A VALID DEEP-SPACE TRANSFER SOLUTION. Establish a parking orbit first if the current trajectory needs recovery."
		return
	manual_guidance_node_index = -1
	manual_guidance_completed = false
	simulation.set("manual_burn_tracking_enabled", false)
	simulation.set("manual_burn_accumulated_vector", Vector2.ZERO)
	simulation.set("thrust_key_down", false)
	var plan := navigation_plan.duplicate(true)
	if not bool(plan.get("local", false)):
		var now_for_plan := float(simulation.get("sim_time"))
		var departure_for_plan := float(plan.get("departure_time_seconds", plan.get("planned_at_time", now_for_plan)))
		var plan_age := absf(now_for_plan - float(plan.get("planned_at_time", -INF)))
		var planned_position: Vector2 = plan.get("planned_position", Vector2.INF)
		var planned_velocity: Vector2 = plan.get("planned_velocity", Vector2.INF)
		if departure_for_plan <= now_for_plan + 2.0 and (plan_age > 2.0 or planned_position.distance_to(simulation.get("rocket_position")) > 20000.0 or planned_velocity.distance_to(simulation.get("velocity")) > 5.0):
			_calculate_destination_plan()
			if not navigation_plan_valid:
				return
			plan = navigation_plan.duplicate(true)
	var now := float(simulation.get("sim_time"))
	var manual_plan: Dictionary = {
		"active": true,
		"target_id": int(plan.get("target_id", -999)),
		"target_name": str(plan.get("target_name", "")),
		"target_altitude": float(plan.get("target_altitude", 200000.0)),
		"phase": "LOCAL_BURN" if bool(plan.get("local", false)) else "WAIT_DEPARTURE",
		"departure_time": float(plan.get("departure_time_seconds", plan.get("planned_at_time", now))),
		"transfer_time": float(plan.get("transfer_time", 0.0)),
		"departure_direction": Vector2(plan.get("departure_direction", Vector2.ZERO)).normalized(),
		"departure_delta_v": float(plan.get("departure_delta_v", 0.0)),
		"planned_position": Vector2(plan.get("planned_position", simulation.get("rocket_position"))),
		"planned_velocity": Vector2(plan.get("planned_velocity", simulation.get("velocity"))),
		"transfer_start_time": -1.0,
		"burn_kind": "",
		"burn_delta_v": 0.0,
		"previous_radial_speed": -0.001
	}
	if bool(plan.get("local", false)):
		var local_burn := FlightComputer.target_radius_burn(relative_position_now, relative_velocity_now, float(current.get("radius", 0.0)) + float(plan.get("target_altitude", 200000.0)), FlightComputer.G * float(current.get("mass", 0.0)))
		if not bool(local_burn.get("valid", false)):
			manual_guidance_report.text = "THE LOCAL ORBIT CHANGE HAS NO VALID MANUAL BURN SOLUTION."
			return
		manual_plan["target_radius"] = float(local_burn.get("target_radius", 0.0))
		_arm_manual_plan_burn(manual_plan, "LOCAL_BURN", Vector2(local_burn.get("burn_vector", Vector2.ZERO)), float(local_burn.get("delta_v", 0.0)))
	else:
		if Vector2(manual_plan["departure_direction"]) == Vector2.ZERO or float(manual_plan["departure_delta_v"]) <= 0.0:
			manual_guidance_report.text = "THE DESTINATION SOLUTION DOES NOT CONTAIN A VALID DEPARTURE BURN."
			return
		if float(manual_plan["departure_time"]) <= now + 2.0:
			_arm_manual_plan_burn(manual_plan, "DEPARTURE_BURN", Vector2(manual_plan["departure_direction"]) * float(manual_plan["departure_delta_v"]), float(manual_plan["departure_delta_v"]))
	simulation.set("manual_flight_plan", manual_plan)
	simulation.set("autopilot_enabled", false)
	simulation.set("guidance_enabled", false)
	simulation.set("thrust_key_down", false)
	manual_guidance_node_index = -1
	simulation.set("manual_burn_tracking_enabled", false)
	_refresh_navigation_state()
	_update_manual_guidance()

func _arm_manual_plan_burn(plan: Dictionary, phase: String, burn_vector: Vector2, delta_v: float) -> void:
	if burn_vector.length() < 0.1 or delta_v < 0.1:
		plan["phase"] = "FAILED"
		plan["reason"] = "The planned burn is too small or invalid."
		return
	plan["phase"] = phase
	plan["burn_kind"] = phase
	plan["burn_delta_v"] = delta_v
	plan["burn_vector"] = burn_vector
	simulation.set("manual_burn_tracking_enabled", true)
	simulation.set("manual_burn_target_vector", burn_vector)
	simulation.set("manual_burn_accumulated_vector", Vector2.ZERO)
	simulation.set("thrust_key_down", false)

func _update_manual_flight_plan() -> void:
	var plan: Dictionary = simulation.get("manual_flight_plan")
	if plan.is_empty():
		return
	if not bool(plan.get("active", false)) and str(plan.get("phase", "")) not in ["COMPLETE", "FAILED"]:
		return
	var now := float(simulation.get("sim_time"))
	var phase := str(plan.get("phase", ""))
	if phase == "WAIT_DEPARTURE":
		var wait_remaining := float(plan.get("departure_time", now)) - now
		if wait_remaining <= 0.0:
			var planned_position: Vector2 = plan.get("planned_position", Vector2.ZERO)
			var planned_velocity: Vector2 = plan.get("planned_velocity", Vector2.ZERO)
			var state_matches := planned_position.distance_to(simulation.get("rocket_position")) <= 50000.0 and planned_velocity.distance_to(simulation.get("velocity")) <= 25.0
			if not state_matches:
				plan["phase"] = "FAILED"
				plan["active"] = false
				plan["reason"] = "The spacecraft missed the predicted departure state. Recalculate the launch window."
				simulation.set("manual_flight_plan", plan)
				phase = "FAILED"
			else:
				_arm_manual_plan_burn(plan, "DEPARTURE_BURN", Vector2(plan.get("departure_direction", Vector2.ZERO)) * float(plan.get("departure_delta_v", 0.0)), float(plan.get("departure_delta_v", 0.0)))
				simulation.set("manual_flight_plan", plan)
				phase = str(plan.get("phase", ""))
		else:
			manual_guidance_report.text = "MANUAL FLIGHT PLAN  •  %s\nDEPARTURE WINDOW OPENS IN %.1f DAYS. No automatic steering or thrust will occur." % [str(plan.get("target_name", "TARGET")).to_upper(), wait_remaining / 86400.0]
			return
	if phase in ["DEPARTURE_BURN", "LOCAL_BURN", "LOCAL_CIRCULARISE", "ARRIVAL_BURN", "ARRIVAL_CIRCULARISE"]:
		var target_vector: Vector2 = simulation.get("manual_burn_target_vector")
		var target_delta_v := float(plan.get("burn_delta_v", 0.0))
		var accumulated: Vector2 = simulation.get("manual_burn_accumulated_vector")
		var direction := target_vector.normalized()
		var achieved := maxf(0.0, accumulated.dot(direction))
		var cross_track := absf(accumulated.cross(direction))
		var tolerance := maxf(0.5, target_delta_v * 0.01)
		var vector_tolerance := maxf(1.0, target_delta_v * 0.03)
		var vector_complete := achieved >= target_delta_v - tolerance and cross_track <= vector_tolerance
		if not bool(simulation.get("thrust_key_down")) and vector_complete:
			simulation.set("manual_burn_tracking_enabled", false)
			if phase == "DEPARTURE_BURN":
				plan["phase"] = "TRANSFER_COAST"
				plan["transfer_start_time"] = now
			elif phase == "LOCAL_BURN":
				plan["phase"] = "LOCAL_COAST"
			elif phase == "ARRIVAL_BURN":
				plan["phase"] = "ARRIVAL_COAST"
			elif phase in ["LOCAL_CIRCULARISE", "ARRIVAL_CIRCULARISE"]:
				var body_state: Dictionary = simulation.call("_surface_body_state", str(plan.get("target_name", "")))
				var body_position: Vector2 = simulation.get("rocket_position") - Vector2(body_state.get("position", Vector2.ZERO))
				var body_velocity: Vector2 = simulation.get("velocity") - Vector2(body_state.get("velocity", Vector2.ZERO))
				var body_mu := FlightComputer.G * float(body_state.get("mass", 0.0))
				var final_orbit := FlightComputer.orbital_state(body_position, body_velocity, body_mu)
				var target_radius := float(plan.get("target_radius", 0.0))
				var orbit_tolerance := maxf(5000.0, target_radius * 0.001)
				var orbit_complete := bool(final_orbit.get("bound", false)) and absf(float(final_orbit.get("periapsis", INF)) - target_radius) <= orbit_tolerance and absf(float(final_orbit.get("apoapsis", INF)) - target_radius) <= orbit_tolerance
				if orbit_complete:
					plan["phase"] = "COMPLETE"
					plan["active"] = false
				elif bool(final_orbit.get("bound", false)) and float(final_orbit.get("periapsis", 0.0)) > float(body_state.get("radius", 0.0)) + FlightComputer.minimum_safe_orbit_altitude(str(plan.get("target_name", "")), float(body_state.get("radius", 0.0))):
					plan["phase"] = "LOCAL_COAST" if phase == "LOCAL_CIRCULARISE" else "ARRIVAL_COAST"
				else:
					plan["phase"] = "FAILED"
					plan["active"] = false
					plan["reason"] = "The executed burn did not establish a safe bound orbit."
			simulation.set("manual_flight_plan", plan)
			phase = str(plan.get("phase", ""))
		else:
			var desired_rotation := target_vector.angle() - Vector2.UP.angle()
			var heading_error := rad_to_deg(angle_difference(float(simulation.get("rotation_angle")), desired_rotation))
			var burn_status := "CUT THRUST  •  TARGET ΔV REACHED" if vector_complete else "OFF-AXIS  •  CORRECT BURN VECTOR" if achieved >= target_delta_v - tolerance and cross_track > vector_tolerance else "BURN IN PROGRESS"
			manual_guidance_report.text = "MANUAL FLIGHT PLAN  •  %s\n%s  •  REQUIRED ΔV %.1f m/s  •  DELIVERED %.1f m/s  •  CROSS-TRACK %.1f m/s\nHEADING ERROR %+.1f°. Rotate with Q/E, thrust with W and cut off with S. Engine control remains entirely manual." % [
				str(plan.get("target_name", "TARGET")).to_upper(),
				burn_status,
				target_delta_v,
				achieved,
				cross_track,
				heading_error
			]
			return
	if phase == "LOCAL_COAST":
		var local_state: Dictionary = simulation.call("_nearest_body_state", simulation.get("rocket_position"))
		var local_name := str(plan.get("target_name", ""))
		if str(local_state.get("name", "")) != local_name:
			plan["phase"] = "FAILED"
			plan["active"] = false
			plan["reason"] = "The spacecraft left the planned local body's sphere of influence."
		else:
			var local_position: Vector2 = simulation.get("rocket_position") - Vector2(local_state.get("position", Vector2.ZERO))
			var local_velocity: Vector2 = simulation.get("velocity") - Vector2(local_state.get("velocity", Vector2.ZERO))
			var local_mu := FlightComputer.G * float(local_state.get("mass", 0.0))
			var local_orbit := FlightComputer.orbital_state(local_position, local_velocity, local_mu)
			var target_radius := float(plan.get("target_radius", 0.0))
			var apsis_tolerance := FlightComputer.orbit_radius_tolerance(target_radius)
			var radial_tolerance := maxf(0.5, FlightComputer.circular_orbit_speed(target_radius, local_mu) * 0.0002)
			if not bool(local_orbit.get("bound", false)) or float(local_orbit.get("periapsis", 0.0)) <= float(local_state.get("radius", 0.0)):
				plan["phase"] = "FAILED"
				plan["active"] = false
				plan["reason"] = "The local transfer orbit became unsafe or unbound."
			elif absf(local_position.length() - target_radius) <= apsis_tolerance and absf(float(local_orbit.get("radial_speed", 0.0))) <= radial_tolerance:
				var local_circularise := FlightComputer.target_radius_burn(local_position, local_velocity, target_radius, local_mu)
				if bool(local_circularise.get("valid", false)) and float(local_circularise.get("delta_v", INF)) > FlightComputer.BURN_COMPLETION_TOLERANCE:
					_arm_manual_plan_burn(plan, "LOCAL_CIRCULARISE", Vector2(local_circularise.get("burn_vector", Vector2.ZERO)), float(local_circularise.get("delta_v", INF)))
				else:
					plan["phase"] = "COMPLETE"
					plan["active"] = false
		simulation.set("manual_flight_plan", plan)
		phase = str(plan.get("phase", ""))
	if phase == "TRANSFER_COAST":
		var target_name := str(plan.get("target_name", ""))
		var target_state: Dictionary = simulation.call("_surface_body_state", target_name)
		if target_state.is_empty():
			plan["phase"] = "FAILED"
			plan["active"] = false
			plan["reason"] = "Destination body data became unavailable."
		else:
			var target_position: Vector2 = simulation.get("rocket_position") - Vector2(target_state.get("position", Vector2.ZERO))
			var target_velocity: Vector2 = simulation.get("velocity") - Vector2(target_state.get("velocity", Vector2.ZERO))
			var target_distance := target_position.length()
			var target_soi := float(target_state.get("soi", 0.0))
			var target_orbit := FlightComputer.orbital_state(target_position, target_velocity, FlightComputer.G * float(target_state.get("mass", 0.0)))
			var arrival_radial_speed := float(target_orbit.get("radial_speed", 0.0))
			if target_distance <= target_soi:
				if arrival_radial_speed < 0.0:
					var capture := FlightComputer.arrival_capture_burn(target_position, target_velocity, FlightComputer.G * float(target_state.get("mass", 0.0)), float(target_state.get("radius", 0.0)), float(plan.get("target_altitude", 100000.0)), FlightComputer.minimum_safe_orbit_altitude(target_name, float(target_state.get("radius", 0.0))))
					if bool(capture.get("valid", false)):
						_arm_manual_plan_burn(plan, "ARRIVAL_BURN", Vector2(capture.get("burn_vector", Vector2.ZERO)), float(capture.get("delta_v", INF)))
						plan["target_radius"] = float(capture.get("target_radius", 0.0))
					else:
						plan["phase"] = "FAILED"
						plan["active"] = false
						plan["reason"] = str(capture.get("reason", "No safe arrival capture solution exists."))
				else:
					plan["phase"] = "FAILED"
					plan["active"] = false
					plan["reason"] = "The spacecraft passed the destination's capture region. A mid-course correction is required."
			elif float(plan.get("transfer_time", 0.0)) > 0.0 and now - float(plan.get("transfer_start_time", now)) > float(plan.get("transfer_time", 0.0)) * 1.5:
				plan["phase"] = "FAILED"
				plan["active"] = false
				plan["reason"] = "The predicted arrival window was missed. A mid-course correction is required."
		simulation.set("manual_flight_plan", plan)
		phase = str(plan.get("phase", ""))
	if phase == "ARRIVAL_COAST":
		var arrival_state: Dictionary = simulation.call("_surface_body_state", str(plan.get("target_name", "")))
		if not arrival_state.is_empty():
			var arrival_position: Vector2 = simulation.get("rocket_position") - Vector2(arrival_state.get("position", Vector2.ZERO))
			var arrival_velocity: Vector2 = simulation.get("velocity") - Vector2(arrival_state.get("velocity", Vector2.ZERO))
			var arrival_orbit := FlightComputer.orbital_state(arrival_position, arrival_velocity, FlightComputer.G * float(arrival_state.get("mass", 0.0)))
			var radial_speed := float(arrival_orbit.get("radial_speed", 0.0))
			var periapsis := float(arrival_orbit.get("periapsis", INF))
			var target_radius := float(plan.get("target_radius", 0.0))
			var at_periapsis := radial_speed >= 0.0 and absf(arrival_position.length() - periapsis) <= FlightComputer.orbit_radius_tolerance(target_radius)
			if at_periapsis and target_radius > 0.0:
				var circularise := FlightComputer.target_radius_burn(arrival_position, arrival_velocity, target_radius, FlightComputer.G * float(arrival_state.get("mass", 0.0)))
				if bool(circularise.get("valid", false)) and float(circularise.get("delta_v", INF)) > FlightComputer.BURN_COMPLETION_TOLERANCE:
					_arm_manual_plan_burn(plan, "ARRIVAL_CIRCULARISE", Vector2(circularise.get("burn_vector", Vector2.ZERO)), float(circularise.get("delta_v", INF)))
				else:
					plan["phase"] = "COMPLETE"
					plan["active"] = false
		simulation.set("manual_flight_plan", plan)
		phase = str(plan.get("phase", ""))
	if phase == "COMPLETE":
		manual_guidance_report.text = "MANUAL FLIGHT PLAN COMPLETE  •  TARGET ORBIT REACHED. Verify periapsis and apoapsis in the orbital readout."
	elif phase == "FAILED":
		manual_guidance_report.text = "MANUAL FLIGHT PLAN FAILED  •  " + str(plan.get("reason", "The planned trajectory is no longer valid."))
	else:
		var target_name := str(plan.get("target_name", "TARGET"))
		var target_state: Dictionary = simulation.call("_surface_body_state", target_name)
		var range_text := ""
		if not target_state.is_empty():
			range_text = "  •  RANGE %.0f km" % (simulation.get("rocket_position").distance_to(Vector2(target_state.get("position", Vector2.ZERO))) / 1000.0)
		manual_guidance_report.text = "MANUAL FLIGHT PLAN  •  %s  •  %s%s\nNo automatic steering or thrust is used." % [target_name.to_upper(), phase.replace("_", " "), range_text]


func _add_node() -> void:
	if not is_instance_valid(simulation):
		return
	var next_time := 0.0
	if not nodes.is_empty():
		next_time = float(nodes[nodes.size() - 1].get("time_offset", 0.0)) + 30.0
	if has_route_target:
		next_time = maxf(next_time, route_duration + 30.0)
	nodes.append({"time_offset": next_time, "prograde": 0.0, "radial": 0.0})
	selected_node_index = nodes.size() - 1
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()
	call_deferred("_focus_node_editor")

func _focus_node_editor() -> void:
	if is_instance_valid(interface_scroll) and is_instance_valid(node_editor):
		interface_scroll.ensure_control_visible(node_editor)

func _remove_node() -> void:
	if selected_node_index < 0 or selected_node_index >= nodes.size():
		return
	manual_guidance_node_index = -1
	manual_guidance_completed = false
	simulation.set("manual_burn_tracking_enabled", false)
	if selected_node_index == 0:
		_invalidate_route_solution()
	nodes.remove_at(selected_node_index)
	selected_node_index = mini(selected_node_index, nodes.size() - 1)
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _change_route_duration(hours: float) -> void:
	route_duration = hours * 3600.0
	if has_route_target:
		if nodes.size() > 1:
			_invalidate_route_solution()
			_update_manoeuvre()
		else:
			_calculate_route()

func _clear_route_target() -> void:
	target_coordinates_loading = true
	target_x_input.value = 0.0
	target_y_input.value = 0.0
	target_coordinates_loading = false
	has_route_target = false
	route_solution_dirty = false
	route_delta_v = 0.0
	route_status = "NO DESTINATION SELECTED"
	nodes.clear()
	selected_node_index = -1
	_rebuild_node_list()
	_load_selected_node()
	_update_manoeuvre()

func _invalidate_route_solution() -> void:
	if has_route_target:
		route_solution_dirty = true
		route_delta_v = INF
		route_status = "MANOEUVRE EDITED  •  DRAG DESTINATION TO RECALCULATE"

func _set_route_target(world_position: Vector2) -> void:
	if gravitational_parameter <= 0.0 or relative_position.length() <= 1.0:
		return
	if not has_route_target or route_solution_dirty:
		nodes.clear()
		selected_node_index = -1
		route_target = world_position
		has_route_target = true
	route_target = world_position
	target_coordinates_loading = true
	target_x_input.value = world_position.x / 1000.0
	target_y_input.value = world_position.y / 1000.0
	target_coordinates_loading = false
	route_solution_dirty = false
	var body_radius := float(current_body.get("radius", 0.0))
	var sphere_of_influence := float(current_body.get("soi", INF))
	if route_target.length() <= body_radius:
		route_delta_v = INF
		route_status = "DESTINATION IS INSIDE THE BODY"
		_update_manoeuvre()
		return
	if route_target.length() >= sphere_of_influence:
		route_delta_v = INF
		route_status = "DESTINATION IS OUTSIDE THIS BODY'S SPHERE OF INFLUENCE"
		_update_manoeuvre()
		return
	_calculate_route()

func _apply_target_coordinates() -> void:
	if target_coordinates_loading:
		return
	_set_route_target(Vector2(target_x_input.value, target_y_input.value) * 1000.0)

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
	route_solution_dirty = false
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
	if index < 0 or index >= nodes.size() or planned_path.size() < 2 or planned_path_times.size() != planned_path.size():
		return
	manual_guidance_node_index = -1
	manual_guidance_completed = false
	simulation.set("manual_burn_tracking_enabled", false)
	if index == 0:
		_invalidate_route_solution()
	var nearest_index := 0
	var nearest_distance := INF
	for point_index in range(planned_path.size()):
		var distance: float = planned_path[point_index].distance_squared_to(world_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = point_index
	var time_offset: float = planned_path_times[nearest_index]
	var before_index := maxi(0, nearest_index - 1)
	var after_index := mini(planned_path.size() - 1, nearest_index + 1)
	var burn_position: Vector2 = planned_path[nearest_index]
	var sample_duration: float = planned_path_times[after_index] - planned_path_times[before_index]
	var burn_velocity: Vector2 = relative_velocity
	if sample_duration > 0.001:
		burn_velocity = (planned_path[after_index] - planned_path[before_index]) / sample_duration
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
		var candidate: Dictionary = nodes[node_index]
		if is_equal_approx(float(candidate.get("time_offset", 0.0)), time_offset) and is_equal_approx(float(candidate.get("prograde", 0.0)), float(node.get("prograde", 0.0))) and is_equal_approx(float(candidate.get("radial", 0.0)), float(node.get("radial", 0.0))):
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
	manual_guidance_node_index = -1
	manual_guidance_completed = false
	simulation.set("manual_burn_tracking_enabled", false)
	if selected_node_index == 0:
		_invalidate_route_solution()
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
	planned_path = PackedVector2Array([relative_position])
	planned_path_times = PackedFloat64Array([0.0])
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
			for sample_index in range(coast_steps):
				planned_path_times.append(elapsed + coast_duration * float(sample_index + 1) / float(coast_steps))
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
	var remaining_steps: int = 1440
	var final_steps: int = clampi(int(ceil(final_duration / 120.0)), 1, remaining_steps)
	var final_result: Dictionary = _append_integrated_path(planned_path, plan_position, plan_velocity, final_duration, remaining_steps)
	planned_path = final_result.get("path", planned_path)
	for sample_index in range(final_steps):
		planned_path_times.append(elapsed + final_duration * float(sample_index + 1) / float(final_steps))
	if has_route_target:
		var body_radius := float(current_body.get("radius", 0.0))
		for point in planned_path:
			if point.length() <= body_radius:
				route_delta_v = INF
				route_status = "PREDICTED ROUTE INTERSECTS THE BODY"
				break
	orbit_plot.set_paths(current_path, planned_path, markers, float(current_body.get("radius", 0.0)), relative_position, route_target, has_route_target)
	if not nodes.is_empty():
		var periapsis_altitude: float = (float(final_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0
		var apoapsis_altitude: float = (float(final_orbit.get("apoapsis", INF)) - float(current_body.get("radius", 0.0))) / 1000.0
		var planned_vehicle_delta_v_text := "UNLIMITED • MASSLESS FUEL" if bool(simulation.get("infinite_weightless_fuel")) else "%.2f km/s" % (available_delta_v / 1000.0)
		state_report.text = "BODY: %s   ALTITUDE: %.1f km   SPEED: %.0f m/s\nCURRENT ORBIT: Pe %.1f km   Ap %s\nFINAL PLANNED ORBIT: Pe %.1f km   Ap %s\nVEHICLE ΔV: %s" % [
			str(current_body.get("name", "Unknown")),
			(relative_position.length() - float(current_body.get("radius", 0.0))) / 1000.0,
			relative_velocity.length(),
			(float(current_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0,
			"UNBOUND" if not bool(current_orbit.get("bound", false)) else "%.1f km" % ((float(current_orbit.get("apoapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0),
			periapsis_altitude,
			"UNBOUND" if not bool(final_orbit.get("bound", false)) else "%.1f km" % apoapsis_altitude,
			planned_vehicle_delta_v_text
		]
	else:
		var idle_vehicle_delta_v_text := "UNLIMITED • MASSLESS FUEL" if bool(simulation.get("infinite_weightless_fuel")) else "%.2f km/s" % (available_delta_v / 1000.0)
		state_report.text = "BODY: %s   ALTITUDE: %.1f km   SPEED: %.0f m/s\nCURRENT ORBIT: Pe %.1f km   Ap %s\nNO MANOEUVRE NODES PLANNED\nVEHICLE ΔV: %s" % [
			str(current_body.get("name", "Unknown")),
			(relative_position.length() - float(current_body.get("radius", 0.0))) / 1000.0,
			relative_velocity.length(),
			(float(current_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0,
			"UNBOUND" if not bool(current_orbit.get("bound", false)) else "%.1f km" % ((float(current_orbit.get("apoapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0),
			idle_vehicle_delta_v_text
		]

func _update_manoeuvre() -> void:
	if not is_instance_valid(simulation) or gravitational_parameter <= 0.0:
		return
	var active_stage: int = int(simulation.get("stage_index"))
	var remaining_fuel: float = float(simulation.get("fuel"))
	available_delta_v = FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if bool(simulation.get("infinite_weightless_fuel")) else FlightComputer.available_delta_v(rocket_design, active_stage, remaining_fuel)
	var total_planned_delta_v := 0.0
	for node in nodes:
		total_planned_delta_v += Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length()
	_build_prediction_paths()
	var landed_state: bool = bool(simulation.get("landed"))
	var crashed_state: bool = bool(simulation.get("crashed"))
	var valid_nodes: bool = not nodes.is_empty() and (not has_route_target or (is_finite(route_delta_v) and not route_solution_dirty))
	for node in nodes:
		if Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length() < 0.1:
			valid_nodes = false
	var body_radius := float(current_body.get("radius", 0.0))
	var safe_orbit_altitude := maxf(70000.0, PlanetarySystem.planetary_atmosphere_height(str(current_body.get("name", ""))) + 50000.0)
	var current_orbit := FlightComputer.orbital_state(relative_position, relative_velocity, gravitational_parameter)
	var in_sphere_of_influence := float(current_body.get("distance", INF)) <= float(current_body.get("soi", 0.0))
	var stable_orbit := in_sphere_of_influence and bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) >= body_radius + safe_orbit_altitude
	var maneuver_autopilot: bool = bool(simulation.get("autopilot_enabled")) and str(simulation.get("autopilot_target_mode")) == "MANEUVER"
	var route_active: bool = maneuver_autopilot and str(simulation.get("autopilot_phase")) in ["ROUTE_COAST", "ROUTE_BURN"]
	var route_complete: bool = maneuver_autopilot and str(simulation.get("autopilot_phase")) == "COMPLETE"
	var exceeds_delta_v: bool = total_planned_delta_v > available_delta_v
	var manual_plan: Dictionary = simulation.get("manual_flight_plan")
	var manual_plan_active := not manual_plan.is_empty() and bool(manual_plan.get("active", false))
	var manual_node_active := manual_guidance_node_index >= 0
	var can_send := not landed_state and not crashed_state and stable_orbit and valid_nodes and not exceeds_delta_v and not route_active and not route_complete and not manual_plan_active and not manual_node_active
	autopilot_button.disabled = not can_send
	autopilot_button.text = "ROUTE ACTIVE IN AUTOPILOT" if route_active else "ROUTE COMPLETE" if route_complete else "SEND ROUTE TO AUTOPILOT"
	cancel_route_button.visible = route_active or route_complete
	cancel_route_button.text = "CANCEL ACTIVE ROUTE" if route_active else "CLEAR COMPLETED ROUTE"
	var send_block_reason := ""
	if route_active:
		send_block_reason = "A route is already running."
	elif route_complete:
		send_block_reason = "Disengage the completed autopilot route before sending another."
	elif manual_plan_active:
		send_block_reason = "Cancel or complete the manual flight plan before sending a route to autopilot."
	elif manual_node_active:
		send_block_reason = "Disarm manual node guidance before sending a route to autopilot."
	elif landed_state:
		send_block_reason = "Launch and establish a safe orbit before executing manoeuvre nodes."
	elif crashed_state:
		send_block_reason = "The spacecraft has crashed."
	elif not stable_orbit:
		send_block_reason = "Establish a safe orbit before sending manoeuvre nodes."
	elif has_route_target and route_solution_dirty:
		send_block_reason = "Press SOLVE TRANSFER to recalculate the edited route."
	elif has_route_target and not is_finite(route_delta_v):
		send_block_reason = "Solve a valid transfer before sending this route."
	elif not valid_nodes:
		send_block_reason = "Add at least one non-zero burn node."
	elif exceeds_delta_v:
		send_block_reason = "Planned ΔV exceeds the remaining vehicle budget."
	autopilot_button.tooltip_text = send_block_reason
	solve_route_button.disabled = not has_route_target
	var delta_v_used := 0.0 if bool(simulation.get("infinite_weightless_fuel")) else maxf(0.0, initial_available_delta_v - available_delta_v)
	burn_report.text = "PLANNED NODES: %d   •   PLANNED ΔV: %.1f m/s   •   ROUTE ΔV: %s   •   USED: %.1f m/s   •   REMAINING: %s   •   %s" % [
		nodes.size(),
		total_planned_delta_v,
		"NO SOLUTION" if not is_finite(route_delta_v) else "%.1f m/s" % route_delta_v if has_route_target else "N/A",
		delta_v_used,
		"UNLIMITED" if bool(simulation.get("infinite_weightless_fuel")) else "%.1f m/s" % available_delta_v,
		"ROUTE ACTIVE IN AUTOPILOT" if route_active else "ROUTE COMPLETE" if route_complete else "LAUNCH BEFORE EXECUTING" if landed_state else "CRAFT CRASHED" if crashed_state else "ESTABLISH A SAFE ORBIT BEFORE EXECUTING" if not stable_orbit else "ROUTE NEEDS RECALCULATION" if has_route_target and route_solution_dirty else "NO VALID ROUTE SOLUTION" if has_route_target and not is_finite(route_delta_v) else "ADD A NON-ZERO BURN" if not valid_nodes else "EXCEEDS VEHICLE ΔV" if exceeds_delta_v else "READY TO SEND TO AUTOPILOT"
	]
	if is_instance_valid(route_report):
		if has_route_target:
			route_report.text = "%s   •   TIME %.2f HOURS   •   TARGET X %.1f km, Y %.1f km   •   RANGE %.1f km" % [route_status, route_duration / 3600.0, route_target.x / 1000.0, route_target.y / 1000.0, route_target.length() / 1000.0]
		else:
			route_report.text = route_status
	_update_manual_guidance()

func _cancel_route() -> void:
	if not is_instance_valid(simulation):
		return
	var route_was_active := str(simulation.get("autopilot_phase")) in ["ROUTE_COAST", "ROUTE_BURN"]
	var route_was_complete := str(simulation.get("autopilot_phase")) == "COMPLETE" and str(simulation.get("autopilot_target_mode")) == "MANEUVER"
	if str(simulation.get("autopilot_target_mode")) != "MANEUVER" or not (route_was_active or route_was_complete):
		return
	simulation.set("autopilot_enabled", false)
	simulation.set("guidance_enabled", false)
	simulation.set("thrust_key_down", false)
	simulation.set("autopilot_complete", false)
	simulation.set("autopilot_phase", "IDLE")
	var active_route_nodes: Array[Dictionary] = simulation.get("autopilot_route_nodes")
	active_route_nodes.clear()
	simulation.set("autopilot_route_node_index", 0)
	simulation.set("autopilot_burn_remaining", 0.0)
	simulation.set("status_message", "AUTOPILOT  •  ROUTE CANCELLED" if route_was_active else "AUTOPILOT  •  COMPLETED ROUTE CLEARED")
	_update_manoeuvre()

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
	_update_manoeuvre()
