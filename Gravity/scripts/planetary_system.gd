extends RefCounted

const G := 6.67430e-11
const EARTH_MASS := 5.972e24
const EARTH_RADIUS := 6.371e6
const MOON_MASS := 7.342e22
const MOON_RADIUS := 1.7374e6
const MOON_ORBIT_RADIUS := 3.844e8
const MOON_ORBIT_ECCENTRICITY := 0.0549
const MOON_ORBIT_PERIOD := 27.321661 * 86400.0
const MOON_ORBITAL_SPEED := TAU * MOON_ORBIT_RADIUS / MOON_ORBIT_PERIOD
const EARTH_ECCENTRICITY := 0.0167
const EARTH_PERIHELION_LONGITUDE := deg_to_rad(102.9)
const ATMOSPHERE_HEIGHT := 120000.0
const SEA_LEVEL_DENSITY := 1.225
const ATMOSPHERE_SCALE_HEIGHT := 8500.0
const ASTRONOMICAL_UNIT := 1.4960e11
const SUN_MASS := 1.98847e30
const EARTH_ORBIT_PERIOD := 365.256 * 86400.0
const ATMOSPHERE_BASE_ALTITUDES := [0.0, 11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0, 84852.0]
const ATMOSPHERE_BASE_TEMPERATURES := [288.15, 216.65, 216.65, 228.65, 270.65, 270.65, 214.65, 186.946]
const ATMOSPHERE_LAPSE_RATES := [-0.0065, 0.0, 0.001, 0.0028, 0.0, -0.0028, -0.002, 0.0]
const ATMOSPHERE_BASE_PRESSURES := [101325.0, 22632.1, 5474.89, 868.019, 110.906, 66.9389, 3.95642, 0.3734]

const PLANETS := [
	{"name": "Mercury", "mass": 3.3011e23, "radius": 2.4397e6, "semi_major_axis": 5.7909e10, "orbital_period": 87.969, "eccentricity": 0.2056, "perihelion": deg_to_rad(77.5)},
	{"name": "Venus", "mass": 4.8675e24, "radius": 6.0518e6, "semi_major_axis": 1.0821e11, "orbital_period": 224.701, "eccentricity": 0.0068, "perihelion": deg_to_rad(131.6)},
	{"name": "Earth", "mass": EARTH_MASS, "radius": EARTH_RADIUS, "semi_major_axis": ASTRONOMICAL_UNIT, "orbital_period": 365.256, "eccentricity": EARTH_ECCENTRICITY, "perihelion": EARTH_PERIHELION_LONGITUDE},
	{"name": "Mars", "mass": 6.4171e23, "radius": 3.3895e6, "semi_major_axis": 2.2794e11, "orbital_period": 686.980, "eccentricity": 0.0934, "perihelion": deg_to_rad(336.0)},
	{"name": "Jupiter", "mass": 1.8982e27, "radius": 6.9911e7, "semi_major_axis": 7.7857e11, "orbital_period": 4332.59, "eccentricity": 0.0489, "perihelion": deg_to_rad(14.7)},
	{"name": "Saturn", "mass": 5.6834e26, "radius": 5.8232e7, "semi_major_axis": 1.4335e12, "orbital_period": 10759.22, "eccentricity": 0.0565, "perihelion": deg_to_rad(92.4)},
	{"name": "Uranus", "mass": 8.6810e25, "radius": 2.5362e7, "semi_major_axis": 2.8725e12, "orbital_period": 30688.5, "eccentricity": 0.0463, "perihelion": deg_to_rad(170.9)},
	{"name": "Neptune", "mass": 1.0241e26, "radius": 2.4622e7, "semi_major_axis": 4.4951e12, "orbital_period": 60182.0, "eccentricity": 0.0095, "perihelion": deg_to_rad(44.9)}
]

static func get_planet_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for planet in PLANETS:
		result.append(planet.duplicate(true))
	return result

static func moon_position(time_seconds: float) -> Vector2:
	return _kepler_position(MOON_ORBIT_RADIUS, MOON_ORBIT_ECCENTRICITY, 0.0, TAU * time_seconds / MOON_ORBIT_PERIOD, MOON_ORBIT_PERIOD)

static func moon_velocity(time_seconds: float) -> Vector2:
	return _kepler_velocity(MOON_ORBIT_RADIUS, MOON_ORBIT_ECCENTRICITY, 0.0, TAU * time_seconds / MOON_ORBIT_PERIOD, MOON_ORBIT_PERIOD)

