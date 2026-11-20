extends RefCounted

const G := 6.67430e-11
const EARTH_MASS := 5.972e24
const EARTH_RADIUS := 6.371e6
const MOON_MASS := 7.342e22
const MOON_RADIUS := 1.7374e6
const MOON_ORBIT_RADIUS := 3.844e8
const MOON_ORBIT_PERIOD := 27.321661 * 86400.0
const MOON_ORBITAL_SPEED := TAU * MOON_ORBIT_RADIUS / MOON_ORBIT_PERIOD
const ATMOSPHERE_HEIGHT := 120000.0
const SEA_LEVEL_DENSITY := 1.225
const ATMOSPHERE_SCALE_HEIGHT := 8500.0

const PLANETS := [
	{"name": "Mercury", "mass": 3.3011e23, "radius": 2.4397e6, "semi_major_axis": 5.7909e10, "orbital_period": 87.969},
	{"name": "Venus", "mass": 4.8675e24, "radius": 6.0518e6, "semi_major_axis": 1.0821e11, "orbital_period": 224.701},
	{"name": "Earth", "mass": EARTH_MASS, "radius": EARTH_RADIUS, "semi_major_axis": 1.4960e11, "orbital_period": 365.256},
	{"name": "Mars", "mass": 6.4171e23, "radius": 3.3895e6, "semi_major_axis": 2.2794e11, "orbital_period": 686.980},
	{"name": "Jupiter", "mass": 1.8982e27, "radius": 6.9911e7, "semi_major_axis": 7.7857e11, "orbital_period": 4332.59},
	{"name": "Saturn", "mass": 5.6834e26, "radius": 5.8232e7, "semi_major_axis": 1.4335e12, "orbital_period": 10759.22},
	{"name": "Uranus", "mass": 8.6810e25, "radius": 2.5362e7, "semi_major_axis": 2.8725e12, "orbital_period": 30688.5},
	{"name": "Neptune", "mass": 1.0241e26, "radius": 2.4622e7, "semi_major_axis": 4.4951e12, "orbital_period": 60182.0}
]

static func get_planet_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for planet in PLANETS:
		result.append(planet.duplicate(true))
	return result

static func moon_position(time_seconds: float) -> Vector2:
	var angle := TAU * time_seconds / MOON_ORBIT_PERIOD
	return Vector2(cos(angle), sin(angle)) * MOON_ORBIT_RADIUS

static func moon_velocity(time_seconds: float) -> Vector2:
	var angle := TAU * time_seconds / MOON_ORBIT_PERIOD
	return Vector2(-sin(angle), cos(angle)) * MOON_ORBITAL_SPEED

static func gravity_acceleration(position: Vector2, time_seconds: float) -> Vector2:
	var distance := maxf(position.length(), EARTH_RADIUS)
	var acceleration := -position.normalized() * G * EARTH_MASS / (distance * distance)
	var moon := moon_position(time_seconds)
	var relative := moon - position
	var relative_distance := maxf(relative.length(), MOON_RADIUS)
	var earth_distance := moon.length()
	var moon_pull := relative.normalized() * G * MOON_MASS / (relative_distance * relative_distance)
	var earth_pull := moon.normalized() * G * MOON_MASS / (earth_distance * earth_distance)
	return acceleration + moon_pull - earth_pull

static func atmospheric_density(altitude: float) -> float:
	if altitude >= ATMOSPHERE_HEIGHT:
		return 0.0
	return SEA_LEVEL_DENSITY * exp(-maxf(0.0, altitude) / ATMOSPHERE_SCALE_HEIGHT)
