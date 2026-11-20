extends Control

const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const G := PlanetarySystem.G
const EARTH_MASS := PlanetarySystem.EARTH_MASS
const EARTH_RADIUS := PlanetarySystem.EARTH_RADIUS
const DRAG_AREA := 0.45
const LIFT_AREA := 1.8
const EARTH_ROTATION_RATE := 7.2921159e-5

var rocket_stages: Array = []
var payload_mass := 500.0

var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var paused := false
var sim_time := 0.0
var time_warp := 1.0
var rocket_position := Vector2(0, -EARTH_RADIUS - 2.0)
var velocity := Vector2(EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0)
var rotation_angle := 0.0
var fuel := 300000.0
var stage_index := 0
var discarded_stage_mass := 0.0
var throttle := 0.0
var gimbal_angle := 0.0
var guidance_enabled := false
var autopilot_enabled := false
var autopilot_target_altitude := 200000.0
var autopilot_target_mode := "ORBIT"
var autopilot_planet_index := -1
var autopilot_burn_remaining := 0.0
var autopilot_transfer_direction := 1.0
var autopilot_complete := false
var autopilot_phase := "IDLE"
var heat_flux_mw := 0.0
var heat_shield_temperature := 290.0
var peak_heat_flux_mw := 0.0
var mach_number := 0.0
var dynamic_pressure_pa := 0.0
var camera_zoom := 0.000045
var solar_map_zoom := 1.0
var camera_offset := Vector2.ZERO
var trail: Array[Vector2] = []
var trail_timer := 0.0
var star_points: Array[Vector2] = []
var status_message := "PAD READY  •  PRESS W TO IGNITE"
var orbit_path: Array[Vector2] = []
var show_orbit := true
var show_grid := true
var show_vectors := true
var show_solar_system := false
var show_predicted_trajectory := false
var predicted_path: Array[Vector2] = []
var prediction_timer := 0.0
var thrust_key_down := false
var throttle_cutoff_key_down := false

func set_rocket_design(design: Dictionary) -> void:
	rocket_stages = (design.get("stages", []) as Array).duplicate(true)
	if rocket_stages.size() < 2:
		rocket_stages = RocketDesign.create_default()["stages"].duplicate(true)
	payload_mass = float(design.get("payload_mass", 500.0))
	stage_index = 0
	fuel = float(rocket_stages[0].get("fuel_capacity", 0.0))

func _active_stage_data() -> Dictionary:
	return rocket_stages[clampi(stage_index, 0, rocket_stages.size() - 1)]