static func _kepler_state(semi_major_axis: float, eccentricity: float, perihelion: float, mean_anomaly: float, orbital_period: float) -> Dictionary:
	var mean := fposmod(mean_anomaly, TAU)
	var eccentric_anomaly := mean
	for i in range(12):
		var correction := (eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - mean) / (1.0 - eccentricity * cos(eccentric_anomaly))
		eccentric_anomaly -= correction
		if absf(correction) < 1.0e-12:
			break
	var root := sqrt(1.0 - eccentricity * eccentricity)
	var x := semi_major_axis * (cos(eccentric_anomaly) - eccentricity)
	var y := semi_major_axis * root * sin(eccentric_anomaly)
	var mean_motion := TAU / orbital_period
	var position := Vector2(x, y).rotated(perihelion)
	var velocity := Vector2(-sin(eccentric_anomaly), root * cos(eccentric_anomaly)) * (semi_major_axis * mean_motion / maxf(1.0e-9, 1.0 - eccentricity * cos(eccentric_anomaly)))
	return {"position": position, "velocity": velocity.rotated(perihelion)}

static func _kepler_position(semi_major_axis: float, eccentricity: float, perihelion: float, mean_anomaly: float, orbital_period: float) -> Vector2:
	var state := _kepler_state(semi_major_axis, eccentricity, perihelion, mean_anomaly, orbital_period)
	return state.position

static func _kepler_velocity(semi_major_axis: float, eccentricity: float, perihelion: float, mean_anomaly: float, orbital_period: float) -> Vector2:
	return _kepler_state(semi_major_axis, eccentricity, perihelion, mean_anomaly, orbital_period).velocity

static func gravity_acceleration(position: Vector2, time_seconds: float) -> Vector2:
	var distance := maxf(position.length(), EARTH_RADIUS)
	var acceleration := -position.normalized() * G * EARTH_MASS / (distance * distance)
	var moon := moon_position(time_seconds)
	var relative := moon - position
	var relative_distance := maxf(relative.length(), MOON_RADIUS)
	var moon_pull := relative.normalized() * G * MOON_MASS / (relative_distance * relative_distance)
	var moon_orbit_distance := maxf(moon.length(), 1.0)
	var earth_moon_pull := moon.normalized() * G * MOON_MASS / (moon_orbit_distance * moon_orbit_distance)
	acceleration += moon_pull - earth_moon_pull
	acceleration += _differential_body_gravity(position, SUN_MASS, _sun_relative_position(time_seconds))
	for planet in PLANETS:
		if planet.name == "Earth":
			continue
		var planet_position := _planet_relative_position(planet, time_seconds)
		acceleration += _differential_body_gravity(position, float(planet.mass), planet_position, float(planet.radius))
	return acceleration

static func _sun_relative_position(time_seconds: float) -> Vector2:
	return -_earth_heliocentric_state(time_seconds).position

static func _earth_heliocentric_state(time_seconds: float) -> Dictionary:
	return _planet_heliocentric_state({
		"semi_major_axis": ASTRONOMICAL_UNIT,
		"eccentricity": EARTH_ECCENTRICITY,
		"perihelion": EARTH_PERIHELION_LONGITUDE,
		"orbital_period": 365.256
	}, time_seconds)

static func _planet_heliocentric_state(planet: Dictionary, time_seconds: float) -> Dictionary:
	var period := float(planet.orbital_period) * 86400.0
	var mean_anomaly := TAU * time_seconds / period
	return _kepler_state(float(planet.semi_major_axis), float(planet.eccentricity), float(planet.perihelion), mean_anomaly, period)

static func planet_position_relative_to_earth(planet_name: String, time_seconds: float) -> Vector2:
	var planet := _find_planet(planet_name)
	if planet.is_empty() or planet_name == "Earth":
		return Vector2.ZERO
	return _planet_relative_position(planet, time_seconds)

static func planet_velocity_relative_to_earth(planet_name: String, time_seconds: float) -> Vector2:
	var planet := _find_planet(planet_name)
	if planet.is_empty() or planet_name == "Earth":
		return Vector2.ZERO
	var earth_velocity := _earth_heliocentric_state(time_seconds).velocity
	var planet_velocity := _planet_heliocentric_state(planet, time_seconds).velocity
	return planet_velocity - earth_velocity

