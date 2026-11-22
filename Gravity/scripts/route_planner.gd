extends Window

const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

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
var cancel_route_button: Button
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
var navigation_report: RichTextLabel
var navigation_engage_button: Button
var navigation_plan_valid := false
var navigation_plan: Dictionary = {}

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

	func _gui_input(event: InputEvent) -> void:
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
	navigation_description.text = "Plan a transfer to any modeled planet or moon and enter a target orbit. This uses the same trajectory search and autopilot as the main destination controls."
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
	navigation_report = RichTextLabel.new()
	navigation_report.bbcode_enabled = false
	navigation_report.fit_content = true
	navigation_report.custom_minimum_size.y = 76
	navigation_report.scroll_active = false
	root.add_child(navigation_report)

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
	var remove_button := Button.new()
	remove_button.text = "REMOVE SELECTED NODE"
	remove_button.pressed.connect(_remove_node)
	node_actions.add_child(remove_button)
	node_editor = node_row

	burn_report = Label.new()
	burn_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(burn_report)

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
	var stable_orbit := inside_current_soi and bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current.get("radius", 0.0)) + current_minimum
	if current_name == target_name:
		if not stable_orbit:
			_invalidate_navigation_plan()
			navigation_report.text = "ESTABLISH A SAFE ORBIT AROUND %s BEFORE CALCULATING AN ORBIT CHANGE." % target_name.to_upper()
			return
		var local_plan := FlightComputer.target_radius_burn(current_position, current_velocity, target_radius, current_mu)
		var local_available: float = FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if bool(simulation.get("infinite_weightless_fuel")) else FlightComputer.available_delta_v(rocket_design, int(simulation.get("stage_index")), float(simulation.get("fuel"))) * (1.0 - float(simulation.get("autopilot_safety_margin")))
		if not bool(local_plan.get("valid", false)) or float(local_plan.get("delta_v", INF)) > local_available:
			_invalidate_navigation_plan()
			navigation_report.text = "NO FEASIBLE LOCAL ORBIT CHANGE. Check the target orbit and remaining ΔV budget."
			return
		navigation_plan = {"valid": true, "target_id": target_id, "target_name": target_name, "target_altitude": target_altitude, "delta_v": float(local_plan.get("delta_v", 0.0)), "local": true}
	else:
		if not stable_orbit:
			_invalidate_navigation_plan()
			navigation_report.text = "A SAFE PARKING ORBIT AROUND %s IS REQUIRED BEFORE A DESTINATION TRANSFER CAN BE CALCULATED." % current_name.to_upper()
			return
		var available: float = FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if bool(simulation.get("infinite_weightless_fuel")) else FlightComputer.available_delta_v(rocket_design, int(simulation.get("stage_index")), float(simulation.get("fuel"))) * (1.0 - float(simulation.get("autopilot_safety_margin")))
		var transfer: Dictionary = FlightComputer.simulated_transfer_search_precise(simulation.get("rocket_position_precise"), simulation.get("velocity"), float(simulation.get("sim_time")), target_id, available, float(simulation.get("autopilot_speed_priority")), false, target_altitude)
		if not bool(transfer.get("valid", false)):
			_invalidate_navigation_plan()
			navigation_report.text = "NO FEASIBLE TRANSFER FOUND\n" + str(transfer.get("reason", "No trajectory satisfied the arrival and fuel constraints."))
			return
		navigation_plan = transfer.duplicate(true)
		navigation_plan["target_id"] = target_id
		navigation_plan["target_name"] = target_name
		navigation_plan["target_altitude"] = target_altitude
		navigation_plan["local"] = false
	navigation_plan_valid = true
	navigation_engage_button.disabled = false
	if bool(navigation_plan.get("local", false)):
		navigation_report.text = "ORBIT CHANGE SOLVED  •  %s\nTarget altitude: %.1f km\nRequired ΔV: %.0f m/s\nThis plan will circularise around the current body." % [target_name, target_altitude / 1000.0, float(navigation_plan.get("delta_v", 0.0))]
	else:
		navigation_report.text = "TRANSFER SOLVED  •  %s\nDeparture ΔV: %.0f m/s\nArrival capture ΔV: %.0f m/s\nTotal estimated ΔV: %.0f m/s\nFlight time: %.1f days\nClosest approach: %.0f km\nCandidate trajectories: %d\nFinite-burn losses and mid-course correction errors are not included." % [
			target_name,
			float(navigation_plan.get("departure_delta_v", 0.0)),
			float(navigation_plan.get("capture_delta_v", 0.0)),
			float(navigation_plan.get("total_delta_v", 0.0)),
			float(navigation_plan.get("transfer_time", 0.0)) / 86400.0,
			float(navigation_plan.get("closest_approach", 0.0)) / 1000.0,
			int(navigation_plan.get("search_candidates", 0))
		]

