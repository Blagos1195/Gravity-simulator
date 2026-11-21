extends Window

const FlightComputer = preload("res://scripts/flight_computer.gd")

var simulation: Control
var rocket_design: Dictionary = {}
var orbit_plot: OrbitPlot
var prograde_input: SpinBox
var radial_input: SpinBox
var state_report: RichTextLabel
var burn_report: Label
var current_body: Dictionary = {}
var relative_position := Vector2.ZERO
var relative_velocity := Vector2.ZERO
var gravitational_parameter := 0.0
var planned_burn_vector := Vector2.ZERO

class OrbitPlot extends Control:
	var position_state := Vector2.ZERO
	var velocity_state := Vector2.ZERO
	var gravitational_parameter := 0.0
	var burn_vector := Vector2.ZERO

	func set_orbit(position: Vector2, velocity: Vector2, mu: float, burn: Vector2) -> void:
		position_state = position
		velocity_state = velocity
		gravitational_parameter = mu
		burn_vector = burn
		queue_redraw()

	func _acceleration(position: Vector2, mu: float) -> Vector2:
		var radius: float = maxf(1.0, position.length())
		return -position / radius * mu / (radius * radius)

	func _sample_orbit(start_position: Vector2, start_velocity: Vector2) -> PackedVector2Array:
		var points := PackedVector2Array()
		if gravitational_parameter <= 0.0 or start_position.length_squared() <= 1.0:
			return points
		var orbit := FlightComputer.orbital_state(start_position, start_velocity, gravitational_parameter)
		var duration: float = 7200.0
		if bool(orbit.get("bound", false)):
			var semi_major_axis: float = float(orbit.get("semi_major_axis", 0.0))
			if semi_major_axis > 0.0:
				duration = TAU * sqrt(pow(semi_major_axis, 3.0) / gravitational_parameter)
		duration = clampf(duration, 60.0, 30.0 * 86400.0)
		var step: float = duration / 180.0
		var sample_position: Vector2 = start_position
		var sample_velocity: Vector2 = start_velocity
		points.append(sample_position)
		for index in range(180):
			var first_acceleration: Vector2 = _acceleration(sample_position, gravitational_parameter)
			var half_velocity: Vector2 = sample_velocity + first_acceleration * step * 0.5
			var next_position: Vector2 = sample_position + half_velocity * step
			var second_acceleration: Vector2 = _acceleration(next_position, gravitational_parameter)
			sample_velocity = half_velocity + second_acceleration * step * 0.5
			sample_position = next_position
			points.append(sample_position)
		return points

	func _draw() -> void:
		if gravitational_parameter <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
			return
		var current_path: PackedVector2Array = _sample_orbit(position_state, velocity_state)
		var planned_path: PackedVector2Array = _sample_orbit(position_state, velocity_state + burn_vector)
		var extent: float = maxf(position_state.length(), 1.0)
		for point in current_path:
			extent = maxf(extent, point.length())
		for point in planned_path:
			extent = maxf(extent, point.length())
		extent *= 1.08
		var scale_factor: float = minf(size.x, size.y) * 0.46 / extent
		var center: Vector2 = size * 0.5
		var body_radius: float = minf(FlightComputer.EARTH_RADIUS, extent * 0.08)
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
			draw_polyline(planned_screen, Color(0.25, 0.9, 0.68), 2.5, true)
		var rocket_screen: Vector2 = center + Vector2(position_state.x, -position_state.y) * scale_factor
		draw_circle(rocket_screen, 4.5, Color(1.0, 0.86, 0.35))
		if burn_vector.length_squared() > 0.01:
			var burn_direction: Vector2 = Vector2(burn_vector.x, -burn_vector.y).normalized()
			var arrow_end: Vector2 = rocket_screen + burn_direction * 34.0
			draw_line(rocket_screen, arrow_end, Color(1.0, 0.48, 0.25), 2.5, true)
			draw_circle(arrow_end, 3.0, Color(1.0, 0.48, 0.25))

func configure(simulation_node: Control, design: Dictionary) -> void:
	simulation = simulation_node
	rocket_design = design.duplicate(true)
	title = "FLIGHT COMPUTER  •  ORBITAL ROUTE PLANNER"
	size = Vector2i(900, 760)
	min_size = Vector2i(680, 560)
	close_requested.connect(queue_free)
	_build_interface()
	_refresh_state()
	popup_centered()

