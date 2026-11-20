extends Control

const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const G := PlanetarySystem.G
const EARTH_MASS := PlanetarySystem.EARTH_MASS
const EARTH_RADIUS := PlanetarySystem.EARTH_RADIUS
const ROCKET_DRY_MASS := 12000.0
const FUEL_CAPACITY := 80000.0
const ENGINE_THRUST := 2.4e6
const FUEL_FLOW := 550.0

var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var paused := false
var sim_time := 0.0
var time_warp := 1.0
var rocket_position := Vector2(0, -EARTH_RADIUS - 2.0)
var velocity := Vector2.ZERO
var rotation_angle := 0.0
var fuel := FUEL_CAPACITY
var throttle := 0.0
var camera_zoom := 0.000045
var camera_offset := Vector2.ZERO
var trail: Array[Vector2] = []
var trail_timer := 0.0
var star_points: Array[Vector2] = []
var status_message := "PAD READY  •  HOLD W / ↑ TO LAUNCH"
var orbit_path: Array[Vector2] = []
var show_orbit := true
var show_grid := true
var show_vectors := true
var thrust_key_down := false

func _ready() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 44219
    for i in range(500):
        star_points.append(Vector2(rng.randf_range(-12000, 12000), rng.randf_range(-8000, 8000)))
    set_process(true)

func _process(delta: float) -> void:
    if not paused:
        var steps := maxi(1, int(ceil(time_warp * delta / 0.05)))
        var step_delta := time_warp * delta / float(steps)
        for i in range(steps):
            _physics_step(step_delta)
    trail_timer += delta
    if trail_timer >= 0.12:
        trail_timer = 0.0
        trail.append(rocket_position)
        if trail.size() > 450:
            trail.pop_front()
    queue_redraw()

func _physics_step(dt: float) -> void:
    sim_time += dt
    var radial := rocket_position.normalized()
    var altitude := rocket_position.length() - EARTH_RADIUS
    if altitude < 0.5:
        rocket_position = radial * (EARTH_RADIUS + 0.5)
        var inward_speed := velocity.dot(radial)
        if inward_speed < 0.0:
            velocity -= radial * inward_speed

    throttle = 1.0 if thrust_key_down else 0.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        throttle = 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        throttle = 0.0

    var thrust_accel := Vector2.ZERO
    if fuel <= 0.0:
        throttle = 0.0
    if throttle > 0.0 and fuel > 0.0:
        var mass := ROCKET_DRY_MASS + fuel
        thrust_accel = Vector2.UP.rotated(rotation_angle) * (ENGINE_THRUST * throttle / mass)
        var consumed := minf(fuel, FUEL_FLOW * throttle * dt)
        fuel -= consumed

    var initial_gravity := PlanetarySystem.gravity_acceleration(rocket_position, sim_time - dt)
    velocity += (initial_gravity + thrust_accel) * (0.5 * dt)
    rocket_position += velocity * dt
    var final_gravity := PlanetarySystem.gravity_acceleration(rocket_position, sim_time)
    velocity += (final_gravity + thrust_accel) * (0.5 * dt)

    if realism in ["Realistic", "Hardcore"]:
        var altitude := rocket_position.length() - EARTH_RADIUS
        if altitude < 120000.0:
            var density := PlanetarySystem.atmospheric_density(altitude)
            var speed := velocity.length()
            var drag_factor := 0.5 * density * speed * speed * 0.45 / maxf(1.0, ROCKET_DRY_MASS + fuel)
            velocity -= velocity.normalized() * drag_factor * dt

    var final_radius := rocket_position.length()
    if final_radius < EARTH_RADIUS + 0.5:
        var surface_normal := rocket_position.normalized()
        rocket_position = surface_normal * (EARTH_RADIUS + 0.5)
        var surface_velocity := velocity.dot(surface_normal)
        if surface_velocity < 0.0:
            velocity -= surface_normal * surface_velocity

    status_message = "ENGINE FIRING  •  T+%s" % _format_time(sim_time) if throttle > 0.0 and fuel > 0.0 else "PAD READY  •  HOLD W / ↑ TO LAUNCH" if altitude < 100.0 else "FLIGHT ACTIVE"

func _input(event: InputEvent) -> void:
    if event is InputEventKey:
        if event.keycode in [KEY_W, KEY_UP] or event.physical_keycode in [KEY_W, KEY_UP]:
            thrust_key_down = event.pressed
        if event.keycode in [KEY_S, KEY_DOWN] or event.physical_keycode in [KEY_S, KEY_DOWN]:
            if event.pressed:
                thrust_key_down = false

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_A, KEY_LEFT:
                rotation_angle -= 0.12
            KEY_D, KEY_RIGHT:
                rotation_angle += 0.12
            KEY_SPACE:
                paused = not paused
            KEY_EQUAL, KEY_KP_ADD:
                time_warp = minf(100.0, time_warp * 2.0)
            KEY_MINUS, KEY_KP_SUBTRACT:
                time_warp = maxf(0.25, time_warp / 2.0)
            KEY_O:
                show_orbit = not show_orbit
            KEY_G:
                show_grid = not show_grid
            KEY_V:
                show_vectors = not show_vectors
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            camera_zoom = minf(0.0003, camera_zoom * 1.15)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            camera_zoom = maxf(0.000008, camera_zoom / 1.15)