func _send_destination_to_autopilot() -> void:
	if not navigation_plan_valid or not is_instance_valid(simulation) or bool(simulation.get("crashed")):
		return
	var target_id := int(navigation_plan.get("target_id", -999))
	var target_name := str(navigation_plan.get("target_name", ""))
	if target_id == -999 or target_name.is_empty():
		return
	var current: Dictionary = simulation.call("_nearest_body_state", simulation.get("rocket_position"))
	var current_name := str(current.get("name", ""))
	var relative_position: Vector2 = Vector2(simulation.get("rocket_position")) - Vector2(current.get("position", Vector2.ZERO))
	var relative_velocity: Vector2 = Vector2(simulation.get("velocity")) - Vector2(current.get("velocity", Vector2.ZERO))
	var current_orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(current.get("mass", 0.0)))
	var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(current_name, float(current.get("radius", 0.0)))
	var stable_orbit := bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current.get("radius", 0.0)) + minimum_altitude
	simulation.set("autopilot_enabled", true)
	simulation.set("autopilot_complete", false)
	simulation.set("autopilot_target_mode", "ORBIT")
	simulation.set("autopilot_planet_index", target_id)
	simulation.set("autopilot_target_altitude", float(navigation_plan.get("target_altitude", 200000.0)))
	simulation.set("autopilot_burn_remaining", 0.0)
	simulation.set("autopilot_burn_direction", Vector2.ZERO)
	simulation.set("autopilot_transfer_corrections", 0)
	simulation.set("autopilot_apsis_correction_armed", true)
	simulation.set("autopilot_apsis_correction_angle", relative_position.angle())
	simulation.set("autopilot_phase", "CIRCULARISE" if current_name == target_name and stable_orbit else "ASCENT" if bool(simulation.get("landed")) or not stable_orbit else "PLAN_TRANSFER")
	simulation.set("guidance_enabled", true)
	simulation.set("thrust_key_down", bool(simulation.get("landed")) or not stable_orbit)
	simulation.set("status_message", "FLIGHT COMPUTER  •  NAVIGATING TO %s" % target_name.to_upper())
	navigation_engage_button.disabled = true
	navigation_engage_button.text = "AUTOPILOT ENGAGED"
	navigation_report.text += "\n\nAUTOPILOT ENGAGED. The flight computer has transferred the destination and orbit altitude to the live guidance system."

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
	if index < 0 or index >= nodes.size() or current_path.size() < 2:
		return
	if index == 0:
		_invalidate_route_solution()
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
	var remaining_steps: int = 1440
	var final_result: Dictionary = _append_integrated_path(planned_path, plan_position, plan_velocity, final_duration, remaining_steps)
	planned_path = final_result.get("path", planned_path)
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
	var can_send := not landed_state and not crashed_state and stable_orbit and valid_nodes and not exceeds_delta_v and not route_active and not route_complete
	autopilot_button.disabled = not can_send
	autopilot_button.text = "ROUTE ACTIVE IN AUTOPILOT" if route_active else "ROUTE COMPLETE" if route_complete else "SEND ROUTE TO AUTOPILOT"
	cancel_route_button.visible = route_active or route_complete
	cancel_route_button.text = "CANCEL ACTIVE ROUTE" if route_active else "CLEAR COMPLETED ROUTE"
	var send_block_reason := ""
	if route_active:
		send_block_reason = "A route is already running."
	elif route_complete:
		send_block_reason = "Disengage the completed autopilot route before sending another."
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
