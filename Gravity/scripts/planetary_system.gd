extends RefCounted

const ContentCatalog = preload("res://scripts/content_catalog.gd")

static var G := 6.67430e-11
static var EARTH_MASS := 5.972e24
static var EARTH_RADIUS := 6.371e6
static var EARTH_ROTATION_RATE := 7.2921159e-5
static var EARTH_SOI_RADIUS := 9.25e8
static var MOON_MASS := 7.342e22
static var MOON_RADIUS := 1.7374e6
static var MOON_ORBIT_RADIUS := 3.8474358321e8
static var MOON_TRANSFER_ORBIT_RADIUS := 3.844e8
static var MOON_ORBIT_ECCENTRICITY := 0.0549
static var MOON_ROTATION_PERIOD := 27.321661 * 86400.0
static var MOON_MEAN_ANOMALY_J2000 := 2.355555
static var MOON_PERIHELION_J2000 := 3.63734
static var MOON_MEAN_MOTION := 2.6616995272e-6
static var MOON_PERIHELION_RATE := 0.0
static var MOON_SOI_RADIUS := 6.61e7
static var MOON_ROTATION_RATE := 2.6616995272e-6
static var MOON_SOLID := true
static var EPHEMERIS_EPOCH_JD := 2461364.5
static var J2000_JD := 2451545.0
static var J2000_CENTURY_DAYS := 36525.0
static var ATMOSPHERE_HEIGHT := 120000.0
static var SEA_LEVEL_DENSITY := 1.225
static var ATMOSPHERE_SCALE_HEIGHT := 8500.0
static var ATMOSPHERE_GRAVITY := 9.80665
static var ATMOSPHERE_GAS_CONSTANT := 287.05287
static var ATMOSPHERE_GAMMA := 1.4
static var ASTRONOMICAL_UNIT := 1.495978707e11
static var SUN_MASS := 1.98847e30
static var SUN_RADIUS := 6.957e8
static var EARTH_ORBIT_PERIOD := 365.256 * 86400.0
static var ATMOSPHERE_BASE_ALTITUDES: Array = []
static var ATMOSPHERE_BASE_TEMPERATURES: Array = []
static var ATMOSPHERE_LAPSE_RATES: Array = []
static var ATMOSPHERE_BASE_PRESSURES: Array = []
static var PLANETS: Array[Dictionary] = []
static var SMALL_BODY_BELTS: Array[Dictionary] = []