static func moon_soi_radius() -> float:
	return MOON_ORBIT_RADIUS * pow(MOON_MASS / (3.0 * EARTH_MASS), 1.0 / 3.0)

static func planet_soi_radius(planet_name: String) -> float:
	var planet := _find_planet(planet_name)
	if planet.is_empty():
		return 0.0
	return float(planet.semi_major_axis) * pow(float(planet.mass) / (3.0 * SUN_MASS), 1.0 / 3.0)

static func _find_planet(planet_name: String) -> Dictionary:
	for planet in PLANETS:
		if str(planet.name) == planet_name:
			return planet
	return {}

static func _planet_relative_position(planet: Dictionary, time_seconds: float) -> Vector2:
	var earth_position := _earth_heliocentric_state(time_seconds).position
	var planet_position := _planet_heliocentric_state(planet, time_seconds).position
	return planet_position - earth_position

static func _differential_body_gravity(position: Vector2, body_mass: float, body_position: Vector2, body_radius: float = 1.0e7) -> Vector2:
	var relative := body_position - position
	var body_distance := maxf(relative.length(), body_radius)
	var earth_distance := maxf(body_position.length(), 1.0e7)
	return relative.normalized() * G * body_mass / (body_distance * body_distance) - body_position.normalized() * G * body_mass / (earth_distance * earth_distance)

static func atmospheric_temperature(altitude: float) -> float:
	var h := clampf(altitude, 0.0, ATMOSPHERE_HEIGHT)
	if h <= 11000.0:
		return 288.15 - 0.0065 * h
	if h <= 20000.0:
		return 216.65
	if h <= 32000.0:
		return 216.65 + 0.001 * (h - 20000.0)
	if h <= 47000.0:
		return 228.65 + 0.0028 * (h - 32000.0)
	if h <= 51000.0:
		return 270.65
	if h <= 71000.0:
		return 270.65 - 0.0028 * (h - 51000.0)
	if h <= 84852.0:
		return 214.65 - 0.002 * (h - 71000.0)
	return 186.946

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
		return ATMOSPHERE_BASE_PRESSURES[layer] * exp(-9.80665 * delta_height / (287.05287 * base_temperature))
	var temperature := base_temperature + lapse * delta_height
	return ATMOSPHERE_BASE_PRESSURES[layer] * pow(temperature / base_temperature, -9.80665 / (lapse * 287.05287))

static func atmospheric_density(altitude: float) -> float:
	if altitude >= ATMOSPHERE_HEIGHT:
		return 0.0
	return atmospheric_pressure(altitude) / (287.05287 * atmospheric_temperature(altitude))

static func planetary_atmosphere_density(planet_name: String, altitude: float) -> float:
	var surface_density := 0.0
	var scale_height := 1.0
	var atmosphere_height := 0.0
	match planet_name:
		"Venus":
			surface_density = 65.0
			scale_height = 15900.0
			atmosphere_height = 250000.0
		"Mars":
			surface_density = 0.020
			scale_height = 11100.0
			atmosphere_height = 125000.0
		"Jupiter":
			surface_density = 0.16
			scale_height = 27000.0
			atmosphere_height = 1000000.0
		"Saturn":
			surface_density = 0.19
			scale_height = 60000.0
			atmosphere_height = 1500000.0
		"Uranus":
			surface_density = 0.42
			scale_height = 50000.0
			atmosphere_height = 1000000.0
		"Neptune":
			surface_density = 0.45
			scale_height = 60000.0
			atmosphere_height = 1500000.0
	if surface_density <= 0.0 or altitude >= atmosphere_height:
		return 0.0
	return surface_density * exp(-maxf(0.0, altitude) / scale_height)

static func planetary_atmosphere_temperature(planet_name: String) -> float:
	match planet_name:
		"Venus":
			return 735.0
		"Mars":
			return 210.0
		"Jupiter":
			return 165.0
		"Saturn":
			return 135.0
		"Uranus":
			return 76.0
		"Neptune":
			return 72.0
	return 250.0

static func planetary_rotation_rate(planet_name: String) -> float:
	match planet_name:
		"Mercury":
			return 1.2400e-6
		"Venus":
			return -2.9924e-7
		"Mars":
			return 7.0882e-5
		"Jupiter":
			return 1.7585e-4
		"Saturn":
			return 1.6379e-4
		"Uranus":
			return -1.0124e-4
		"Neptune":
			return 1.0834e-4
	return 0.0