func _build_interface() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 14
	root.offset_bottom = -14
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var heading := Label.new()
	heading.text = "ORBITAL ROUTE PLANNER"
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(heading)

	var description := Label.new()
	description.text = "Plot the current orbit, add an immediate manoeuvre and preview the resulting trajectory before sending the burn to autopilot."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)

	orbit_plot = OrbitPlot.new()
	orbit_plot.custom_minimum_size = Vector2(0, 340)
	orbit_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orbit_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(orbit_plot)

	var legend := Label.new()
	legend.text = "GREY  CURRENT ORBIT     GREEN  PLANNED ORBIT     ORANGE  BURN DIRECTION"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 11)
	root.add_child(legend)

	state_report = RichTextLabel.new()
	state_report.bbcode_enabled = false
	state_report.fit_content = true
	state_report.custom_minimum_size.y = 74
	state_report.scroll_active = false
	root.add_child(state_report)

	var node_heading := Label.new()
	node_heading.text = "MANOEUVRE NODE  •  IMMEDIATE BURN"
	node_heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(node_heading)

	var controls := GridContainer.new()
	controls.columns = 4
	controls.add_theme_constant_override("h_separation", 12)
	controls.add_theme_constant_override("v_separation", 5)
	root.add_child(controls)

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

	burn_report = Label.new()
	burn_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(burn_report)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	var refresh_button := Button.new()
	refresh_button.text = "REFRESH ORBIT"
	refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_button.pressed.connect(_refresh_state)
	actions.add_child(refresh_button)
	var preview_button := Button.new()
	preview_button.text = "UPDATE MANOEUVRE"
	preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_button.pressed.connect(_update_manoeuvre)
	actions.add_child(preview_button)
	var autopilot_button := Button.new()
	autopilot_button.text = "SEND BURN TO AUTOPILOT"
	autopilot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autopilot_button.pressed.connect(_send_to_autopilot)
	actions.add_child(autopilot_button)
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.pressed.connect(queue_free)
	actions.add_child(close_button)

	prograde_input.value_changed.connect(func(_value: float): _update_manoeuvre())
	radial_input.value_changed.connect(func(_value: float): _update_manoeuvre())

func _create_burn_input() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -10000.0
	spin.max_value = 10000.0
	spin.step = 10.0
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value = 0.0
	spin.custom_minimum_size.x = 125.0
	return spin

func _refresh_state() -> void:
	if not is_instance_valid(simulation):
		return
	current_body = simulation.call("_nearest_body_state", simulation.get("rocket_position"))
	var body_position: Vector2 = current_body.get("position", Vector2.ZERO)
	var body_velocity: Vector2 = current_body.get("velocity", Vector2.ZERO)
	relative_position = Vector2(simulation.get("rocket_position")) - body_position
	relative_velocity = Vector2(simulation.get("velocity")) - body_velocity
	gravitational_parameter = FlightComputer.G * float(current_body.get("mass", 0.0))
	_update_manoeuvre()

func _update_manoeuvre() -> void:
	if not is_instance_valid(orbit_plot) or gravitational_parameter <= 0.0:
		return
	var radial: Vector2 = relative_position.normalized()
	var tangent := Vector2(-radial.y, radial.x)
	if relative_position.cross(relative_velocity) < 0.0:
		tangent = -tangent
	planned_burn_vector = tangent * prograde_input.value + radial * radial_input.value
	orbit_plot.set_orbit(relative_position, relative_velocity, gravitational_parameter, planned_burn_vector)
	var current_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity, gravitational_parameter)
	var planned_orbit: Dictionary = FlightComputer.orbital_state(relative_position, relative_velocity + planned_burn_vector, gravitational_parameter)
	var current_periapsis: float = (float(current_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0
	var current_apoapsis: float = (float(current_orbit.get("apoapsis", INF)) - float(current_body.get("radius", 0.0))) / 1000.0
	var planned_periapsis: float = (float(planned_orbit.get("periapsis", 0.0)) - float(current_body.get("radius", 0.0))) / 1000.0
	var planned_apoapsis: float = (float(planned_orbit.get("apoapsis", INF)) - float(current_body.get("radius", 0.0))) / 1000.0
	state_report.text = "BODY: %s    ALTITUDE: %.1f km    SPEED: %.0f m/s\nCURRENT ORBIT: Pe %.1f km  •  Ap %s\nPLANNED ORBIT: Pe %.1f km  •  Ap %s" % [
		str(current_body.get("name", "Unknown")),
		(relative_position.length() - float(current_body.get("radius", 0.0))) / 1000.0,
		relative_velocity.length(),
		current_periapsis,
		"UNBOUND" if not bool(current_orbit.get("bound", false)) else "%.1f km" % current_apoapsis,
		planned_periapsis,
		"UNBOUND" if not bool(planned_orbit.get("bound", false)) else "%.1f km" % planned_apoapsis
	]
	var burn_angle: float = rad_to_deg(atan2(radial_input.value, prograde_input.value))
	burn_report.text = "TOTAL ΔV: %.1f m/s    •    BURN ROTATION FROM PROGRADE: %.1f°    •    %s" % [
		planned_burn_vector.length(),
		burn_angle,
		"NO BURN SELECTED" if planned_burn_vector.length() < 0.1 else "READY TO PREVIEW OR EXECUTE"
	]

func _send_to_autopilot() -> void:
	if not is_instance_valid(simulation) or planned_burn_vector.length() < 0.1:
		return
	simulation.set("autopilot_enabled", true)
	simulation.set("autopilot_complete", false)
	simulation.set("autopilot_target_mode", "MANEUVER")
	simulation.set("autopilot_burn_direction", planned_burn_vector.normalized())
	simulation.set("autopilot_burn_remaining", planned_burn_vector.length())
	simulation.set("autopilot_phase", "MANEUVER_BURN")
	simulation.set("guidance_enabled", true)
	simulation.set("thrust_key_down", false)
	burn_report.text += "    •    BURN SENT TO AUTOPILOT"