func _draw() -> void:
    var view_center := get_viewport_rect().size * 0.5
    var world_scale_factor := _visual_scale()
    var earth_screen := view_center + Vector2(0, 0)
    var radius_px := maxf(4.0, EARTH_RADIUS * camera_zoom * world_scale_factor)
    var rocket_screen := view_center + (rocket_position * camera_zoom * world_scale_factor)
    if rocket_screen.distance_to(view_center) > minf(size.x, size.y) * 0.35:
        camera_offset = rocket_position
        rocket_screen = view_center
        earth_screen = view_center - rocket_position * camera_zoom * world_scale_factor

    for star in star_points:
        var p := view_center + star * 0.035
        draw_circle(p, 1.0, Color(0.55, 0.7, 0.9, 0.5))

    if show_grid:
        _draw_grid(view_center)

    var pad_width := 34.0
    var pad_y := earth_screen.y - radius_px - 2.0
    draw_line(Vector2(earth_screen.x - pad_width, pad_y), Vector2(earth_screen.x + pad_width, pad_y), Color(0.65, 0.72, 0.82), 3.0)
    draw_line(Vector2(earth_screen.x - 20.0, pad_y), Vector2(earth_screen.x - 20.0, pad_y + 7.0), Color(0.65, 0.72, 0.82), 2.0)
    draw_line(Vector2(earth_screen.x + 20.0, pad_y), Vector2(earth_screen.x + 20.0, pad_y + 7.0), Color(0.65, 0.72, 0.82), 2.0)

    draw_circle(earth_screen, radius_px + 7, Color(0.15, 0.35, 0.58, 0.12))
    draw_circle(earth_screen, radius_px, Color(0.10, 0.28, 0.53))
    draw_arc(earth_screen, radius_px, 0, TAU, 120, Color(0.28, 0.64, 0.95), 2.0)
    draw_arc(earth_screen, radius_px * 0.76, -0.4, 2.4, 48, Color(0.18, 0.43, 0.48, 0.45), 2.0)
    draw_arc(earth_screen, radius_px * 0.53, 2.2, 5.4, 48, Color(0.18, 0.43, 0.48, 0.35), 2.0)
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

    _draw_rocket(rocket_screen + Vector2.UP.rotated(rotation_angle) * 14.0)
    if show_vectors:
        var velocity_end := rocket_screen + velocity.normalized() * 65.0
        draw_line(rocket_screen, velocity_end, Color(0.25, 0.9, 0.55), 2.0)
        draw_string(ThemeDB.fallback_font, velocity_end + Vector2(6, 0), "V", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.25, 0.9, 0.55))

    _draw_hud()

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

func _draw_rocket(p: Vector2) -> void:
    var forward := Vector2.UP.rotated(rotation_angle)
    var side := Vector2.RIGHT.rotated(rotation_angle)
    var tip := p + forward * 17.0
    var left := p - forward * 12.0 - side * 6.0
    var right := p - forward * 12.0 + side * 6.0
    draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.82, 0.88, 0.94))
    draw_line(left, right, Color(0.25, 0.55, 0.78), 1.5)
    if throttle > 0.0 and fuel > 0.0:
        var flame_base := p - forward * 12.0
        var flame_tip := p - forward * (28.0 + randf_range(0, 8))
        draw_colored_polygon(PackedVector2Array([flame_base - side * 3, flame_tip, flame_base + side * 3]), Color(1.0, 0.48, 0.12, 0.9))

func _draw_hud() -> void:
    var altitude := maxf(0.0, rocket_position.length() - EARTH_RADIUS)
    var orbital_speed := velocity.length()
    var periapsis := _apsis(false)
    var apoapsis := _apsis(true)
    var lines := [
        "ALTITUDE       %s" % _format_distance(altitude),
        "VELOCITY       %s" % _format_speed(orbital_speed),
        "FUEL           %s%%" % str(roundi(100.0 * fuel / FUEL_CAPACITY)),
        "THROTTLE       %s%%" % str(roundi(throttle * 100.0)),
        "PERIAPSIS      %s" % _format_distance(periapsis),
        "APOAPSIS       %s" % _format_distance(apoapsis),
        "MISSION TIME   %s" % _format_time(sim_time),
        "TIME WARP      x%s" % str(snappedf(time_warp, 0.01))
    ]
    var box := Rect2(Vector2(18, size.y - 226), Vector2(270, 205))
    draw_rect(box, Color(0.015, 0.035, 0.065, 0.86), true)
    draw_rect(box, Color(0.18, 0.42, 0.6, 0.7), false, 1.0)
    for i in range(lines.size()):
        draw_string(ThemeDB.fallback_font, Vector2(32, size.y - 200 + i * 23), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.68, 0.82, 0.94))
    draw_string(ThemeDB.fallback_font, Vector2(315, size.y - 28), status_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.35, 0.85, 0.75))
    draw_string(ThemeDB.fallback_font, Vector2(size.x - 280, size.y - 28), realism.to_upper() + "  /  " + world_scale.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.48, 0.68, 0.84))

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
        "throttle": throttle,
        "time_warp": time_warp,
        "paused": paused
    }

func load_save_data(data: Dictionary) -> void:
    sim_time = float(data.get("sim_time", 0.0))
    var p: Array = data.get("position", [0.0, -EARTH_RADIUS - 180000.0])
    var v: Array = data.get("velocity", [7600.0, 0.0])
    rocket_position = Vector2(float(p[0]), float(p[1]))
    velocity = Vector2(float(v[0]), float(v[1]))
    rotation_angle = float(data.get("rotation_angle", 0.0))
    fuel = float(data.get("fuel", FUEL_CAPACITY))
    throttle = float(data.get("throttle", 0.0))
    time_warp = float(data.get("time_warp", 1.0))
    paused = bool(data.get("paused", false))
    trail.clear()
