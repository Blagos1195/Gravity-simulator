extends RefCounted

const G := 6.67430e-11
const EARTH_MASS := 5.972e24
const EARTH_RADIUS := 6.371e6
const MOON_MASS := 7.342e22
const MOON_RADIUS := 1.7374e6
const MOON_ORBIT_RADIUS := 3.844e8
const MOON_ORBIT_ECCENTRICITY := 0.0549
const MOON_ANOMALOUS_PERIOD := 27.55455 * 86400.0
const MOON_MEAN_ANOMALY_J2000 := 2.355555
const MOON_PERIHELION_J2000 := 3.63734
const MOON_MEAN_MOTION := 2.6392030625e-6
const MOON_PERIHELION_RATE := 1.1807233192e-8
const EPHEMERIS_EPOCH_JD := 2461364.5
const J2000_JD := 2451545.0
const J2000_CENTURY_DAYS := 36525.0
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
	{"name": "Mercury", "mass": 3.3011e23, "radius": 2.4397e6, "a": 0.38709927, "adot": 0.00000037, "e": 0.20563593, "edot": 0.00001906, "i": 7.00497902, "idot": -0.00594749, "L": 252.25032350, "Ldot": 149472.67411175, "peri": 77.45779628, "peridot": 0.16047689, "node": 48.33076593, "nodedot": -0.12534081, "semi_major_axis": 5.7909e10, "orbital_period": 87.969},
	{"name": "Venus", "mass": 4.8675e24, "radius": 6.0518e6, "a": 0.72333566, "adot": 0.00000390, "e": 0.00677672, "edot": -0.00004107, "i": 3.39467605, "idot": -0.00078890, "L": 181.97909950, "Ldot": 58517.81538729, "peri": 131.60246718, "peridot": 0.00268329, "node": 76.67984255, "nodedot": -0.27769418, "semi_major_axis": 1.0821e11, "orbital_period": 224.701},
	{"name": "Earth", "mass": EARTH_MASS, "radius": EARTH_RADIUS, "a": 1.00000261, "adot": 0.00000562, "e": 0.01671123, "edot": -0.00004392, "i": -0.00001531, "idot": -0.01294668, "L": 100.46457166, "Ldot": 35999.37244981, "peri": 102.93768193, "peridot": 0.32327364, "node": 0.0, "nodedot": 0.0, "semi_major_axis": 1.4960e11, "orbital_period": 365.256},
	{"name": "Mars", "mass": 6.4171e23, "radius": 3.3895e6, "a": 1.52371034, "adot": 0.00001847, "e": 0.09339410, "edot": 0.00007882, "i": 1.84969142, "idot": -0.00813131, "L": -4.55343205, "Ldot": 19140.30268499, "peri": -23.94362959, "peridot": 0.44441088, "node": 49.55953891, "nodedot": -0.29257343, "semi_major_axis": 2.2794e11, "orbital_period": 686.980},
	{"name": "Jupiter", "mass": 1.8982e27, "radius": 6.9911e7, "a": 5.20288700, "adot": -0.00011607, "e": 0.04838624, "edot": -0.00013253, "i": 1.30439695, "idot": -0.00183714, "L": 34.39644051, "Ldot": 3034.74612775, "peri": 14.72847983, "peridot": 0.21252668, "node": 100.47390909, "nodedot": 0.20469106, "semi_major_axis": 7.7857e11, "orbital_period": 4332.59},
	{"name": "Saturn", "mass": 5.6834e26, "radius": 5.8232e7, "a": 9.53667594, "adot": -0.00125060, "e": 0.05386179, "edot": -0.00050991, "i": 2.48599187, "idot": 0.00193609, "L": 49.95424423, "Ldot": 1222.49362201, "peri": 92.59887831, "peridot": -0.41897216, "node": 113.66242448, "nodedot": -0.28867794, "semi_major_axis": 1.4335e12, "orbital_period": 10759.22},
	{"name": "Uranus", "mass": 8.6810e25, "radius": 2.5362e7, "a": 19.18916464, "adot": -0.00196176, "e": 0.04725744, "edot": -0.00004397, "i": 0.77263783, "idot": -0.00242939, "L": 313.23810451, "Ldot": 428.48202785, "peri": 170.95427630, "peridot": 0.40805281, "node": 74.01692503, "nodedot": 0.04240589, "semi_major_axis": 2.8725e12, "orbital_period": 30688.5},
	{"name": "Neptune", "mass": 1.0241e26, "radius": 2.4622e7, "a": 30.06992276, "adot": 0.00026291, "e": 0.00859048, "edot": 0.00005105, "i": 1.77004347, "idot": 0.00035372, "L": -55.12002969, "Ldot": 218.45945325, "peri": 44.96476227, "peridot": -0.32241464, "node": 131.78422574, "nodedot": -0.00508664, "semi_major_axis": 4.4951e12, "orbital_period": 60182.0}
]

static func get_planet_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for planet in PLANETS:
		result.append(planet.duplicate(true))
	return result

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

static func _planet_position_at_century(planet: Dictionary, centuries: float) -> Vector2:
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
	return Vector2(x, y)

static func _planet_heliocentric_state(planet: Dictionary, time_seconds: float) -> Dictionary:
	var centuries := _ephemeris_centuries(time_seconds)
	var position := _planet_position_at_century(planet, centuries)
	var delta := 60.0 / (86400.0 * J2000_CENTURY_DAYS)
	var before := _planet_position_at_century(planet, centuries - delta)
	var after := _planet_position_at_century(planet, centuries + delta)
	return {"position": position, "velocity": (after - before) / 120.0}

static func moon_position(time_seconds: float) -> Vector2:
	var days_since_j2000 := EPHEMERIS_EPOCH_JD - J2000_JD + time_seconds / 86400.0
	var mean_anomaly := MOON_MEAN_ANOMALY_J2000 + MOON_MEAN_MOTION * days_since_j2000 * 86400.0
	var perihelion := MOON_PERIHELION_J2000 + MOON_PERIHELION_RATE * days_since_j2000 * 86400.0
	var eccentric_anomaly := _solve_kepler(mean_anomaly, MOON_ORBIT_ECCENTRICITY)
	var x := MOON_ORBIT_RADIUS * (cos(eccentric_anomaly) - MOON_ORBIT_ECCENTRICITY)
	var y := MOON_ORBIT_RADIUS * sqrt(1.0 - MOON_ORBIT_ECCENTRICITY * MOON_ORBIT_ECCENTRICITY) * sin(eccentric_anomaly)
	return Vector2(x, y).rotated(perihelion)

static func moon_velocity(time_seconds: float) -> Vector2:
	return (moon_position(time_seconds + 30.0) - moon_position(time_seconds - 30.0)) / 60.0

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
	var barycentre := _planet_heliocentric_state(PLANETS[2], time_seconds)
	var earth_moon_ratio := MOON_MASS / (EARTH_MASS + MOON_MASS)
	return {
		"position": barycentre.position - moon_position(time_seconds) * earth_moon_ratio,
		"velocity": barycentre.velocity - moon_velocity(time_seconds) * earth_moon_ratio
	}

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
	return float(planet.a) * ASTRONOMICAL_UNIT * pow(float(planet.mass) / (3.0 * SUN_MASS), 1.0 / 3.0)

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