func _remaining_stack_mass() -> float:
	var mass := payload_mass
	for i in range(stage_index + 1, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[i]
		mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
	return mass

func _current_vehicle_mass(fuel_amount: float = -1.0) -> float:
	var active := _active_stage_data()
	return float(active.get("dry_mass", 0.0)) + _remaining_stack_mass() + (fuel if fuel_amount < 0.0 else fuel_amount)

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44219
	for i in range(500):
		star_points.append(Vector2(rng.randf_range(-12000, 12000), rng.randf_range(-8000, 8000)))
	set_process(true)

func _process(delta: float) -> void:
	if not paused:
		var remaining := time_warp * delta
		var iterations := 0
		while remaining > 0.000001 and iterations < 20000:
			var step_delta := minf(remaining, _adaptive_step_size())
			_physics_step(step_delta)
			remaining -= step_delta
			iterations += 1
	if show_predicted_trajectory:
		prediction_timer += delta
		if prediction_timer >= 0.35:
			prediction_timer = 0.0
			_calculate_predicted_trajectory()
	trail_timer += delta
	if trail_timer >= 0.12:
		trail_timer = 0.0
		trail.append(rocket_position)
		if trail.size() > 450:
			trail.pop_front()
	queue_redraw()

func _physics_step(dt: float) -> void:
	var start_time := sim_time
	var end_time := sim_time + dt
	var altitude := rocket_position.length() - EARTH_RADIUS
	if altitude < 0.5:
		var normal := rocket_position.normalized()
		rocket_position = normal * (EARTH_RADIUS + 0.5)
		var inward_speed := velocity.dot(normal)
		if inward_speed < 0.0:
			velocity -= normal * inward_speed
	if guidance_enabled:
		_update_guidance(dt)
	var active := _active_stage_data()
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	throttle = 1.0 if thrust_key_down and fuel > 0.0 else 0.0
	var fuel_used := minf(fuel, total_flow * throttle * dt)
	var mass_before := maxf(1.0, _current_vehicle_mass())
	var mass_after := maxf(1.0, mass_before - fuel_used)
	var mass_mid := (mass_before + mass_after) * 0.5
	var thrust_force := _engine_thrust(maxf(0.0, altitude)) * throttle
	var thrust_delta_v := 0.0
	if fuel_used > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
		thrust_delta_v = thrust_force / total_flow * log(mass_before / mass_after)
	var thrust_direction := Vector2.UP.rotated(rotation_angle + gimbal_angle)
	var thrust_impulse := thrust_direction * thrust_delta_v
	if autopilot_enabled and autopilot_phase == "TRANSFER_BURN" and thrust_delta_v > 0.0:
		autopilot_burn_remaining = maxf(0.0, autopilot_burn_remaining - thrust_delta_v)
		if autopilot_burn_remaining <= 1.0:
			thrust_key_down = false
			autopilot_phase = "TRANSFER_COAST"
			autopilot_complete = true
	var initial_gravity := PlanetarySystem.gravity_acceleration(rocket_position, start_time)
	var initial_aero := _aerodynamic_acceleration(rocket_position, velocity, mass_mid)
	var half_velocity := velocity + (initial_gravity + initial_aero) * (0.5 * dt) + thrust_impulse * 0.5
	var next_position := rocket_position + half_velocity * dt
	var final_gravity := PlanetarySystem.gravity_acceleration(next_position, end_time)
	var final_aero := _aerodynamic_acceleration(next_position, half_velocity, mass_mid)
	velocity = half_velocity + (final_gravity + final_aero) * (0.5 * dt) + thrust_impulse * 0.5
	rocket_position = next_position
	sim_time = end_time
	fuel = maxf(0.0, fuel - fuel_used)
	_update_flight_environment()
	_update_heating(dt, rocket_position.length() - EARTH_RADIUS, (velocity - Vector2(-rocket_position.y, rocket_position.x) * EARTH_ROTATION_RATE).length())
	if fuel <= 0.0001 and stage_index < rocket_stages.size() - 1:
		_separate_stage()
	if rocket_position.length() < EARTH_RADIUS + 0.5:
		var normal := rocket_position.normalized()
		rocket_position = normal * (EARTH_RADIUS + 0.5)
		var radial_speed := velocity.dot(normal)
		if radial_speed < 0.0:
			velocity -= normal * radial_speed
	var final_altitude := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
	status_message = "STAGE %d  •  ENGINE FIRING" % (stage_index + 1) if throttle > 0.0 else "PAD READY  •  W TO IGNITE" if final_altitude < 100.0 else "FLIGHT ACTIVE"

func _adaptive_step_size() -> float:
	var radius := maxf(EARTH_RADIUS, rocket_position.length())
	var altitude := maxf(0.0, radius - EARTH_RADIUS)
	var gravity := G * EARTH_MASS / (radius * radius)
	var orbital_limit := 0.015 * sqrt(radius / maxf(0.001, gravity))
	var speed := velocity.length()
	var travel_limit := 250.0 / maxf(100.0, speed) if altitude < 150000.0 else 0.25
	var drag_acceleration := _aerodynamic_acceleration(rocket_position, velocity, maxf(1.0, _current_vehicle_mass())).length()
	var drag_limit := 0.08 * speed / drag_acceleration if drag_acceleration > 0.01 else 0.25
	var active := _active_stage_data()
	var engine_acceleration := _engine_thrust(altitude) / maxf(1.0, _current_vehicle_mass()) if thrust_key_down and fuel > 0.0 else 0.0
	var thrust_limit := 0.08 * maxf(100.0, speed) / engine_acceleration if engine_acceleration > 0.01 else 0.25
	var total_flow := float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
	var burnout_limit := fuel / total_flow if thrust_key_down and fuel > 0.0 and total_flow > 0.0 else 0.25
	var physics_limit := clampf(minf(minf(orbital_limit, travel_limit), minf(drag_limit, thrust_limit)), 0.0005, 0.25)
	return minf(physics_limit, burnout_limit)

func _engine_thrust(altitude: float) -> float:
	var active := _active_stage_data()
	var ambient_pressure_ratio := PlanetarySystem.atmospheric_pressure(altitude) / 101325.0
	var sea_level_thrust := float(active.get("thrust", 0.0))
	var vacuum_thrust := float(active.get("vacuum_thrust", 0.0))
	return lerpf(vacuum_thrust, sea_level_thrust, clampf(ambient_pressure_ratio, 0.0, 1.0)) * float(active.get("engine_count", 1))

func _aerodynamic_acceleration(position: Vector2, current_velocity: Vector2, mass: float) -> Vector2:
	if realism not in ["Realistic", "Hardcore"]:
		return Vector2.ZERO
	var altitude := position.length() - EARTH_RADIUS
	if altitude >= PlanetarySystem.ATMOSPHERE_HEIGHT:
		return Vector2.ZERO
	var density := PlanetarySystem.atmospheric_density(altitude)
	var atmospheric_velocity := Vector2(-position.y, position.x) * EARTH_ROTATION_RATE
	var relative_velocity := current_velocity - atmospheric_velocity
	var relative_speed := relative_velocity.length()
	if relative_speed < 0.01:
		return Vector2.ZERO
	var direction := relative_velocity / relative_speed
	var nose := Vector2.UP.rotated(rotation_angle + gimbal_angle)
	var angle_of_attack := asin(clampf(nose.cross(direction), -1.0, 1.0))
	var temperature := PlanetarySystem.atmospheric_temperature(altitude)
	var speed_of_sound := sqrt(1.4 * 287.05287 * temperature)
	var mach := relative_speed / maxf(1.0, speed_of_sound)
	var drag_coefficient := 0.22 + 0.28 * exp(-pow((mach - 1.0) / 0.3, 2.0)) + 0.08 * pow(sin(angle_of_attack), 2.0)
	var dynamic_pressure := 0.5 * density * relative_speed * relative_speed
	var drag_force := dynamic_pressure * DRAG_AREA * drag_coefficient
	var lift_force := dynamic_pressure * LIFT_AREA * sin(2.0 * angle_of_attack) * 0.35
	var lift_direction := Vector2(-direction.y, direction.x)
	return -direction * (drag_force / maxf(1.0, mass)) + lift_direction * (lift_force / maxf(1.0, mass))

func _update_flight_environment() -> void:
	var altitude := rocket_position.length() - EARTH_RADIUS
	if altitude >= PlanetarySystem.ATMOSPHERE_HEIGHT:
		mach_number = 0.0
		dynamic_pressure_pa = 0.0
		return
	var atmospheric_velocity := Vector2(-rocket_position.y, rocket_position.x) * EARTH_ROTATION_RATE
	var relative_speed := (velocity - atmospheric_velocity).length()
	var density := PlanetarySystem.atmospheric_density(altitude)
	var temperature := PlanetarySystem.atmospheric_temperature(altitude)
	mach_number = relative_speed / sqrt(1.4 * 287.05287 * temperature)
	dynamic_pressure_pa = 0.5 * density * relative_speed * relative_speed

func _update_heating(dt: float, altitude: float, speed: float) -> void:
	var heat_flux_w := 0.0
	if altitude < PlanetarySystem.ATMOSPHERE_HEIGHT:
		var density := PlanetarySystem.atmospheric_density(altitude)
		var nose_radius := 0.5
		heat_flux_w = 1.83e-4 * sqrt(maxf(0.0, density) / nose_radius) * pow(speed, 3.0)
	heat_flux_mw = heat_flux_w / 1000000.0
	peak_heat_flux_mw = maxf(peak_heat_flux_mw, heat_flux_mw)
	var absorbed_flux := heat_flux_w * 0.15
	var radiated_flux := 0.82 * 5.670374419e-8 * (pow(heat_shield_temperature, 4.0) - pow(290.0, 4.0))
	var temperature_rate := (absorbed_flux - radiated_flux) / 60000.0
	heat_shield_temperature = maxf(290.0, heat_shield_temperature + temperature_rate * dt)

func _separate_stage() -> void:
	if stage_index >= rocket_stages.size() - 1:
		return
	discarded_stage_mass += float(_active_stage_data().get("dry_mass", 0.0)) + fuel
	stage_index += 1
	fuel = float(_active_stage_data().get("fuel_capacity", 0.0))
	thrust_key_down = false

func _update_guidance(dt: float) -> void:
	var radial := rocket_position.normalized()
	var altitude := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
	var tangent := Vector2(-radial.y, radial.x)
	var pitch_above_horizon := lerpf(90.0, 5.0, clampf(altitude / 100000.0, 0.0, 1.0))
	if autopilot_enabled:
		var orbit := FlightComputer.orbital_state(rocket_position, velocity)
		var target_radius := EARTH_RADIUS + autopilot_target_altitude
		var prograde := velocity.normalized() if velocity.length() > 1.0 else tangent
		match autopilot_phase:
			"ASCENT":
				status_message = "AUTOPILOT  •  ASCENT TO %.0f KM" % (autopilot_target_altitude / 1000.0)
				if bool(orbit.get("bound", false)) and float(orbit.get("apoapsis", 0.0)) >= target_radius:
					thrust_key_down = false
					autopilot_phase = "COAST"
				else:
					var apoapsis: float = float(orbit.get("apoapsis", 0.0))
					var apoapsis_fraction := clampf((apoapsis - EARTH_RADIUS) / maxf(1.0, autopilot_target_altitude), 0.0, 1.0) if is_finite(apoapsis) else 0.0
					var speed_fraction := clampf(velocity.length() / 7800.0, 0.0, 1.0)
					pitch_above_horizon = lerpf(90.0, 2.0, clampf(maxf(altitude / maxf(1.0, autopilot_target_altitude), apoapsis_fraction * 0.92, speed_fraction * 0.9), 0.0, 1.0))
					thrust_key_down = fuel > 0.0
			"COAST":
				status_message = "AUTOPILOT  •  COASTING TO APOAPSIS"
				thrust_key_down = false
				if absf(float(orbit.get("radial_speed", 0.0))) <= 5.0 and altitude > 70000.0:
					autopilot_phase = "CIRCULARISE"
					thrust_key_down = true
			"CIRCULARISE":
				status_message = "AUTOPILOT  •  ORBITAL CIRCULARISATION"
				var desired_speed := FlightComputer.circular_orbit_speed(rocket_position.length())
				var tangential_speed := float(orbit.get("tangential_speed", 0.0))
				var radial_speed := absf(float(orbit.get("radial_speed", 0.0)))
				var speed_error := desired_speed - tangential_speed
				autopilot_transfer_direction = 1.0 if speed_error >= 0.0 else -1.0
				var circular_burn_direction := tangent * autopilot_transfer_direction
				var circular_burn_rotation := circular_burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, circular_burn_rotation, clampf(dt * 1.5, 0.0, 1.0))
				if absf(speed_error) <= 2.0 and radial_speed < 100.0:
					thrust_key_down = false
					if autopilot_target_mode == "PLANET":
						var transfer := FlightComputer.interplanetary_transfer(autopilot_planet_index, altitude)
					if bool(transfer.get("valid", false)):
						autopilot_burn_remaining = float(transfer.get("departure_delta_v", 0.0))
						autopilot_transfer_direction = float(transfer.get("direction", 1.0))
						var wait_time := FlightComputer.departure_wait_time(autopilot_planet_index, sim_time, rocket_position)
						autopilot_phase = "TRANSFER_BURN" if wait_time <= 1.0 else "WAIT_WINDOW"
					else:
						autopilot_phase = "FAILED"
				else:
					autopilot_phase = "COMPLETE"
					autopilot_complete = true
				else:
					thrust_key_down = fuel > 0.0
			"WAIT_WINDOW":
				var wait_time := FlightComputer.departure_wait_time(autopilot_planet_index, sim_time)
				status_message = "AUTOPILOT  •  WAITING FOR TRANSFER WINDOW  %.1F DAYS" % (wait_time / 86400.0)
				thrust_key_down = false
				if wait_time <= 1.0:
					autopilot_phase = "TRANSFER_BURN"
			"TRANSFER_BURN":
				status_message = "AUTOPILOT  •  INTERPLANETARY INJECTION  %.0F M/S" % autopilot_burn_remaining
				var burn_direction := tangent * autopilot_transfer_direction
				var burn_rotation := burn_direction.angle() - Vector2.UP.angle()
				rotation_angle = lerp_angle(rotation_angle, burn_rotation, clampf(dt * 1.5, 0.0, 1.0))
				thrust_key_down = fuel > 0.0 and autopilot_burn_remaining > 1.0
				if fuel <= 0.0:
					autopilot_phase = "FAILED"
			"TRANSFER_COAST":
				status_message = "AUTOPILOT  •  TRANSFER BURN COMPLETE"
				thrust_key_down = false
			"COMPLETE":
				status_message = "AUTOPILOT  •  TARGET ORBIT ACHIEVED"
				thrust_key_down = false
				autopilot_complete = true
			"FAILED":
				status_message = "AUTOPILOT  •  BURN INCOMPLETE"
				thrust_key_down = false
		var target_direction := prograde
		if autopilot_phase in ["TRANSFER_BURN", "WAIT_WINDOW"]:
			target_direction = tangent * autopilot_transfer_direction
		var target_rotation := target_direction.angle() - Vector2.UP.angle()
		rotation_angle = lerp_angle(rotation_angle, target_rotation, clampf(dt * 0.8, 0.0, 1.0))
		return
	elif velocity.length() > 1500.0:
		pitch_above_horizon = minf(pitch_above_horizon, 12.0)
	var target_direction := radial * sin(deg_to_rad(pitch_above_horizon)) + tangent * cos(deg_to_rad(pitch_above_horizon))
	var target_rotation := target_direction.angle() - Vector2.UP.angle()
	rotation_angle = lerp_angle(rotation_angle, target_rotation, clampf(dt * 0.08, 0.0, 1.0))

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode in [KEY_W, KEY_UP] or event.physical_keycode in [KEY_W, KEY_UP]:
				thrust_key_down = not thrust_key_down
			if event.keycode in [KEY_S, KEY_DOWN] or event.physical_keycode in [KEY_S, KEY_DOWN]:
				thrust_key_down = false
			throttle_cutoff_key_down = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		thrust_key_down = false
		throttle_cutoff_key_down = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_A, KEY_LEFT:
				rotation_angle -= 0.12
			KEY_D, KEY_RIGHT:
				rotation_angle += 0.12
			KEY_SPACE:
				paused = not paused
			KEY_HOME:
				camera_zoom = 0.000045
				solar_map_zoom = 1.0
			KEY_EQUAL, KEY_KP_ADD:
				time_warp = minf(100.0, time_warp * 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				time_warp = maxf(0.25, time_warp / 2.0)
			KEY_O:
				show_orbit = not show_orbit
			KEY_P:
				show_predicted_trajectory = not show_predicted_trajectory
				if show_predicted_trajectory:
					_calculate_predicted_trajectory()
			KEY_M:
				show_solar_system = not show_solar_system
			KEY_G:
				show_grid = not show_grid
			KEY_V:
				show_vectors = not show_vectors
			KEY_H:
				guidance_enabled = not guidance_enabled
				if not guidance_enabled:
					autopilot_enabled = false
					thrust_key_down = false
			KEY_Q:
				gimbal_angle = clampf(gimbal_angle - deg_to_rad(1.0), deg_to_rad(-8.0), deg_to_rad(8.0))
			KEY_E:
				gimbal_angle = clampf(gimbal_angle + deg_to_rad(1.0), deg_to_rad(-8.0), deg_to_rad(8.0))
			KEY_X:
				_separate_stage()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if show_solar_system:
				solar_map_zoom = minf(8.0, solar_map_zoom * 1.2)
			else:
				camera_zoom = minf(0.0025, camera_zoom * 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if show_solar_system:
				solar_map_zoom = maxf(0.25, solar_map_zoom / 1.2)
			else:
				camera_zoom = maxf(0.0000005, camera_zoom / 1.2)

func _draw() -> void:
	var view_center := get_viewport_rect().size * 0.5
	var world_scale_factor := _visual_scale()
	var radius_px := maxf(4.0, EARTH_RADIUS * camera_zoom * world_scale_factor)
	var rocket_screen := view_center
	var radial_direction := rocket_position.normalized()
	var altitude_for_view := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
	var altitude_visual_scale := camera_zoom * world_scale_factor
	var earth_screen := view_center - radial_direction * (radius_px + altitude_for_view * altitude_visual_scale)
	camera_offset = rocket_position

	for star in star_points:
		var p := view_center + star * 0.035
		draw_circle(p, 1.0, Color(0.55, 0.7, 0.9, 0.5))

	if show_solar_system:
		_draw_solar_system(view_center)
		_draw_hud()
		return

	if show_grid:
		_draw_grid(view_center)

	draw_circle(earth_screen, radius_px + 7, Color(0.15, 0.35, 0.58, 0.12))
	draw_circle(earth_screen, radius_px, Color(0.10, 0.28, 0.53))
	draw_arc(earth_screen, radius_px, 0, TAU, 120, Color(0.28, 0.64, 0.95), 2.0)
	draw_arc(earth_screen, radius_px * 0.76, -0.4, 2.4, 48, Color(0.18, 0.43, 0.48, 0.45), 2.0)
	draw_arc(earth_screen, radius_px * 0.53, 2.2, 5.4, 48, Color(0.18, 0.43, 0.48, 0.35), 2.0)
	var object_scale := clampf(camera_zoom * world_scale_factor / 0.000045, 0.12, 5.0)
	var pad_width := clampf(34.0 * object_scale, 9.0, 85.0)
	var pad_height := clampf(7.0 * object_scale, 3.0, 18.0)
	var pad_y := earth_screen.y - radius_px - 2.0 * object_scale
	draw_line(Vector2(earth_screen.x - pad_width, pad_y), Vector2(earth_screen.x + pad_width, pad_y), Color(0.65, 0.72, 0.82), 3.0 * object_scale)
	draw_line(Vector2(earth_screen.x - 20.0 * object_scale, pad_y), Vector2(earth_screen.x - 20.0 * object_scale, pad_y + pad_height), Color(0.65, 0.72, 0.82), 2.0 * object_scale)
	draw_line(Vector2(earth_screen.x + 20.0 * object_scale, pad_y), Vector2(earth_screen.x + 20.0 * object_scale, pad_y + pad_height), Color(0.65, 0.72, 0.82), 2.0 * object_scale)
	draw_string(ThemeDB.fallback_font, earth_screen + Vector2(radius_px + 12, 4), "EARTH", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.78, 1.0))

	var moon_world := PlanetarySystem.moon_position(sim_time)
	var moon_screen := rocket_screen + (moon_world - rocket_position) * camera_zoom * world_scale_factor
	var moon_radius_px := maxf(2.0, PlanetarySystem.MOON_RADIUS * camera_zoom * world_scale_factor)
	if moon_screen.x > -moon_radius_px and moon_screen.x < size.x + moon_radius_px and moon_screen.y > -moon_radius_px and moon_screen.y < size.y + moon_radius_px:
		draw_circle(moon_screen, moon_radius_px + 3.0, Color(0.55, 0.58, 0.66, 0.16))
		draw_circle(moon_screen, moon_radius_px, Color(0.48, 0.49, 0.52))
		draw_arc(moon_screen, moon_radius_px, 0.0, TAU, 64, Color(0.72, 0.74, 0.78), 1.0)
		draw_string(ThemeDB.fallback_font, moon_screen + Vector2(moon_radius_px + 8.0, 4.0), "MOON", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.78, 0.84))

	if show_orbit:
		_draw_orbit(rocket_screen, earth_screen, radius_px, world_scale_factor)

	if trail.size() > 1:
		var trail_points := PackedVector2Array()
		for p_world in trail:
			trail_points.append(view_center + (p_world - rocket_position) * camera_zoom * world_scale_factor + (rocket_screen - view_center))
		draw_polyline(trail_points, Color(0.2, 0.85, 0.95, 0.7), 2.0)

	if show_predicted_trajectory and predicted_path.size() > 1:
		var prediction_points := PackedVector2Array()
		for point in predicted_path:
			prediction_points.append(rocket_screen + (point - rocket_position) * camera_zoom * world_scale_factor)
		draw_polyline(prediction_points, Color(1.0, 0.72, 0.22, 0.85), 2.0)
	_draw_rocket(rocket_screen + Vector2.UP.rotated(rotation_angle) * 14.0 * object_scale, object_scale)
	if show_vectors:
		var velocity_end := rocket_screen + velocity.normalized() * 65.0
		draw_line(rocket_screen, velocity_end, Color(0.25, 0.9, 0.55), 2.0)
		draw_string(ThemeDB.fallback_font, velocity_end + Vector2(6, 0), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.9, 0.55))

	_draw_hud()