static func _static_init() -> void:
	var catalog: Dictionary = ContentCatalog.get_catalog()
	var system: Dictionary = catalog.get("system", {})
	var earth_atmosphere: Dictionary = system.get("earth_atmosphere", {})
	var moon: Dictionary = catalog.get("moon", {})
	G = float(system.get("gravitational_constant", G))
	ASTRONOMICAL_UNIT = float(system.get("astronomical_unit_m", ASTRONOMICAL_UNIT))
	SUN_MASS = float(system.get("sun_mass_kg", SUN_MASS))
	SUN_RADIUS = float(system.get("sun_radius_m", SUN_RADIUS))
	EPHEMERIS_EPOCH_JD = float(system.get("ephemeris_epoch_jd", EPHEMERIS_EPOCH_JD))
	J2000_JD = float(system.get("j2000_jd", J2000_JD))
	J2000_CENTURY_DAYS = float(system.get("j2000_century_days", J2000_CENTURY_DAYS))
	MOON_MASS = float(moon.get("mass_kg", MOON_MASS))
	MOON_RADIUS = float(moon.get("radius_m", MOON_RADIUS))
	MOON_ORBIT_RADIUS = float(moon.get("semi_major_axis_m", MOON_ORBIT_RADIUS))
	MOON_TRANSFER_ORBIT_RADIUS = float(moon.get("transfer_orbit_radius_m", MOON_TRANSFER_ORBIT_RADIUS))
	MOON_ORBIT_ECCENTRICITY = float(moon.get("eccentricity", MOON_ORBIT_ECCENTRICITY))
	MOON_ROTATION_PERIOD = float(moon.get("rotation_period_s", MOON_ROTATION_PERIOD))
	MOON_MEAN_ANOMALY_J2000 = float(moon.get("mean_anomaly_j2000_rad", MOON_MEAN_ANOMALY_J2000))
	MOON_PERIHELION_J2000 = float(moon.get("perihelion_j2000_rad", MOON_PERIHELION_J2000))
	MOON_MEAN_MOTION = float(moon.get("mean_motion_rad_s", MOON_MEAN_MOTION))
	MOON_PERIHELION_RATE = float(moon.get("perihelion_rate_rad_s", MOON_PERIHELION_RATE))
	MOON_SOI_RADIUS = float(moon.get("soi_radius_m", MOON_SOI_RADIUS))
	MOON_ROTATION_RATE = float(moon.get("rotation_rate_rad_s", MOON_ROTATION_RATE))
	MOON_SOLID = bool(moon.get("solid", MOON_SOLID))
	ATMOSPHERE_HEIGHT = float(earth_atmosphere.get("height_m", ATMOSPHERE_HEIGHT))
	SEA_LEVEL_DENSITY = float(earth_atmosphere.get("sea_level_density_kg_m3", SEA_LEVEL_DENSITY))
	ATMOSPHERE_SCALE_HEIGHT = float(earth_atmosphere.get("scale_height_m", ATMOSPHERE_SCALE_HEIGHT))
	ATMOSPHERE_GRAVITY = float(earth_atmosphere.get("gravity_m_s2", ATMOSPHERE_GRAVITY))
	ATMOSPHERE_GAS_CONSTANT = float(earth_atmosphere.get("gas_constant_j_kg_k", ATMOSPHERE_GAS_CONSTANT))
	ATMOSPHERE_GAMMA = float(earth_atmosphere.get("gamma", ATMOSPHERE_GAMMA))
	ATMOSPHERE_BASE_ALTITUDES = earth_atmosphere.get("base_altitudes_m", [])
	ATMOSPHERE_BASE_TEMPERATURES = earth_atmosphere.get("base_temperatures_k", [])
	ATMOSPHERE_LAPSE_RATES = earth_atmosphere.get("lapse_rates_k_m", [])
	ATMOSPHERE_BASE_PRESSURES = earth_atmosphere.get("base_pressures_pa", [])
	for belt_variant in system.get("small_body_belts", []):
		SMALL_BODY_BELTS.append(belt_variant.duplicate(true))
	for planet_variant in catalog.get("planets", []):
		var planet: Dictionary = planet_variant.duplicate(true)
		PLANETS.append(planet)
		if str(planet.get("name", "")) == "Earth":
			EARTH_MASS = float(planet.get("mass", EARTH_MASS))
			EARTH_RADIUS = float(planet.get("radius", EARTH_RADIUS))
			EARTH_ROTATION_RATE = float(planet.get("rotation_rate_rad_s", EARTH_ROTATION_RATE))
			EARTH_SOI_RADIUS = float(planet.get("soi_radius_m", EARTH_SOI_RADIUS))
			EARTH_ORBIT_PERIOD = float(planet.get("orbital_period", 365.256)) * 86400.0

static func get_planet_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for planet in PLANETS:
		result.append(planet.duplicate(true))
	return result

static func get_small_body_belts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for belt in SMALL_BODY_BELTS:
		result.append(belt.duplicate(true))
	return result

