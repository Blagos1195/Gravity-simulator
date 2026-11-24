extends RefCounted
class_name MissionSystem

const ContentCatalog = preload("res://scripts/content_catalog.gd")
const SpaceDiscovery = preload("res://scripts/space_discovery.gd")

static func definitions() -> Array:
	var missions: Variant = ContentCatalog.get_catalog().get("missions", [])
	return missions.duplicate(true) if missions is Array else []

static func new_state() -> Dictionary:
	return {"completed": {}}

static func sanitize_state(value: Variant) -> Dictionary:
	var state := new_state()
	if not value is Dictionary:
		return state
	var completed: Variant = value.get("completed", {})
	if completed is Dictionary:
		for mission_id in completed:
			if bool(completed[mission_id]):
				state.completed[str(mission_id)] = true
	return state

static func progress(mission: Dictionary, discovery_state: Dictionary, orbited_bodies: Dictionary, planet_names: Array, operational_satellites: int) -> Dictionary:
	var condition := str(mission.get("condition", ""))
	var target_body := str(mission.get("body", ""))
	var target_count := maxi(1, int(mission.get("count", 1)))
	var current := 0
	var complete := false
	match condition:
		"orbit_body":
			complete = orbited_bodies.has(target_body)
			current = 1 if complete else 0
		"visit_body":
			complete = SpaceDiscovery.is_visited(discovery_state, target_body)
			current = 1 if complete else 0
		"discover_body":
			complete = SpaceDiscovery.is_spotted(discovery_state, target_body)
			current = 1 if complete else 0
		"discover_count":
			for body_name in planet_names:
				if SpaceDiscovery.is_spotted(discovery_state, str(body_name)):
					current += 1
			complete = current >= target_count
		"operational_satellites":
			current = operational_satellites
			complete = current >= target_count
	return {"complete": complete, "current": current, "target": target_count}

static func evaluate(missions: Array, state: Dictionary, discovery_state: Dictionary, orbited_bodies: Dictionary, planet_names: Array, operational_satellites: int) -> Array[Dictionary]:
	var completed_now: Array[Dictionary] = []
	var completed: Dictionary = state.get("completed", {})
	for mission_variant in missions:
		if not mission_variant is Dictionary:
			continue
		var mission: Dictionary = mission_variant
		var mission_id := str(mission.get("id", ""))
		if mission_id.is_empty() or completed.has(mission_id):
			continue
		if bool(progress(mission, discovery_state, orbited_bodies, planet_names, operational_satellites).complete):
			completed[mission_id] = true
			completed_now.append(mission.duplicate(true))
	state["completed"] = completed
	return completed_now