func _draw_solar_system(center: Vector2) -> void:
	var map_scale := minf(size.x, size.y) * 0.43 / 4.4951e12 * solar_map_zoom
	draw_circle(center, 5.0, Color(1.0, 0.78, 0.28))
	draw_string(ThemeDB.fallback_font, center + Vector2(10, 4), "SUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.82, 0.48))
	for planet in PlanetarySystem.PLANETS:
		var orbit_radius := float(planet.semi_major_axis) * map_scale
		draw_arc(center, orbit_radius, 0.0, TAU, 180, Color(0.28, 0.43, 0.58, 0.42), 1.0)
		var period := float(planet.orbital_period) * 86400.0
		var angle := TAU * sim_time / period
		var planet_position := center + Vector2(cos(angle), sin(angle)) * orbit_radius
		var planet_radius := clampf(pow(float(planet.radius) / EARTH_RADIUS, 0.45) * 3.0, 2.0, 8.0)
		var planet_color := Color(0.32, 0.62, 0.88)
		if planet.name == "Earth":
			planet_color = Color(0.22, 0.68, 1.0)
		elif planet.name == "Mars":
			planet_color = Color(0.88, 0.39, 0.24)
		elif planet.name == "Jupiter":
			planet_color = Color(0.82, 0.66, 0.48)
		elif planet.name == "Saturn":
			planet_color = Color(0.82, 0.75, 0.53)
		draw_circle(planet_position, planet_radius, planet_color)
		draw_string(ThemeDB.fallback_font, planet_position + Vector2(planet_radius + 5.0, 4.0), str(planet.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.72, 0.82, 0.92))
	draw_string(ThemeDB.fallback_font, Vector2(24, size.y - 420.0 * clampf(minf(size.x / 1440.0, size.y / 900.0), 0.7, 1.0)), "SOLAR SYSTEM OVERVIEW  •  ALL PLANETARY ORBITS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.8, 1.0))

func _calculate_predicted_trajectory() -> void:
	predicted_path.clear()
	var position := rocket_position
	var predicted_velocity := velocity
	var predicted_fuel := fuel
	var predicted_stage := stage_index
	var dt := 5.0
	for i in range(360):
		var mass := payload_mass
		var active: Dictionary = {}
		var total_flow := 0.0
		var thrust_force := 0.0
		var burn := 0.0
		if predicted_stage < rocket_stages.size():
			active = rocket_stages[predicted_stage]
			mass += float(active.get("dry_mass", 0.0)) + predicted_fuel
			for j in range(predicted_stage + 1, rocket_stages.size()):
				var upper: Dictionary = rocket_stages[j]
				mass += float(upper.get("dry_mass", 0.0)) + float(upper.get("fuel_capacity", 0.0))
			total_flow = float(active.get("flow", 0.0)) * float(active.get("engine_count", 1))
			burn = minf(predicted_fuel, total_flow * throttle * dt)
			var pressure_ratio := PlanetarySystem.atmospheric_pressure(position.length() - EARTH_RADIUS) / 101325.0
			thrust_force = lerpf(float(active.get("vacuum_thrust", 0.0)), float(active.get("thrust", 0.0)), clampf(pressure_ratio, 0.0, 1.0)) * float(active.get("engine_count", 1)) * throttle
		var mass_after := maxf(1.0, mass - burn)
		var mass_mid := (mass + mass_after) * 0.5
		var thrust_delta_v := 0.0
		if burn > 0.0 and total_flow > 0.0 and thrust_force > 0.0:
			thrust_delta_v = thrust_force / total_flow * log(mass / mass_after)
		var thrust_impulse := Vector2.UP.rotated(rotation_angle + gimbal_angle) * thrust_delta_v
		var step_time := sim_time + float(i) * dt
		var initial_gravity := PlanetarySystem.gravity_acceleration(position, step_time)
		var initial_aero := _aerodynamic_acceleration(position, predicted_velocity, mass_mid)
		var half_velocity := predicted_velocity + (initial_gravity + initial_aero) * (0.5 * dt) + thrust_impulse * 0.5
		var next_position := position + half_velocity * dt
		var final_gravity := PlanetarySystem.gravity_acceleration(next_position, step_time + dt)
		var final_aero := _aerodynamic_acceleration(next_position, half_velocity, mass_mid)
		predicted_velocity = half_velocity + (final_gravity + final_aero) * (0.5 * dt) + thrust_impulse * 0.5
		position = next_position
		predicted_fuel = maxf(0.0, predicted_fuel - burn)
		if predicted_fuel <= 0.0001 and predicted_stage < rocket_stages.size() - 1:
			predicted_stage += 1
			predicted_fuel = float(rocket_stages[predicted_stage].get("fuel_capacity", 0.0))
		predicted_path.append(position)
		if position.length() < EARTH_RADIUS:
			break

func _draw_grid(center: Vector2) -> void:
	var spacing := 80.0
	for x in range(0, int(size.x / spacing) + 1):
		var px := x * spacing
		draw_line(Vector2(px, 0), Vector2(px, size.y), Color(0.18, 0.28, 0.4, 0.12), 1.0)
	for y in range(0, int(size.y / spacing) + 1):
		var py := y * spacing
		draw_line(Vector2(0, py), Vector2(size.x, py), Color(0.18, 0.28, 0.4, 0.12), 1.0)

func _draw_orbit(rocket_screen: Vector2, earth_screen: Vector2, radius_px: float, factor: float) -> void:
	var r := rocket_position.length()
	var speed_sq := velocity.length_squared()
	var specific_energy := speed_sq * 0.5 - G * EARTH_MASS / r
	if specific_energy >= 0:
		return
	var semi_major := -G * EARTH_MASS / (2.0 * specific_energy)
	var angular_momentum := rocket_position.x * velocity.y - rocket_position.y * velocity.x
	var eccentricity_sq := maxf(0.0, 1.0 + 2.0 * specific_energy * angular_momentum * angular_momentum / pow(G * EARTH_MASS, 2.0))
	var eccentricity := sqrt(eccentricity_sq)
	var periapsis := semi_major * (1.0 - eccentricity)
	var apoapsis := semi_major * (1.0 + eccentricity)
	if periapsis <= EARTH_RADIUS:
		return
	var points := PackedVector2Array()
	var direction := atan2(rocket_position.y, rocket_position.x)
	for i in range(121):
		var theta := TAU * float(i) / 120.0
		var radius := semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(theta))
		var local := Vector2(cos(theta + direction), sin(theta + direction)) * radius
		points.append(rocket_screen + (local - rocket_position) * camera_zoom * factor)
	draw_polyline(points, Color(0.2, 0.75, 1.0, 0.5), 1.5)

func _draw_rocket(p: Vector2, object_scale: float) -> void:
	var forward := Vector2.UP.rotated(rotation_angle)
	var side := Vector2.RIGHT.rotated(rotation_angle)
	var tip := p + forward * 17.0 * object_scale
	var left := p - forward * 12.0 * object_scale - side * 6.0 * object_scale
	var right := p - forward * 12.0 * object_scale + side * 6.0 * object_scale
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.82, 0.88, 0.94))
	draw_line(left, right, Color(0.25, 0.55, 0.78), 1.5)
	if throttle > 0.0 and fuel > 0.0:
		var flame_base := p - forward * 12.0 * object_scale
		var flame_tip := p - forward * (28.0 + randf_range(0, 8)) * object_scale
		draw_colored_polygon(PackedVector2Array([flame_base - side * 3 * object_scale, flame_tip, flame_base + side * 3 * object_scale]), Color(1.0, 0.48, 0.12, 0.9))

