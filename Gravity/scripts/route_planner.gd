extends Window

const FlightComputer = preload("res://scripts/flight_computer.gd")

var simulation: Control
var rocket_design: Dictionary = {}
var orbit_plot: OrbitPlot
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
var nodes: Array[Dictionary] = []
var selected_node_index := -1
var loading_node := false

class OrbitPlot extends Control:
	var body_radius := 0.0
	var current_path := PackedVector2Array()
	var planned_path := PackedVector2Array()
	var node_positions := PackedVector2Array()
	var rocket_position := Vector2.ZERO

	func set_paths(current: PackedVector2Array, planned: PackedVector2Array, markers: PackedVector2Array, radius: float, initial_position: Vector2) -> void:
		current_path = current
		planned_path = planned
		node_positions = markers
		body_radius = radius
		rocket_position = initial_position
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
		var scale_factor: float = minf(size.x, size.y) * 0.46 / extent
		var center: Vector2 = size * 0.5
		var body_screen_radius: float = maxf(4.0, body_radius * scale_factor)
		draw_circle(center, body_screen_radius, Color(0.16, 0.39, 0.72))
		draw_arc(center, body_screen_radius, 0.0, TAU, 96, Color(0.45, 0.72, 1.0), 1.5)
		var current_screen := PackedVector2Array()
		for point in current_path:
			current_screen.append(center + Vector2(point.x, -point.y) * scale_factor)
		var planned_screen := PackedVector2Array()
		for point in planned_path:
			planned_screen.append(center + Vector2(point.x, -point.y) * scale_factor)
		if current_screen.size() > 1:
			draw_polyline(current_screen, Color(0.55, 0.7, 0.82, 0.8), 1.5, true)
		if planned_screen.size() > 1:
			draw_polyline(planned_screen, Color(0.25, 0.9, 0.68), 2.2, true)
		var rocket_screen: Vector2 = center + Vector2(rocket_position.x, -rocket_position.y) * scale_factor
		draw_circle(rocket_screen, 4.5, Color(1.0, 0.86, 0.35))
		for index in range(node_positions.size()):
			var node_screen: Vector2 = center + Vector2(node_positions[index].x, -node_positions[index].y) * scale_factor
			draw_circle(node_screen, 5.0, Color(1.0, 0.48, 0.25))
			draw_string(ThemeDB.fallback_font, node_screen + Vector2(7.0, -7.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.72, 0.42))

func configure(simulation_node: Control, design: Dictionary) -> void:
	simulation = simulation_node
	rocket_design = design.duplicate(true)
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
	description.text = "Build timed orbital manoeuvres and send the sequence to autopilot. The preview is an impulsive two-body estimate; live flight uses the simulator physics."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)

	orbit_plot = OrbitPlot.new()
	orbit_plot.custom_minimum_size = Vector2(0, 340)
	orbit_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orbit_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(orbit_plot)

	var legend := Label.new()
	legend.text = "GREY  CURRENT ORBIT     GREEN  PLANNED ROUTE     ORANGE  MANOEUVRE NODES"
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
		node_list.add_item("NODE %d   T+ %.1F MIN   ΔV %.0F M/S" % [index + 1, float(node.get("time_offset", 0.0)) / 60.0, Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length()])
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
	var current_path := PackedVector2Array()
	var planned_path := PackedVector2Array()
	var markers := PackedVector2Array()
	var current_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, gravitational_parameter)
	var orbit_duration: float = 7200.0
	if bool(current_orbit.get("bound", false)):
		var semi_major_axis: float = float(current_orbit.get("semi_major_axis", 0.0))
		if semi_major_axis > 0.0:
			orbit_duration = TAU * sqrt(pow(semi_major_axis, 3.0) / gravitational_parameter)
	orbit_duration = clampf(orbit_duration, 60.0, 30.0 * 86400.0)
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
	var final_duration: float = 7200.0
	if bool(final_orbit.get("bound", false)):
		var final_axis: float = float(final_orbit.get("semi_major_axis", 0.0))
		if final_axis > 0.0:
			final_duration = TAU * sqrt(pow(final_axis, 3.0) / gravitational_parameter)
	final_duration = clampf(final_duration, 60.0, 30.0 * 86400.0)
	var remaining_steps: int = 180
	var final_result: Dictionary = _append_integrated_path(planned_path, plan_position, plan_velocity, final_duration, remaining_steps)
	planned_path = final_result.get("path", planned_path)
	orbit_plot.set_paths(current_path, planned_path, markers, float(current_body.get("radius", 0.0)), relative_position)
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
	var valid_nodes: bool = not nodes.is_empty()
	for node in nodes:
		if Vector2(float(node.get("prograde", 0.0)), float(node.get("radial", 0.0))).length() < 0.1:
			valid_nodes = false
	autopilot_button.disabled = landed_state or crashed_state or not valid_nodes or total_planned_delta_v > available_delta_v
	burn_report.text = "PLANNED NODES: %d   •   TOTAL ΔV: %.1f m/s   •   AVAILABLE ΔV: %.1f m/s   •   %s" % [
		nodes.size(),
		total_planned_delta_v,
		available_delta_v,
		"LAUNCH BEFORE EXECUTING" if landed_state else "CRAFT CRASHED" if crashed_state else "EXCEEDS VEHICLE ΔV" if total_planned_delta_v > available_delta_v else "READY TO SEND TO AUTOPILOT"
	]

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

