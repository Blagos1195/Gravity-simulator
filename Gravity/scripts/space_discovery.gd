extends RefCounted
class_name SpaceDiscovery

static func new_campaign_state() -> Dictionary:
	return {
		"Earth": {"spotted": true, "visited": true},
		"Moon": {"spotted": true, "visited": false}
	}

static func sanitize_state(value: Variant) -> Dictionary:
	var state := new_campaign_state()
	if not value is Dictionary:
		return state
	for raw_name in value:
		var body_name := str(raw_name).strip_edges()
		var entry: Variant = value[raw_name]
		if body_name.is_empty() or not entry is Dictionary:
			continue
		var spotted := bool(entry.get("spotted", false))
		var visited := bool(entry.get("visited", false))
		if spotted or visited:
			state[body_name] = {"spotted": spotted or visited, "visited": visited}
	return state

static func mark_spotted(state: Dictionary, body_name: String) -> bool:
	if body_name.is_empty():
		return false
	var entry: Dictionary = state.get(body_name, {"spotted": false, "visited": false})
	if bool(entry.get("spotted", false)):
		return false
	entry["spotted"] = true
	state[body_name] = entry
	return true

static func mark_visited(state: Dictionary, body_name: String) -> bool:
	if body_name.is_empty():
		return false
	var entry: Dictionary = state.get(body_name, {"spotted": false, "visited": false})
	var changed := not bool(entry.get("visited", false)) or not bool(entry.get("spotted", false))
	entry["spotted"] = true
	entry["visited"] = true
	state[body_name] = entry
	return changed

static func is_spotted(state: Dictionary, body_name: String) -> bool:
	return bool(state.get(body_name, {}).get("spotted", false))

static func is_visited(state: Dictionary, body_name: String) -> bool:
	return bool(state.get(body_name, {}).get("visited", false))

static func spotted_names(state: Dictionary) -> Dictionary:
	var result := {}
	for body_name in state:
		if is_spotted(state, str(body_name)):
			result[str(body_name)] = true
	return result

static func visited_names(state: Dictionary) -> Dictionary:
	var result := {}
	for body_name in state:
		if is_visited(state, str(body_name)):
			result[str(body_name)] = true
	return result

static func scan_telescope(state: Dictionary, telescope_position: Vector2, range_m: float, body_states: Array, pointing_angle: float = 0.0, field_of_view: float = PI / 6.0) -> Array[String]:
	var discovered: Array[String] = []
	if range_m <= 0.0 or field_of_view <= 0.0:
		return discovered
	var range_squared := range_m * range_m
	var half_field_of_view := minf(PI, field_of_view * 0.5)
	for body_variant in body_states:
		if not body_variant is Dictionary:
			continue
		var body: Dictionary = body_variant
		var body_name := str(body.get("name", ""))
		if body_name.is_empty() or body_name == "Sun" or is_spotted(state, body_name):
			continue
		var offset: Vector2 = Vector2(body.get("position", Vector2.ZERO)) - telescope_position
		if offset.length_squared() > range_squared or offset.length_squared() < 0.000001:
			continue
		var angular_offset := absf(wrapf(offset.angle() - pointing_angle, -PI, PI))
		if angular_offset <= half_field_of_view and mark_spotted(state, body_name):
			discovered.append(body_name)
	return discovered