func _draw_hud() -> void:
	var ui_scale := clampf(minf(size.x / 1440.0, size.y / 900.0), 0.7, 1.0)
	var altitude := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
	var orbital_speed := velocity.length()
	var periapsis := _apsis(false)
	var apoapsis := _apsis(true)
	var local_gravity := G * EARTH_MASS / pow(rocket_position.length(), 2.0)
	var current_thrust := _engine_thrust(altitude)
	var current_mass := _current_vehicle_mass()
	var active_fuel_capacity := float(_active_stage_data().get("fuel_capacity", 1.0))
	var thrust_to_weight := current_thrust / (current_mass * local_gravity)
	var remaining_delta_v := _remaining_ideal_delta_v(current_mass)
	var lines := [
		"ALTITUDE       %s" % _format_distance(altitude),
		"VELOCITY       %s" % _format_speed(orbital_speed),
		"FUEL           %s%%" % str(roundi(100.0 * fuel / maxf(1.0, active_fuel_capacity))),
		"THROTTLE       %s%%" % str(roundi(throttle * 100.0)),
		"THRUST / WEIGHT %.2f" % thrust_to_weight,
		"IDEAL ΔV EST.  %.2f km/s" % (remaining_delta_v / 1000.0),
		"STAGE          %d / %d" % [stage_index + 1, rocket_stages.size()],
		"MACH NUMBER    %.2f" % mach_number,
		"DYNA PRESSURE  %.1f kPa" % (dynamic_pressure_pa / 1000.0),
		"HEAT FLUX      %.2f MW/m²" % heat_flux_mw,
		"SHIELD TEMP    %.0f K" % heat_shield_temperature,
		"PEAK HEATING   %.2f MW/m²" % peak_heat_flux_mw,
		"GUIDANCE       %s" % ("AUTO" if guidance_enabled else "MANUAL"),
		"PERIAPSIS      %s" % _format_distance(periapsis),
		"APOAPSIS       %s" % _format_distance(apoapsis),
		"MISSION TIME   %s" % _format_time(sim_time),
		"TIME WARP      x%s" % str(snappedf(time_warp, 0.01))
	]
	var box := Rect2(Vector2(18.0 * ui_scale, size.y - 435.0 * ui_scale), Vector2(310.0 * ui_scale, 415.0 * ui_scale))
	draw_rect(box, Color(0.015, 0.035, 0.065, 0.86), true)
	draw_rect(box, Color(0.18, 0.42, 0.6, 0.7), false, 1.0)
	for i in range(lines.size()):
		draw_string(ThemeDB.fallback_font, Vector2(32.0 * ui_scale, size.y - 408.0 * ui_scale + i * 23.0 * ui_scale), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(13.0 * ui_scale)), Color(0.68, 0.82, 0.94))
	draw_string(ThemeDB.fallback_font, Vector2(315.0 * ui_scale, size.y - 28.0 * ui_scale), status_message, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(13.0 * ui_scale)), Color(0.35, 0.85, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 280.0 * ui_scale, size.y - 28.0 * ui_scale), realism.to_upper() + "  /  " + world_scale.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, roundi(12.0 * ui_scale)), Color(0.48, 0.68, 0.84))