static func color_from_rgb(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if not value is Array or value.size() < 3:
		return fallback
	return Color(float(value[0]), float(value[1]), float(value[2]))

static func system_visual_color() -> Color:
	var system: Dictionary = ContentCatalog.get_catalog().get("system", {})
	return color_from_rgb(system.get("sun_color_rgb"), Color(1.0, 0.78, 0.28))

static func planet_visual_data(planet_name: String) -> Dictionary:
	if planet_name == "Moon":
		var moon: Dictionary = ContentCatalog.get_catalog().get("moon", {})
		return {
			"color": color_from_rgb(moon.get("color_rgb"), Color(0.72, 0.74, 0.78)),
			"atmosphere_height": 0.0,
			"atmosphere_color": Color.TRANSPARENT,
			"has_rings": false,
			"ring_color": Color.WHITE,
			"ring_inner_ratio": 1.0,
			"ring_outer_ratio": 1.0,
			"ring_opacity": 0.0
		}
	var satellite := _satellite_data(planet_name)
	if not satellite.is_empty():
		var atmosphere: Dictionary = satellite.get("atmosphere", {})
		var satellite_color: Color = color_from_rgb(satellite.get("color_rgb"), Color.WHITE)
		return {
			"color": satellite_color,
			"surface_color": satellite_color,
			"atmosphere_height": float(atmosphere.get("visual_height_m", atmosphere.get("height_m", 0.0))),
			"atmosphere_color": color_from_rgb(atmosphere.get("color_rgb"), Color.TRANSPARENT),
			"has_rings": false,
			"ring_color": Color.WHITE,
			"ring_inner_ratio": 1.0,
			"ring_outer_ratio": 1.0,
			"ring_opacity": 0.0
		}
	var planet := _planet_data(planet_name)
	if planet.is_empty():
		return {}
	var atmosphere: Dictionary = planet.get("atmosphere", {})
	var rings: Dictionary = planet.get("rings", {})
	var has_rings := bool(rings.get("enabled", false))
	return {
		"color": color_from_rgb(planet.get("color_rgb"), Color.WHITE),
		"surface_color": color_from_rgb(planet.get("surface_color_rgb"), color_from_rgb(planet.get("color_rgb"), Color.WHITE)),
		"atmosphere_height": float(atmosphere.get("visual_height_m", atmosphere.get("height_m", 0.0))),
		"atmosphere_color": color_from_rgb(atmosphere.get("color_rgb"), Color.TRANSPARENT),
		"has_rings": has_rings,
		"ring_color": color_from_rgb(rings.get("color_rgb"), Color.WHITE),
		"ring_inner_ratio": float(rings.get("inner_radius_ratio", 1.2)),
		"ring_outer_ratio": float(rings.get("outer_radius_ratio", 2.0)),
		"ring_opacity": float(rings.get("opacity", 0.5 if has_rings else 0.0))
	}

static func _planet_data(planet_name: String) -> Dictionary:
	for planet in PLANETS:
		if str(planet.get("name", "")) == planet_name:
			return planet
	return {}

static func _satellite_data(satellite_body_name: String) -> Dictionary:
	for planet in PLANETS:
		for satellite_variant in planet.get("satellites", []):
			var satellite: Dictionary = satellite_variant
			var full_name := "%s %s" % [str(planet.get("name", "")), str(satellite.get("name", ""))]
			if full_name == satellite_body_name:
				return satellite
	return {}

static func _earth_planet_data() -> Dictionary:
	return _planet_data("Earth")

static func _ephemeris_centuries(time_seconds: float) -> float:
	return (EPHEMERIS_EPOCH_JD + time_seconds / 86400.0 - J2000_JD) / J2000_CENTURY_DAYS

static func _solve_kepler(mean_anomaly: float, eccentricity: float) -> float:
	var mean := wrapf(mean_anomaly, -PI, PI)
	var eccentric := mean + eccentricity * sin(mean)
	for i in range(15):
		var correction := (eccentric - eccentricity * sin(eccentric) - mean) / (1.0 - eccentricity * cos(eccentric))
		eccentric -= correction
		if absf(correction) < 1.0e-12:
			break
	return eccentric

static func _planet_position_components_at_century(planet: Dictionary, centuries: float) -> PackedFloat64Array:
	var a := (float(planet.a) + float(planet.adot) * centuries) * ASTRONOMICAL_UNIT
	var eccentricity := float(planet.e) + float(planet.edot) * centuries
	var inclination := deg_to_rad(float(planet.i) + float(planet.idot) * centuries)
	var mean_longitude := deg_to_rad(float(planet.L) + float(planet.Ldot) * centuries)
	var perihelion := deg_to_rad(float(planet.peri) + float(planet.peridot) * centuries)
	var node := deg_to_rad(float(planet.node) + float(planet.nodedot) * centuries)
	var mean_anomaly := wrapf(mean_longitude - perihelion, -PI, PI)
	var eccentric_anomaly := _solve_kepler(mean_anomaly, eccentricity)
	var x_orbit := a * (cos(eccentric_anomaly) - eccentricity)
	var y_orbit := a * sqrt(1.0 - eccentricity * eccentricity) * sin(eccentric_anomaly)
	var argument := perihelion - node
	var x := (cos(argument) * cos(node) - sin(argument) * sin(node) * cos(inclination)) * x_orbit + (-sin(argument) * cos(node) - cos(argument) * sin(node) * cos(inclination)) * y_orbit
	var y := (cos(argument) * sin(node) + sin(argument) * cos(node) * cos(inclination)) * x_orbit + (-sin(argument) * sin(node) + cos(argument) * cos(node) * cos(inclination)) * y_orbit
	return PackedFloat64Array([x, y])

static func _planet_position_at_century(planet: Dictionary, centuries: float) -> Vector2:
	var components := _planet_position_components_at_century(planet, centuries)
	return Vector2(components[0], components[1])

static func _planet_heliocentric_state(planet: Dictionary, time_seconds: float) -> Dictionary:
	var centuries := _ephemeris_centuries(time_seconds)
	var step_seconds := minf(float(planet.orbital_period) * 86400.0 * 0.001, 86400.0)
	var step_centuries := step_seconds / (86400.0 * J2000_CENTURY_DAYS)
	var position_components := _planet_position_components_at_century(planet, centuries)
	var previous_components := _planet_position_components_at_century(planet, centuries - step_centuries)
	var next_components := _planet_position_components_at_century(planet, centuries + step_centuries)
	var velocity_components := PackedFloat64Array([
		(next_components[0] - previous_components[0]) / (2.0 * step_seconds),
		(next_components[1] - previous_components[1]) / (2.0 * step_seconds)
	])
	return {
		"position": Vector2(position_components[0], position_components[1]),
		"position_components": position_components,
		"velocity": Vector2(velocity_components[0], velocity_components[1]),
		"velocity_components": velocity_components
	}

static func _satellite_orbit_state(satellite: Dictionary, time_seconds: float) -> Dictionary:
	var radius := float(satellite.get("semi_major_axis_m", 0.0))
	var period := float(satellite.get("orbital_period_s", 0.0))
	if radius <= 0.0 or period <= 0.0:
		return {"position": Vector2.ZERO, "velocity": Vector2.ZERO}
	var direction := -1.0 if float(satellite.get("orbital_direction", 1.0)) < 0.0 else 1.0
	var angular_rate := TAU / period * direction
	var angle := wrapf(float(satellite.get("phase_rad", 0.0)) + angular_rate * time_seconds, -PI, PI)
	var position := Vector2(cos(angle), sin(angle)) * radius
	var velocity := Vector2(-sin(angle), cos(angle)) * radius * angular_rate
	return {"position": position, "velocity": velocity}

static func moon_state(time_seconds: float) -> Dictionary:
	var days_since_j2000 := EPHEMERIS_EPOCH_JD - J2000_JD + time_seconds / 86400.0
	var mean_anomaly := MOON_MEAN_ANOMALY_J2000 + MOON_MEAN_MOTION * days_since_j2000 * 86400.0
	var perihelion := MOON_PERIHELION_J2000 + MOON_PERIHELION_RATE * days_since_j2000 * 86400.0
	var eccentric_anomaly := _solve_kepler(mean_anomaly, MOON_ORBIT_ECCENTRICITY)
	var root := sqrt(1.0 - MOON_ORBIT_ECCENTRICITY * MOON_ORBIT_ECCENTRICITY)
	var x := MOON_ORBIT_RADIUS * (cos(eccentric_anomaly) - MOON_ORBIT_ECCENTRICITY)
	var y := MOON_ORBIT_RADIUS * root * sin(eccentric_anomaly)
	var eccentric_rate := MOON_MEAN_MOTION / (1.0 - MOON_ORBIT_ECCENTRICITY * cos(eccentric_anomaly))
	var vx := -MOON_ORBIT_RADIUS * sin(eccentric_anomaly) * eccentric_rate
	var vy := MOON_ORBIT_RADIUS * root * cos(eccentric_anomaly) * eccentric_rate
	var perihelion_cos := cos(perihelion)
	var perihelion_sin := sin(perihelion)
	var position_x := x * perihelion_cos - y * perihelion_sin
	var position_y := x * perihelion_sin + y * perihelion_cos
	var velocity_x := vx * perihelion_cos - vy * perihelion_sin - position_y * MOON_PERIHELION_RATE
	var velocity_y := vx * perihelion_sin + vy * perihelion_cos + position_x * MOON_PERIHELION_RATE
	var position_components := PackedFloat64Array([position_x, position_y])
	var velocity_components := PackedFloat64Array([velocity_x, velocity_y])
	return {
		"position": Vector2(position_x, position_y),
		"position_components": position_components,
		"velocity": Vector2(velocity_x, velocity_y),
		"velocity_components": velocity_components
	}

static func moon_position(time_seconds: float) -> Vector2:
	return moon_state(time_seconds).position

static func moon_velocity(time_seconds: float) -> Vector2:
	return moon_state(time_seconds).velocity

static func gravity_body_states(time_seconds: float) -> Dictionary:
	var barycentre_state := _planet_heliocentric_state(_earth_planet_data(), time_seconds)
	var moon_state_value := moon_state(time_seconds)
	var moon_position_components: PackedFloat64Array = moon_state_value.position_components
	var moon_velocity_components: PackedFloat64Array = moon_state_value.velocity_components
	var moon_position_value := Vector2(moon_position_components[0], moon_position_components[1])
	var moon_velocity_value := Vector2(moon_velocity_components[0], moon_velocity_components[1])
	var earth_moon_ratio: float = MOON_MASS / (EARTH_MASS + MOON_MASS)
	var earth_state := _earth_heliocentric_state(time_seconds)
	var earth_position: Vector2 = earth_state.position
	var earth_velocity: Vector2 = earth_state.velocity
	var earth_position_components: PackedFloat64Array = earth_state.position_components
	var earth_velocity_components: PackedFloat64Array = earth_state.velocity_components
	var bodies: Array[Dictionary] = [
		{"name": "Sun", "mass": SUN_MASS, "position": -earth_position, "position_components": PackedFloat64Array([-earth_position_components[0], -earth_position_components[1]]), "velocity": -earth_velocity, "velocity_components": PackedFloat64Array([-earth_velocity_components[0], -earth_velocity_components[1]]), "radius": SUN_RADIUS},
		{"name": "Moon", "mass": MOON_MASS, "position": moon_position_value, "position_components": moon_position_components, "velocity": moon_velocity_value, "velocity_components": moon_velocity_components, "radius": MOON_RADIUS}
	]
	var surface_bodies: Array[Dictionary] = [
		{"name": "Earth", "mass": EARTH_MASS, "position": Vector2.ZERO, "position_components": PackedFloat64Array([0.0, 0.0]), "velocity": Vector2.ZERO, "velocity_components": PackedFloat64Array([0.0, 0.0]), "radius": EARTH_RADIUS, "rotation_rate": EARTH_ROTATION_RATE, "solid": true, "soi": EARTH_SOI_RADIUS},
		{"name": "Moon", "mass": MOON_MASS, "position": moon_position_value, "position_components": moon_position_components, "velocity": moon_velocity_value, "velocity_components": moon_velocity_components, "radius": MOON_RADIUS, "rotation_rate": MOON_ROTATION_RATE, "solid": MOON_SOLID, "soi": moon_soi_radius()}
	]
	for planet in PLANETS:
		if planet.name == "Earth":
			continue
		var planet_state := _planet_heliocentric_state(planet, time_seconds)
		var relative_components := _planet_relative_position_components(planet, time_seconds)
		var relative_position := Vector2(relative_components[0], relative_components[1])
		var relative_velocity_components := PackedFloat64Array([
			planet_state.velocity_components[0] - earth_velocity_components[0],
			planet_state.velocity_components[1] - earth_velocity_components[1]
		])
		var relative_velocity := Vector2(relative_velocity_components[0], relative_velocity_components[1])
		var planet_name := str(planet.name)
		var planet_mass := float(planet.mass)
		var planet_radius := float(planet.radius)
		bodies.append({"name": planet_name, "mass": planet_mass, "position": relative_position, "position_components": relative_components, "velocity": relative_velocity, "velocity_components": relative_velocity_components, "radius": planet_radius})
		for satellite_variant in planet.get("satellites", []):
			var satellite: Dictionary = satellite_variant
			var satellite_orbit := _satellite_orbit_state(satellite, time_seconds)
			var satellite_position: Vector2 = relative_position + satellite_orbit.position
			var satellite_velocity: Vector2 = relative_velocity + satellite_orbit.velocity
			var satellite_position_components := PackedFloat64Array([
				relative_components[0] + satellite_orbit.position.x,
				relative_components[1] + satellite_orbit.position.y
			])
			var satellite_velocity_components := PackedFloat64Array([
				relative_velocity_components[0] + satellite_orbit.velocity.x,
				relative_velocity_components[1] + satellite_orbit.velocity.y
			])
			var satellite_name := "%s %s" % [planet_name, str(satellite.get("name", "Moon"))]
			var satellite_mass := float(satellite.get("mass_kg", 0.0))
			var satellite_radius := float(satellite.get("radius_m", 0.0))
			var satellite_soi := maxf(satellite_radius * 1.1, float(satellite.get("semi_major_axis_m", 0.0)) * pow(satellite_mass / (3.0 * planet_mass), 1.0 / 3.0))
			bodies.append({
				"name": satellite_name,
				"mass": satellite_mass,
				"position": satellite_position,
				"position_components": satellite_position_components,
				"velocity": satellite_velocity,
				"velocity_components": satellite_velocity_components,
				"radius": satellite_radius
			})
			surface_bodies.append({
				"name": satellite_name,
				"mass": satellite_mass,
				"position": satellite_position,
				"position_components": satellite_position_components,
				"velocity": satellite_velocity,
				"velocity_components": satellite_velocity_components,
				"radius": satellite_radius,
				"rotation_rate": float(satellite.get("rotation_rate_rad_s", 0.0)),
				"solid": bool(satellite.get("solid", true)),
				"soi": satellite_soi
			})
		surface_bodies.append({
			"name": planet_name,
			"mass": planet_mass,
			"position": relative_position,
			"position_components": relative_components,
			"velocity": relative_velocity,
			"velocity_components": relative_velocity_components,
			"radius": planet_radius,
			"rotation_rate": planetary_rotation_rate(planet_name),
			"solid": bool(planet.get("solid", false)),
			"soi": float(planet.a) * ASTRONOMICAL_UNIT * pow(planet_mass / (3.0 * SUN_MASS), 1.0 / 3.0)
		})
	var moon_heliocentric_components := PackedFloat64Array([
		earth_position_components[0] + moon_position_components[0],
		earth_position_components[1] + moon_position_components[1]
	])
	var moon_heliocentric_velocity_components := PackedFloat64Array([
		earth_velocity_components[0] + moon_velocity_components[0],
		earth_velocity_components[1] + moon_velocity_components[1]
	])
	var heliocentric_bodies: Array[Dictionary] = [
		{"name": "Sun", "mass": SUN_MASS, "position": Vector2.ZERO, "position_components": PackedFloat64Array([0.0, 0.0]), "velocity": Vector2.ZERO, "velocity_components": PackedFloat64Array([0.0, 0.0]), "radius": SUN_RADIUS},
		{"name": "Earth", "mass": EARTH_MASS, "position": earth_position, "position_components": earth_position_components, "velocity": earth_velocity, "velocity_components": earth_velocity_components, "radius": EARTH_RADIUS},
		{"name": "Moon", "mass": MOON_MASS, "position": earth_position + moon_position_value, "position_components": moon_heliocentric_components, "velocity": earth_velocity + moon_velocity_value, "velocity_components": moon_heliocentric_velocity_components, "radius": MOON_RADIUS}
	]
	for planet in PLANETS:
		if str(planet.name) == "Earth":
			continue
		var planet_state: Dictionary = _planet_heliocentric_state(planet, time_seconds)
		heliocentric_bodies.append({"name": str(planet.name), "mass": float(planet.mass), "position": Vector2(planet_state.position), "position_components": planet_state.position_components, "velocity": planet_state.velocity, "velocity_components": planet_state.velocity_components, "radius": float(planet.radius)})
		for satellite_variant in planet.get("satellites", []):
			var satellite: Dictionary = satellite_variant
			var satellite_orbit := _satellite_orbit_state(satellite, time_seconds)
			var satellite_position := planet_state.position + satellite_orbit.position
			var satellite_velocity := planet_state.velocity + satellite_orbit.velocity
			var satellite_position_components := PackedFloat64Array([
				planet_state.position_components[0] + satellite_orbit.position.x,
				planet_state.position_components[1] + satellite_orbit.position.y
			])
			var satellite_velocity_components := PackedFloat64Array([
				planet_state.velocity_components[0] + satellite_orbit.velocity.x,
				planet_state.velocity_components[1] + satellite_orbit.velocity.y
			])
			heliocentric_bodies.append({
				"name": "%s %s" % [str(planet.name), str(satellite.get("name", "Moon"))],
				"mass": float(satellite.get("mass_kg", 0.0)),
				"position": satellite_position,
				"position_components": satellite_position_components,
				"velocity": satellite_velocity,
				"velocity_components": satellite_velocity_components,
				"radius": float(satellite.get("radius_m", 0.0))
			})
	return {
		"bodies": bodies,
		"surface_bodies": surface_bodies,
		"heliocentric_bodies": heliocentric_bodies,
		"earth_heliocentric_position": earth_position,
		"earth_heliocentric_position_components": earth_position_components,
		"earth_heliocentric_velocity": earth_velocity,
		"earth_heliocentric_velocity_components": earth_velocity_components,
		"moon_heliocentric_velocity": earth_velocity + moon_velocity_value,
		"moon_heliocentric_velocity_components": moon_heliocentric_velocity_components
	}

static func gravity_acceleration_from_heliocentric_states(earth_relative_position: Vector2, body_states: Dictionary) -> Vector2:
	return gravity_acceleration_from_states(earth_relative_position, body_states)

static func gravity_acceleration_from_precise_states(position_components: PackedFloat64Array, body_states: Dictionary) -> Vector2:
	if position_components.size() < 2:
		return Vector2.ZERO
	var position_x: float = position_components[0]
	var position_y: float = position_components[1]
	var earth_distance := maxf(sqrt(position_x * position_x + position_y * position_y), EARTH_RADIUS)
	var earth_factor := G * EARTH_MASS / (earth_distance * earth_distance * earth_distance)
	var acceleration_x := -position_x * earth_factor
	var acceleration_y := -position_y * earth_factor
	for body in body_states.get("bodies", []):
		var body_position: Vector2 = body.get("position", Vector2.ZERO)
		var body_components: PackedFloat64Array = body.get("position_components", PackedFloat64Array([body_position.x, body_position.y]))
		var body_x: float = body_components[0]
		var body_y: float = body_components[1]
		var body_mass := float(body.get("mass", 0.0))
		var body_radius := float(body.get("radius", 1.0))
		var relative_x := body_x - position_x
		var relative_y := body_y - position_y
		var relative_distance := maxf(sqrt(relative_x * relative_x + relative_y * relative_y), body_radius)
		var body_distance := maxf(sqrt(body_x * body_x + body_y * body_y), 1.0e7)
		var direct_factor := G * body_mass / (relative_distance * relative_distance * relative_distance)
		var indirect_factor := G * body_mass / (body_distance * body_distance * body_distance)
		acceleration_x += relative_x * direct_factor - body_x * indirect_factor
		acceleration_y += relative_y * direct_factor - body_y * indirect_factor
	return Vector2(acceleration_x, acceleration_y)

static func gravity_acceleration(position: Vector2, time_seconds: float) -> Vector2:
	return gravity_acceleration_from_heliocentric_states(position, gravity_body_states(time_seconds))

static func gravity_acceleration_from_states(position: Vector2, body_states: Dictionary) -> Vector2:
	var distance := maxf(position.length(), EARTH_RADIUS)
	var acceleration := -position.normalized() * G * EARTH_MASS / (distance * distance)
	for body in body_states.get("bodies", []):
		var body_position: Vector2 = body.position
		var body_mass := float(body.mass)
		var body_radius := float(body.radius)
		if body_mass == MOON_MASS:
			var relative := body_position - position
			var relative_distance := maxf(relative.length(), body_radius)
			var body_pull := relative.normalized() * G * body_mass / (relative_distance * relative_distance)
			var earth_pull := body_position.normalized() * G * body_mass / maxf(body_position.length() * body_position.length(), 1.0)
			acceleration += body_pull - earth_pull
		else:
			acceleration += _differential_body_gravity(position, body_mass, body_position, body_radius)
	return acceleration

static func _sun_relative_position(time_seconds: float) -> Vector2:
	return -_earth_heliocentric_state(time_seconds).position

static func _earth_heliocentric_state(time_seconds: float) -> Dictionary:
	var barycentre := _planet_heliocentric_state(_earth_planet_data(), time_seconds)
	var moon_state_value := moon_state(time_seconds)
	var moon_position_components: PackedFloat64Array = moon_state_value.position_components
	var moon_velocity_components: PackedFloat64Array = moon_state_value.velocity_components

	var position_components := PackedFloat64Array([
		barycentre.position_components[0] - moon_position_components[0] * earth_moon_ratio,
		barycentre.position_components[1] - moon_position_components[1] * earth_moon_ratio
	])
	var velocity_components := PackedFloat64Array([
		barycentre.velocity_components[0] - moon_velocity_components[0] * earth_moon_ratio,
		barycentre.velocity_components[1] - moon_velocity_components[1] * earth_moon_ratio
	])
	return {
		"position": Vector2(position_components[0], position_components[1]),
		"position_components": position_components,
		"velocity": Vector2(velocity_components[0], velocity_components[1]),
		"velocity_components": velocity_components
	}

static func planet_position_relative_to_earth(planet_name: String, time_seconds: float) -> Vector2:
	var planet := _planet_data(planet_name)
	if planet.is_empty() or planet_name == "Earth":
		return Vector2.ZERO
	return _planet_relative_position(planet, time_seconds)

static func planet_position_relative_to_earth_components(planet_name: String, time_seconds: float) -> PackedFloat64Array:
	var planet := _planet_data(planet_name)
	if planet.is_empty() or planet_name == "Earth":
		return PackedFloat64Array([0.0, 0.0])
	return _planet_relative_position_components(planet, time_seconds)

static func planet_velocity_relative_to_earth(planet_name: String, time_seconds: float) -> Vector2:
	var planet := _planet_data(planet_name)
	if planet.is_empty() or planet_name == "Earth":
		return Vector2.ZERO
	var earth_state := _earth_heliocentric_state(time_seconds)
	var planet_state := _planet_heliocentric_state(planet, time_seconds)
	return Vector2(
		planet_state.velocity_components[0] - earth_state.velocity_components[0],
		planet_state.velocity_components[1] - earth_state.velocity_components[1]
	)

static func moon_soi_radius() -> float:
	return MOON_SOI_RADIUS

static func planet_soi_radius(planet_name: String) -> float:
	var planet := _planet_data(planet_name)
	if planet.is_empty():
		return 0.0
	return float(planet.a) * ASTRONOMICAL_UNIT * pow(float(planet.mass) / (3.0 * SUN_MASS), 1.0 / 3.0)

static func _planet_relative_position_components(planet: Dictionary, time_seconds: float) -> PackedFloat64Array:
	var earth_state := _earth_heliocentric_state(time_seconds)
	var planet_state := _planet_heliocentric_state(planet, time_seconds)
	return PackedFloat64Array([
		planet_state.position_components[0] - earth_state.position_components[0],
		planet_state.position_components[1] - earth_state.position_components[1]
	])

static func _planet_relative_position(planet: Dictionary, time_seconds: float) -> Vector2:
	var components := _planet_relative_position_components(planet, time_seconds)
	return Vector2(components[0], components[1])

static func _differential_body_gravity(position: Vector2, body_mass: float, body_position: Vector2, body_radius: float = 1.0e7) -> Vector2:
	var relative := body_position - position
	var body_distance := maxf(relative.length(), body_radius)
	var earth_distance := maxf(body_position.length(), 1.0e7)
	return relative.normalized() * G * body_mass / (body_distance * body_distance) - body_position.normalized() * G * body_mass / (earth_distance * earth_distance)

static func atmospheric_temperature(altitude: float) -> float:
	var h := clampf(altitude, 0.0, ATMOSPHERE_HEIGHT)
	var layer := 0
	for i in range(ATMOSPHERE_BASE_ALTITUDES.size() - 1):
		if h >= ATMOSPHERE_BASE_ALTITUDES[i + 1]:
			layer = i + 1
		else:
			break
	var base_altitude: float = ATMOSPHERE_BASE_ALTITUDES[layer]
	var base_temperature: float = ATMOSPHERE_BASE_TEMPERATURES[layer]
	var lapse_rate: float = ATMOSPHERE_LAPSE_RATES[layer]
	return base_temperature + lapse_rate * (h - base_altitude)

static func atmospheric_pressure(altitude: float) -> float:
	var h := clampf(altitude, 0.0, ATMOSPHERE_HEIGHT)
	var layer := 0
	for i in range(ATMOSPHERE_BASE_ALTITUDES.size() - 1):
		if h >= ATMOSPHERE_BASE_ALTITUDES[i + 1]:
			layer = i + 1
		else:
			break
	var base_height: float = ATMOSPHERE_BASE_ALTITUDES[layer]
	var base_temperature: float = ATMOSPHERE_BASE_TEMPERATURES[layer]
	var lapse: float = ATMOSPHERE_LAPSE_RATES[layer]
	var delta_height := h - base_height
	if absf(lapse) < 0.0000001:
		return ATMOSPHERE_BASE_PRESSURES[layer] * exp(-ATMOSPHERE_GRAVITY * delta_height / (ATMOSPHERE_GAS_CONSTANT * base_temperature))
	var temperature := base_temperature + lapse * delta_height
	return ATMOSPHERE_BASE_PRESSURES[layer] * pow(temperature / base_temperature, -ATMOSPHERE_GRAVITY / (lapse * ATMOSPHERE_GAS_CONSTANT))

static func atmospheric_density(altitude: float) -> float:
	if altitude >= ATMOSPHERE_HEIGHT:
		return 0.0
	return atmospheric_pressure(altitude) / (ATMOSPHERE_GAS_CONSTANT * atmospheric_temperature(altitude))

static func earth_atmosphere_gas_constant() -> float:
	return ATMOSPHERE_GAS_CONSTANT

static func earth_atmosphere_gamma() -> float:
	return ATMOSPHERE_GAMMA

static func planetary_atmosphere_height(planet_name: String) -> float:
	if planet_name == "Earth":
		return ATMOSPHERE_HEIGHT
	return float(_atmosphere_data(planet_name).get("height_m", 0.0))

static func planetary_atmosphere_density(planet_name: String, altitude: float) -> float:
	var atmosphere := _atmosphere_data(planet_name)
	var model := str(atmosphere.get("model", "none"))
	if model == "standard":
		return atmospheric_density(altitude)
	var atmosphere_height := float(atmosphere.get("height_m", 0.0))
	var surface_density := float(atmosphere.get("surface_density_kg_m3", 0.0))
	var scale_height := float(atmosphere.get("scale_height_m", 1.0))
	if model != "exponential" or surface_density <= 0.0 or altitude >= atmosphere_height:
		return 0.0
	return surface_density * exp(-maxf(0.0, altitude) / scale_height)

static func planetary_atmosphere_temperature(planet_name: String) -> float:
	return float(_atmosphere_data(planet_name).get("temperature_k", 250.0))

static func planetary_atmosphere_gas_constant(planet_name: String) -> float:
	return float(_atmosphere_data(planet_name).get("gas_constant_j_kg_k", 287.05287))

static func planetary_atmosphere_gamma(planet_name: String) -> float:
	return float(_atmosphere_data(planet_name).get("gamma", 1.4))

static func _atmosphere_data(body_name: String) -> Dictionary:
	var planet := _planet_data(body_name)
	if not planet.is_empty():
		return planet.get("atmosphere", {})
	var satellite := _satellite_data(body_name)
	if not satellite.is_empty():
		return satellite.get("atmosphere", {})
	return {}

static func planetary_rotation_rate(planet_name: String) -> float:
	return float(_planet_data(planet_name).get("rotation_rate_rad_s", 0.0))
