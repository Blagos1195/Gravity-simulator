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
	var builtin_catalog := _read_catalog(BUILTIN_PATH)
	var builtin_error := _catalog_error(builtin_catalog)
	if not builtin_error.is_empty():
		push_error("Built-in content catalog is invalid: %s" % builtin_error)
		return _catalog
	_catalog = builtin_catalog
	source_path = BUILTIN_PATH
	if not FileAccess.file_exists(MOD_PATH):
		return _catalog
	var mod_catalog := _read_catalog(MOD_PATH)
	if mod_catalog.is_empty() or int(mod_catalog.get("schema_version", 0)) != 1:
		push_error("Ignoring invalid mod catalog at %s: schema_version must be 1." % MOD_PATH)
		return _catalog
	var merged_catalog := _merge_overlay(builtin_catalog, mod_catalog)
	var mod_error := _catalog_error(merged_catalog)
	if not mod_error.is_empty():
		push_error("Ignoring invalid mod catalog at %s: %s" % [MOD_PATH, mod_error])
		return _catalog
	_catalog = merged_catalog
	source_path = "%s + %s" % [BUILTIN_PATH, MOD_PATH]
	return _catalog

static func _merge_overlay(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for raw_key in overlay:
		var key := str(raw_key)
		if key.ends_with("_add"):
			var target_key := key.trim_suffix("_add")
			var existing: Variant = merged.get(target_key)
			var additions: Variant = overlay[raw_key]
			if existing is Array and additions is Array:
				merged[target_key] = _merge_array_items(existing, additions)
			elif existing is Dictionary and additions is Dictionary:
				merged[target_key] = _merge_overlay(existing, additions)
			elif existing == null and additions is Array:
				merged[target_key] = _merge_array_items([], additions)
			elif existing == null and additions is Dictionary:
				merged[target_key] = _merge_overlay({}, additions)
			else:
				push_error("Ignoring unsupported mod extension field: %s" % key)
		elif merged.get(key) is Dictionary and overlay[raw_key] is Dictionary:
			merged[key] = _merge_overlay(merged[key], overlay[raw_key])
		else:
			var value: Variant = overlay[raw_key]
			merged[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	return merged

static func _merge_array_items(base: Array, additions: Array) -> Array:
	var merged := base.duplicate(true)
	for addition in additions:
		var identity_key := ""
		if addition is Dictionary:
			identity_key = "id" if addition.has("id") else "name" if addition.has("name") else ""
		var match_index := -1
		if not identity_key.is_empty():
			for index in range(merged.size()):
				var existing: Variant = merged[index]
				if existing is Dictionary and str(existing.get(identity_key, "")) == str(addition.get(identity_key, "")):
					match_index = index
					break
		if match_index >= 0:
				merged[match_index] = _merge_overlay(merged[match_index], addition)
		else:
			merged.append(_merge_overlay({}, addition) if addition is Dictionary else addition.duplicate(true) if addition is Array else addition)
	return merged

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
	if not presets is Dictionary or presets.is_empty() or not stage_parts is Array or stage_parts.is_empty():
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
		if not part.has("name") or float(part.dry_mass) <= 0.0 or float(part.fuel_capacity) <= 0.0 or float(part.thrust) <= 0.0 or float(part.vacuum_thrust) <= 0.0 or float(part.flow) <= 0.0 or int(part.engine_count) <= 0 or float(part.engine_count) != float(int(part.engine_count)):
			return "Rocket stage part %s has invalid name or engine values." % part_id
		if part.has("engine_layout") and (not part.engine_layout is String or not ["linear", "cluster", "radial"].has(part.engine_layout)):
			return "Rocket stage part %s has an unsupported engine_layout." % part_id
		for visual_key in ["visual_length_factor", "visual_diameter_factor"]:
			if part.has(visual_key) and (not (part[visual_key] is int or part[visual_key] is float) or float(part[visual_key]) <= 0.0):
				return "Rocket stage part %s has an invalid %s." % [part_id, visual_key]
		if part.has("visual_color_rgb"):
			var visual_color_error := _color_field_error(part, "visual_color_rgb", "rocket stage part %s" % part_id)
			if not visual_color_error.is_empty():
				return visual_color_error
	var builder_options: Variant = rocket.get("builder_options")
	if not builder_options is Dictionary:
		return "The rocket builder_options section is missing or invalid."
	var payload_options: Variant = builder_options.get("payloads")
	var engine_counts: Variant = builder_options.get("engine_counts")
	var tank_scales: Variant = builder_options.get("tank_scales")
	var booster_options: Variant = builder_options.get("booster_options")
	var payload_components: Variant = builder_options.get("payload_components")
	if not payload_options is Array or payload_options.is_empty() or not engine_counts is Array or engine_counts.is_empty() or not tank_scales is Array or tank_scales.is_empty() or not booster_options is Array or booster_options.is_empty() or not payload_components is Array or payload_components.is_empty():
		return "Rocket builder payloads, payload_components, engine_counts, tank_scales and booster_options must be non-empty arrays."
	var payload_mass_limits: Variant = builder_options.get("payload_mass_limits")
	if payload_mass_limits != null:
		if not payload_mass_limits is Dictionary:
			return "Rocket payload_mass_limits must be an object."
		var payload_limits_error := _numeric_fields_error(payload_mass_limits, ["minimum", "maximum", "step"], "rocket payload_mass_limits")
		if not payload_limits_error.is_empty():
			return payload_limits_error
		if float(payload_mass_limits.minimum) <= 0.0 or float(payload_mass_limits.maximum) <= float(payload_mass_limits.minimum) or float(payload_mass_limits.step) <= 0.0:
			return "Rocket payload mass limits must have a positive minimum, maximum and step."
	var payload_ids := {}
	for payload_variant in payload_options:
		if not payload_variant is Dictionary:
			return "Every rocket payload option must be an object."
		var payload: Dictionary = payload_variant
		var payload_id := str(payload.get("id", ""))
		if payload_id.is_empty() or payload_ids.has(payload_id) or str(payload.get("label", "")).is_empty():
			return "Rocket payload option ids and labels must be non-empty and unique."
		var payload_error := _numeric_fields_error(payload, ["mass"], "rocket payload %s" % payload_id)
		if not payload_error.is_empty():
			return payload_error
		if payload_mass_limits is Dictionary and (float(payload.mass) < float(payload_mass_limits.minimum) or float(payload.mass) > float(payload_mass_limits.maximum)):
			return "Rocket payload %s mass is outside the configured payload limits." % payload_id
		if payload.has("visual_type") and (not payload.visual_type is String or not ["probe", "crew", "satellite", "cargo"].has(payload.visual_type)):
			return "Rocket payload %s has an unsupported visual_type." % payload_id
		for visual_key in ["visual_width_factor", "visual_height_factor"]:
			if payload.has(visual_key) and (not (payload[visual_key] is int or payload[visual_key] is float) or not is_finite(float(payload[visual_key])) or float(payload[visual_key]) <= 0.0):
				return "Rocket payload %s has an invalid %s." % [payload_id, visual_key]
		if payload.has("telescope_range_au") and (not (payload.telescope_range_au is int or payload.telescope_range_au is float) or not is_finite(float(payload.telescope_range_au)) or float(payload.telescope_range_au) < 0.0):
			return "Rocket payload %s has an invalid telescope_range_au." % payload_id
		for economy_key in ["revenue_per_day", "operating_cost_per_day", "operational_lifetime_days"]:
			if payload.has(economy_key):
				var economy_value: Variant = payload[economy_key]
				var minimum_value := 0.0 if economy_key != "operational_lifetime_days" else 0.000001
				if not (economy_value is int or economy_value is float) or not is_finite(float(economy_value)) or float(economy_value) < minimum_value:
					return "Rocket payload %s has an invalid %s." % [payload_id, economy_key]
		if payload.has("satellite_role") and not str(payload.satellite_role).is_empty() and str(payload.get("visual_type", "satellite")) != "satellite":
			return "Rocket payload %s assigns a satellite role to a non-satellite visual." % payload_id
		if payload.has("visual_color_rgb"):
			var payload_visual_color_error := _color_field_error(payload, "visual_color_rgb", "rocket payload %s" % payload_id)
			if not payload_visual_color_error.is_empty():
				return payload_visual_color_error
		payload_ids[payload_id] = true
	var payload_component_ids := {}
	var component_types := ["fairing", "solar_panels", "antenna", "docking_port", "instrument"]
	for component_variant in payload_components:
		if not component_variant is Dictionary:
			return "Every payload component option must be an object."
		var component: Dictionary = component_variant
		var component_id := str(component.get("id", ""))
		var component_type := str(component.get("component_type", ""))
		if component_id.is_empty() or payload_component_ids.has(component_id) or str(component.get("label", "")).is_empty() or not component_types.has(component_type):
			return "Payload component ids, labels and component types must be valid and unique."
		var component_error := _numeric_fields_error(component, ["dry_mass"], "payload component %s" % component_id)
		if not component_error.is_empty() or float(component.dry_mass) <= 0.0:
			return "Payload component %s has an invalid dry_mass." % component_id
		for visual_key in ["visual_width_factor", "visual_height_factor"]:
			if component.has(visual_key) and (not (component[visual_key] is int or component[visual_key] is float) or not is_finite(float(component[visual_key])) or float(component[visual_key]) <= 0.0):
				return "Payload component %s has an invalid %s." % [component_id, visual_key]
		if component.has("visual_color_rgb"):
			var component_color_error := _color_field_error(component, "visual_color_rgb", "payload component %s" % component_id)
			if not component_color_error.is_empty():
				return component_color_error
		for numeric_key in ["drag_reduction", "power_output_kw", "science_value"]:
			if component.has(numeric_key) and (not (component[numeric_key] is int or component[numeric_key] is float) or not is_finite(float(component[numeric_key])) or float(component[numeric_key]) < 0.0):
				return "Payload component %s has an invalid %s." % [component_id, numeric_key]
		if component_type == "fairing" and (not component.has("drag_reduction") or float(component.drag_reduction) > 1.0):
			return "Payload fairings need a drag_reduction between zero and one."
		payload_component_ids[component_id] = true
	var booster_ids := {}
	for booster_variant in booster_options:
		if not booster_variant is Dictionary:
			return "Every rocket booster option must be an object."
		var booster: Dictionary = booster_variant
		var booster_id := str(booster.get("id", ""))
		if booster_id.is_empty() or booster_ids.has(booster_id) or str(booster.get("label", "")).is_empty():
			return "Rocket booster option ids and labels must be non-empty and unique."
		var booster_error := _numeric_fields_error(booster, ["dry_mass", "fuel_capacity", "thrust", "vacuum_thrust", "flow", "pair_count"], "rocket booster %s" % booster_id)
		if not booster_error.is_empty():
			return booster_error
		if float(booster.dry_mass) <= 0.0 or float(booster.fuel_capacity) <= 0.0 or float(booster.thrust) <= 0.0 or float(booster.vacuum_thrust) < float(booster.thrust) or float(booster.flow) <= 0.0 or int(booster.pair_count) != 2 or float(booster.pair_count) != float(int(booster.pair_count)):
			return "Rocket booster %s has invalid physical values." % booster_id
		for visual_key in ["visual_width_factor", "visual_length_factor"]:
			if booster.has(visual_key) and (not (booster[visual_key] is int or booster[visual_key] is float) or float(booster[visual_key]) <= 0.0):
				return "Rocket booster %s has an invalid %s." % [booster_id, visual_key]
		if booster.has("visual_color_rgb"):
			var booster_color_error := _color_field_error(booster, "visual_color_rgb", "rocket booster %s" % booster_id)
			if not booster_color_error.is_empty():
				return booster_color_error
		booster_ids[booster_id] = true
	var engine_count_ids := {}
	for engine_count in engine_counts:
		if not (engine_count is int or engine_count is float) or int(engine_count) < 1 or float(engine_count) != float(int(engine_count)) or engine_count_ids.has(int(engine_count)):
			return "Rocket builder engine_counts must contain unique positive whole numbers."
		engine_count_ids[int(engine_count)] = true
	var tank_scale_values := []
	for tank_option_variant in tank_scales:
		if not tank_option_variant is Dictionary:
			return "Every rocket tank scale option must be an object."
		var tank_option: Dictionary = tank_option_variant
		var tank_error := _numeric_fields_error(tank_option, ["scale"], "rocket tank scale")
		if not tank_error.is_empty():
			return tank_error
		var tank_scale := float(tank_option.scale)
		if str(tank_option.get("label", "")).is_empty() or tank_scale <= 0.0 or tank_scale_values.has(tank_scale):
			return "Rocket tank scale options need unique positive scales."
		tank_scale_values.append(tank_scale)
	if not engine_count_ids.has(1) or not tank_scale_values.has(1.0):
		return "Rocket builder options must include one engine and a standard 1.0 tank scale."
	for part_variant in stage_parts:
		if not engine_count_ids.has(int(part_variant.get("engine_count", 1))):
			return "Rocket stage part %s uses an engine count not available in builder_options." % str(part_variant.get("id", "unnamed"))
	var designs: Array = [rocket.get("default_design")]
	for preset_id in presets:
		designs.append(presets[preset_id])
	for design_variant in designs:
		if not design_variant is Dictionary:
			return "Every rocket design must be an object."
		var design: Dictionary = design_variant
		if not design.get("stages") is Array:
			return "Rocket design %s must have a stages array." % str(design.get("name", "unnamed"))
		if design.stages.is_empty():
			return "Rocket design %s must have at least one stage." % str(design.get("name", "unnamed"))
		var design_error := _numeric_fields_error(design, ["payload_mass"], "rocket design %s" % str(design.get("name", "unnamed")))
		if not design_error.is_empty():
			return design_error
		if float(design.payload_mass) <= 0.0:
			return "Rocket design %s must have positive payload mass." % str(design.get("name", "unnamed"))
		if design.has("payload_id") and not payload_ids.has(str(design.payload_id)):
			return "Rocket design %s references unknown payload %s." % [str(design.get("name", "unnamed")), str(design.payload_id)]
		for part_id_variant in design.get("stages", []):
			if not part_ids.has(str(part_id_variant)):
				return "Rocket design %s references unknown stage part %s." % [str(design.get("name", "unnamed")), str(part_id_variant)]
	var missions: Variant = catalog.get("missions", [])
	if not missions is Array:
		return "The missions section must be an array."
	var mission_ids := {}
	var mission_conditions := ["orbit_body", "visit_body", "discover_body", "discover_count", "operational_satellites"]
	for mission_variant in missions:
		if not mission_variant is Dictionary:
			return "Every mission entry must be an object."
		var mission: Dictionary = mission_variant
		var mission_id := str(mission.get("id", ""))
		var condition := str(mission.get("condition", ""))
		if mission_id.is_empty() or mission_ids.has(mission_id) or str(mission.get("title", "")).is_empty() or str(mission.get("description", "")).is_empty():
			return "Mission ids, titles and descriptions must be non-empty and unique."
		if not mission_conditions.has(condition):
			return "Mission %s has an unsupported condition." % mission_id
		var mission_reward_error := _numeric_fields_error(mission, ["reward"], "mission %s" % mission_id)
		if not mission_reward_error.is_empty() or not is_finite(float(mission.reward)) or float(mission.reward) < 0.0:
			return "Mission %s has an invalid reward." % mission_id
		if condition in ["orbit_body", "visit_body", "discover_body"] and str(mission.get("body", "")).is_empty():
			return "Mission %s needs a body name." % mission_id
		if condition in ["discover_count", "operational_satellites"]:
			var count_value: Variant = mission.get("count")
			var count_type := typeof(count_value)
			if (count_type != TYPE_INT and count_type != TYPE_FLOAT) or int(count_value) < 1 or not is_equal_approx(float(count_value), float(int(count_value))):
				return "Mission %s needs a positive whole-number count." % mission_id
		mission_ids[mission_id] = true
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