func _remaining_ideal_delta_v(current_mass: float) -> float:
	var total := 0.0
	var mass := current_mass
	for i in range(stage_index, rocket_stages.size()):
		var stage: Dictionary = rocket_stages[i]
		var propellant := fuel if i == stage_index else float(stage.get("fuel_capacity", 0.0))
		var dry := float(stage.get("dry_mass", 0.0))
		var engines := float(stage.get("engine_count", 1))
		var thrust := float(stage.get("vacuum_thrust", 0.0)) * engines
		var flow := float(stage.get("flow", 0.0)) * engines
		var final_mass := mass - propellant
		if propellant > 0.0 and flow > 0.0 and thrust > 0.0 and final_mass > dry:
			total += thrust / flow * log(mass / final_mass)
		mass = final_mass - dry
	return total

func _apsis(apo: bool) -> float:
	var r := rocket_position.length()
	var energy := velocity.length_squared() * 0.5 - G * EARTH_MASS / r
	if energy >= 0:
		return INF if apo else 0.0
	var a := -G * EARTH_MASS / (2.0 * energy)
	var h := rocket_position.x * velocity.y - rocket_position.y * velocity.x
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * energy * h * h / pow(G * EARTH_MASS, 2.0)))
	return a * (1.0 + e if apo else 1.0 - e) - EARTH_RADIUS

