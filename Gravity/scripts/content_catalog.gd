extends RefCounted
class_name ContentCatalog

const BUILTIN_PATH := "res://data/content_catalog.json"
const MOD_PATH := "user://mods/content_catalog.json"

static var _catalog: Dictionary = {}
static var _loaded := false
static var source_path := ""

static func get_catalog() -> Dictionary:
	if _loaded:
		return _catalog
	_loaded = true
	if FileAccess.file_exists(MOD_PATH):
		var mod_catalog := _read_catalog(MOD_PATH)
		var mod_error := _catalog_error(mod_catalog)
		if mod_error.is_empty():
			_catalog = mod_catalog
			source_path = MOD_PATH
			return _catalog
		push_error("Ignoring invalid mod catalog at %s: %s" % [MOD_PATH, mod_error])
	var builtin_catalog := _read_catalog(BUILTIN_PATH)
	var builtin_error := _catalog_error(builtin_catalog)
	if not builtin_error.is_empty():
		push_error("Built-in content catalog is invalid: %s" % builtin_error)
		return _catalog
	_catalog = builtin_catalog
	source_path = BUILTIN_PATH
	return _catalog

static func _read_catalog(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open content catalog at %s." % path)
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error("Could not parse content catalog at %s, line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		push_error("Content catalog at %s must have a JSON object at its root." % path)
		return {}
	return parser.data

static func _catalog_error(catalog: Dictionary) -> String:
	if int(catalog.get("schema_version", 0)) != 1:
		return "Unsupported or missing schema_version; expected 1."
	var system: Variant = catalog.get("system")
	if not system is Dictionary:
		return "The system section is missing or invalid."
	var system_error := _numeric_fields_error(system, [
		"gravitational_constant", "astronomical_unit_m", "sun_mass_kg", "sun_radius_m",
		"ephemeris_epoch_jd", "j2000_jd", "j2000_century_days"
	], "system")
	if not system_error.is_empty():
		return system_error
	for key in ["gravitational_constant", "astronomical_unit_m", "sun_mass_kg", "sun_radius_m", "j2000_century_days"]:
		if float(system[key]) <= 0.0:
			return "System %s must be greater than zero." % key
	var sun_color_error := _color_field_error(system, "sun_color_rgb", "system")
	if not sun_color_error.is_empty():
		return sun_color_error
	var earth_atmosphere: Variant = system.get("earth_atmosphere")
	if not earth_atmosphere is Dictionary:
		return "The system earth_atmosphere section is missing or invalid."
	var atmosphere_error := _numeric_fields_error(earth_atmosphere, [
		"height_m", "sea_level_density_kg_m3", "scale_height_m", "gravity_m_s2",
		"gas_constant_j_kg_k", "gamma"
	], "system.earth_atmosphere")
	if not atmosphere_error.is_empty():
		return atmosphere_error
	for key in ["height_m", "sea_level_density_kg_m3", "scale_height_m", "gravity_m_s2", "gas_constant_j_kg_k", "gamma"]:
		if float(earth_atmosphere[key]) <= 0.0:
			return "Earth atmosphere %s must be greater than zero." % key
	var atmosphere_arrays := [
		earth_atmosphere.get("base_altitudes_m"),
		earth_atmosphere.get("base_temperatures_k"),
		earth_atmosphere.get("lapse_rates_k_m"),
		earth_atmosphere.get("base_pressures_pa")
	]
	for values in atmosphere_arrays:
		if not values is Array or values.is_empty():
			return "Earth atmosphere profile values must be non-empty arrays."
		if values.size() != atmosphere_arrays[0].size():
			return "Earth atmosphere profile arrays must have matching lengths."
		for value in values:
			if not (value is int or value is float):
				return "Earth atmosphere profile arrays may contain only numbers."
	for i in range(atmosphere_arrays[0].size()):
		if float(atmosphere_arrays[1][i]) <= 0.0 or float(atmosphere_arrays[3][i]) <= 0.0:
			return "Earth atmosphere profile temperatures and pressures must be positive."
		if i > 0 and float(atmosphere_arrays[0][i]) <= float(atmosphere_arrays[0][i - 1]):
			return "Earth atmosphere base altitudes must be strictly increasing."
	var belts: Variant = system.get("small_body_belts", [])
	if not belts is Array:
		return "System small_body_belts must be an array."
	for belt_variant in belts:
		if not belt_variant is Dictionary:
			return "Every small-body belt must be an object."
		var belt: Dictionary = belt_variant
		var belt_error := _numeric_fields_error(belt, [
			"inner_radius_au", "outer_radius_au", "particle_count", "seed", "particle_size_px", "opacity"
		], "small-body belt %s" % str(belt.get("name", "unnamed")))
		if not belt_error.is_empty():
			return belt_error
		if belt.has("collision_radius_min_m") != belt.has("collision_radius_max_m"):
			return "Small-body belt %s must define both collision-radius bounds." % str(belt.get("name", "unnamed"))
		if belt.has("collision_radius_min_m"):
			var collision_radius_error := _numeric_fields_error(belt, ["collision_radius_min_m", "collision_radius_max_m"], "small-body belt collision radii")
			if not collision_radius_error.is_empty():
				return collision_radius_error
			if float(belt.collision_radius_min_m) <= 0.0 or float(belt.collision_radius_max_m) < float(belt.collision_radius_min_m):
				return "Small-body belt %s has invalid collision-radius bounds." % str(belt.get("name", "unnamed"))
		var belt_color_error := _color_field_error(belt, "color_rgb", "small-body belt")
		if not belt_color_error.is_empty():
			return belt_color_error
		if str(belt.get("name", "")).is_empty() or float(belt.inner_radius_au) <= 0.0 or float(belt.outer_radius_au) <= float(belt.inner_radius_au) or int(belt.particle_count) < 1 or int(belt.particle_count) > 5000 or float(belt.particle_size_px) <= 0.0 or float(belt.opacity) < 0.0 or float(belt.opacity) > 1.0:
			return "Small-body belt %s has invalid bounds or display settings." % str(belt.get("name", "unnamed"))
	var planets: Variant = catalog.get("planets")
	if not planets is Array or planets.is_empty():
		return "The planets section must be a non-empty array."
	var planet_names := {}
	for planet_variant in planets:
		if not planet_variant is Dictionary:
			return "Every planet entry must be an object."
		var planet: Dictionary = planet_variant
		var planet_name := str(planet.get("name", ""))
		if planet_name.is_empty() or planet_names.has(planet_name):
			return "Planet names must be non-empty and unique."
		if not planet.get("solid") is bool:
			return "Planet %s must define a solid boolean." % planet_name
		planet_names[planet_name] = true
		var planet_color_error := _color_field_error(planet, "color_rgb", "planet %s" % planet_name)
		if not planet_color_error.is_empty():
			return planet_color_error
		if planet.has("surface_color_rgb"):
			var surface_color_error := _color_field_error(planet, "surface_color_rgb", "planet %s" % planet_name)
			if not surface_color_error.is_empty():
				return surface_color_error
		var planet_error := _numeric_fields_error(planet, [
			"mass", "radius", "a", "adot", "e", "edot", "i", "idot", "L", "Ldot",
			"peri", "peridot", "node", "nodedot", "orbital_period",
			"rotation_rate_rad_s"
		], "planet %s" % planet_name)
		if not planet_error.is_empty():
			return planet_error
		if float(planet.mass) <= 0.0 or float(planet.radius) <= 0.0 or float(planet.a) <= 0.0 or float(planet.orbital_period) <= 0.0 or float(planet.e) < 0.0 or float(planet.e) >= 1.0:
			return "Planet %s has invalid mass, radius or orbital elements." % planet_name
		var planet_atmosphere: Variant = planet.get("atmosphere")
		if not planet_atmosphere is Dictionary:
			return "Planet %s needs an atmosphere object." % planet_name
		var planet_atmosphere_error := _numeric_fields_error(planet_atmosphere, [
			"height_m", "visual_height_m", "surface_density_kg_m3", "scale_height_m", "temperature_k",
			"gas_constant_j_kg_k", "gamma"
		], "planet %s atmosphere" % planet_name)
		if not planet_atmosphere_error.is_empty():
			return planet_atmosphere_error
		var atmosphere_color_error := _color_field_error(planet_atmosphere, "color_rgb", "planet %s atmosphere" % planet_name)
		if not atmosphere_color_error.is_empty():
			return atmosphere_color_error
		if float(planet_atmosphere.scale_height_m) <= 0.0 or float(planet_atmosphere.temperature_k) <= 0.0 or float(planet_atmosphere.gas_constant_j_kg_k) <= 0.0 or float(planet_atmosphere.gamma) <= 0.0 or float(planet_atmosphere.height_m) < 0.0 or float(planet_atmosphere.visual_height_m) < 0.0 or float(planet_atmosphere.surface_density_kg_m3) < 0.0:
			return "Planet %s has invalid atmosphere values." % planet_name
		var atmosphere_model := str(planet_atmosphere.get("model", ""))
		if atmosphere_model != "none" and atmosphere_model != "standard" and atmosphere_model != "exponential":
			return "Planet %s has an unsupported atmosphere model." % planet_name
		if planet.has("rings"):
			var rings: Variant = planet.get("rings")
			if not rings is Dictionary or not rings.get("enabled") is bool:
				return "Planet %s has invalid ring data." % planet_name
			if bool(rings.enabled):
				var ring_fields: Array = []
				for key in ["inner_radius_ratio", "outer_radius_ratio", "opacity"]:
					if rings.has(key):
						ring_fields.append(key)
				var ring_error := _numeric_fields_error(rings, ring_fields, "planet %s rings" % planet_name)
				if not ring_error.is_empty():
					return ring_error
				var ring_color_error := _color_field_error(rings, "color_rgb", "planet %s rings" % planet_name)
				if not ring_color_error.is_empty():
					return ring_color_error
				var inner_ratio := float(rings.get("inner_radius_ratio", 1.2))
				var outer_ratio := float(rings.get("outer_radius_ratio", 2.0))
				var ring_opacity := float(rings.get("opacity", 0.5))
				if inner_ratio <= 1.0 or outer_ratio <= inner_ratio or ring_opacity < 0.0 or ring_opacity > 1.0:
					return "Planet %s has invalid ring dimensions or opacity." % planet_name
		var satellites: Variant = planet.get("satellites", [])
		if not satellites is Array:
			return "Planet %s satellites must be an array." % planet_name
		var satellite_names := {}
		for satellite_variant in satellites:
			if not satellite_variant is Dictionary:
				return "Planet %s satellite entries must be objects." % planet_name
			var satellite: Dictionary = satellite_variant
			var satellite_name := str(satellite.get("name", ""))
			if satellite_name.is_empty() or satellite_names.has(satellite_name):
				return "Planet %s satellite names must be non-empty and unique." % planet_name
			satellite_names[satellite_name] = true
			var satellite_error := _numeric_fields_error(satellite, [
				"mass_kg", "radius_m", "semi_major_axis_m", "orbital_period_s", "phase_rad", "rotation_rate_rad_s"
			], "%s satellite %s" % [planet_name, satellite_name])
			if not satellite_error.is_empty():
				return satellite_error
			var satellite_color_error := _color_field_error(satellite, "color_rgb", "%s satellite %s" % [planet_name, satellite_name])
			if not satellite_color_error.is_empty():
				return satellite_color_error
			if not satellite.get("solid") is bool or float(satellite.mass_kg) <= 0.0 or float(satellite.radius_m) <= 0.0 or float(satellite.semi_major_axis_m) <= float(planet.radius) or float(satellite.orbital_period_s) <= 0.0:
				return "%s satellite %s has invalid physical or orbital values." % [planet_name, satellite_name]
			if satellite.has("orbital_direction") and (not (satellite.orbital_direction is int or satellite.orbital_direction is float) or absf(float(satellite.orbital_direction)) != 1.0):
				return "%s satellite %s orbital_direction must be -1 or 1." % [planet_name, satellite_name]
			if satellite.has("atmosphere"):
				var satellite_atmosphere: Variant = satellite.get("atmosphere")
				if not satellite_atmosphere is Dictionary:
					return "%s satellite %s atmosphere must be an object." % [planet_name, satellite_name]
				var satellite_atmosphere_error := _numeric_fields_error(satellite_atmosphere, [
					"height_m", "visual_height_m", "surface_density_kg_m3", "scale_height_m",
					"temperature_k", "gas_constant_j_kg_k", "gamma"
				], "%s satellite %s atmosphere" % [planet_name, satellite_name])
				if not satellite_atmosphere_error.is_empty():
					return satellite_atmosphere_error
				var satellite_atmosphere_color_error := _color_field_error(satellite_atmosphere, "color_rgb", "%s satellite %s atmosphere" % [planet_name, satellite_name])
				if not satellite_atmosphere_color_error.is_empty():
					return satellite_atmosphere_color_error
				var satellite_atmosphere_model := str(satellite_atmosphere.get("model", ""))
				if satellite_atmosphere_model != "none" and satellite_atmosphere_model != "exponential":
					return "%s satellite %s has an unsupported atmosphere model." % [planet_name, satellite_name]
				if float(satellite_atmosphere.height_m) < 0.0 or float(satellite_atmosphere.visual_height_m) < 0.0 or float(satellite_atmosphere.surface_density_kg_m3) < 0.0 or float(satellite_atmosphere.scale_height_m) <= 0.0 or float(satellite_atmosphere.temperature_k) <= 0.0 or float(satellite_atmosphere.gas_constant_j_kg_k) <= 0.0 or float(satellite_atmosphere.gamma) <= 0.0:
					return "%s satellite %s has invalid atmosphere values." % [planet_name, satellite_name]
	if not planet_names.has("Earth"):
		return "The planets section must include Earth."
	var moon: Variant = catalog.get("moon")
	if not moon is Dictionary:
		return "The moon section is missing or invalid."
	var moon_error := _numeric_fields_error(moon, [
		"mass_kg", "radius_m", "semi_major_axis_m", "transfer_orbit_radius_m", "eccentricity",
		"rotation_period_s", "mean_anomaly_j2000_rad", "perihelion_j2000_rad", "mean_motion_rad_s",
		"perihelion_rate_rad_s", "soi_radius_m", "rotation_rate_rad_s"
	], "moon")
	if not moon_error.is_empty():
		return moon_error
	var moon_color_error := _color_field_error(moon, "color_rgb", "moon")
	if not moon_color_error.is_empty():
		return moon_color_error
	if not moon.get("solid") is bool or float(moon.mass_kg) <= 0.0 or float(moon.radius_m) <= 0.0 or float(moon.semi_major_axis_m) <= 0.0 or float(moon.transfer_orbit_radius_m) <= 0.0 or float(moon.rotation_period_s) <= 0.0 or float(moon.mean_motion_rad_s) <= 0.0 or float(moon.soi_radius_m) <= 0.0 or float(moon.eccentricity) < 0.0 or float(moon.eccentricity) >= 1.0:
		return "The moon section has invalid physical or orbital values."
	var rocket: Variant = catalog.get("rocket")
	if not rocket is Dictionary:
		return "The rocket section is missing or invalid."
	if not rocket.has("default_design") or not rocket.has("presets") or not rocket.has("stage_parts"):
		return "The rocket section needs default_design, presets and stage_parts."
	var presets: Variant = rocket.get("presets")
	var stage_parts: Variant = rocket.get("stage_parts")
	if not presets is Dictionary or not stage_parts is Array or stage_parts.is_empty():
		return "The rocket presets or stage_parts have an invalid type."
	var part_ids := {}
	for part_variant in stage_parts:
		if not part_variant is Dictionary:
			return "Every rocket stage part must be an object."
		var part: Dictionary = part_variant
		var part_id := str(part.get("id", ""))
		if part_id.is_empty() or part_ids.has(part_id):
			return "Rocket stage-part ids must be non-empty and unique."
		part_ids[part_id] = true
		var part_error := _numeric_fields_error(part, ["dry_mass", "fuel_capacity", "thrust", "vacuum_thrust", "flow", "engine_count"], "rocket stage part %s" % part_id)
		if not part_error.is_empty():
			return part_error
		if not part.has("name") or float(part.dry_mass) <= 0.0 or float(part.fuel_capacity) <= 0.0 or float(part.thrust) <= 0.0 or float(part.vacuum_thrust) <= 0.0 or float(part.flow) <= 0.0 or int(part.engine_count) <= 0:
			return "Rocket stage part %s has invalid name or engine values." % part_id
	var designs: Array = [rocket.get("default_design")]
	for preset_id in presets:
		designs.append(presets[preset_id])
	for design_variant in designs:
		if not design_variant is Dictionary:
			return "Every rocket design must be an object."
		var design: Dictionary = design_variant
		if not design.get("stages") is Array:
			return "Rocket design %s must have a stages array." % str(design.get("name", "unnamed"))
		if design.stages.size() < 2 or design.stages.size() > 8:
			return "Rocket design %s must have between 2 and 8 stages." % str(design.get("name", "unnamed"))
		var design_error := _numeric_fields_error(design, ["payload_mass"], "rocket design %s" % str(design.get("name", "unnamed")))
		if not design_error.is_empty():
			return design_error
		if float(design.payload_mass) <= 0.0:
			return "Rocket design %s must have positive payload mass." % str(design.get("name", "unnamed"))
		for part_id_variant in design.get("stages", []):
			if not part_ids.has(str(part_id_variant)):
				return "Rocket design %s references unknown stage part %s." % [str(design.get("name", "unnamed")), str(part_id_variant)]
	return ""

static func _numeric_fields_error(data: Dictionary, fields: Array, context: String) -> String:
	for key in fields:
		var value: Variant = data.get(key)
		if not (value is int or value is float):
			return "%s is missing numeric field %s." % [context, key]
	return ""

static func _color_field_error(data: Dictionary, key: String, context: String) -> String:
	var value: Variant = data.get(key)
	if not value is Array or value.size() != 3:
		return "%s needs a three-number %s RGB array." % [context, key]
	for component in value:
		if not (component is int or component is float) or float(component) < 0.0 or float(component) > 1.0:
			return "%s %s components must be between zero and one." % [context, key]
	return ""