func _visual_scale() -> float:
	match world_scale:
		"Balanced":
			return 0.55
		"Realistic distances":
			return 0.22
		_:
			return 1.0

func _format_distance(value: float) -> String:
	if is_inf(value):
		return "ESCAPE"
	if absf(value) >= 1000000.0:
		return "%.2f Mm" % (value / 1000000.0)
	return "%.0f km" % (value / 1000.0)

func _format_speed(value: float) -> String:
	return "%.0f m/s" % value

func _format_time(value: float) -> String:
	var total := int(value)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]

func get_save_data() -> Dictionary:
	return {
		"sim_time": sim_time,
		"position": [rocket_position.x, rocket_position.y],
		"velocity": [velocity.x, velocity.y],
		"rotation_angle": rotation_angle,
		"fuel": fuel,
		"stage_index": stage_index,
		"discarded_stage_mass": discarded_stage_mass,
		"gimbal_angle": gimbal_angle,
		"guidance_enabled": guidance_enabled,
		"autopilot_enabled": autopilot_enabled,
		"autopilot_target_altitude": autopilot_target_altitude,
		"autopilot_target_mode": autopilot_target_mode,
		"autopilot_planet_index": autopilot_planet_index,
		"autopilot_burn_remaining": autopilot_burn_remaining,
		"autopilot_transfer_direction": autopilot_transfer_direction,
		"autopilot_complete": autopilot_complete,
		"autopilot_phase": autopilot_phase,
		"heat_shield_temperature": heat_shield_temperature,
		"peak_heat_flux_mw": peak_heat_flux_mw,
		"throttle": throttle,
		"time_warp": time_warp,
		"paused": paused,
		"rocket_design": {"payload_mass": payload_mass, "stages": rocket_stages.duplicate(true)}
	}

func load_save_data(data: Dictionary) -> void:
	var saved_design: Variant = data.get("rocket_design", null)
	if saved_design is Dictionary:
		set_rocket_design(saved_design)
	stage_index = clampi(int(data.get("stage_index", 0)), 0, maxi(0, rocket_stages.size() - 1))
	sim_time = float(data.get("sim_time", 0.0))
	var p: Array = data.get("position", [0.0, -EARTH_RADIUS - 2.0])
	var v: Array = data.get("velocity", [EARTH_RADIUS * EARTH_ROTATION_RATE, 0.0])
	rocket_position = Vector2(float(p[0]), float(p[1]))
	velocity = Vector2(float(v[0]), float(v[1]))
	rotation_angle = float(data.get("rotation_angle", 0.0))
	fuel = float(data.get("fuel", _active_stage_data().get("fuel_capacity", 0.0)))
	discarded_stage_mass = float(data.get("discarded_stage_mass", 0.0))
	gimbal_angle = float(data.get("gimbal_angle", 0.0))
	guidance_enabled = bool(data.get("guidance_enabled", false))
	autopilot_enabled = bool(data.get("autopilot_enabled", false))
	autopilot_target_altitude = float(data.get("autopilot_target_altitude", 200000.0))
	autopilot_target_mode = str(data.get("autopilot_target_mode", "ORBIT"))
	autopilot_planet_index = int(data.get("autopilot_planet_index", -1))
	autopilot_burn_remaining = float(data.get("autopilot_burn_remaining", 0.0))
	autopilot_transfer_direction = float(data.get("autopilot_transfer_direction", 1.0))
	autopilot_complete = bool(data.get("autopilot_complete", false))
	autopilot_phase = str(data.get("autopilot_phase", "IDLE"))
	heat_shield_temperature = float(data.get("heat_shield_temperature", 290.0))
	peak_heat_flux_mw = float(data.get("peak_heat_flux_mw", 0.0))
	throttle = float(data.get("throttle", 0.0))
	thrust_key_down = false
	time_warp = float(data.get("time_warp", 1.0))
	paused = bool(data.get("paused", false))
	trail.clear()
