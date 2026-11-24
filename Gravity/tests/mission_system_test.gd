extends SceneTree

const MissionSystem = preload("res://scripts/mission_system.gd")
const SpaceDiscovery = preload("res://scripts/space_discovery.gd")

func _initialize() -> void:
	var missions: Array = [
		{"id": "lunar_orbit", "condition": "orbit_body", "body": "Moon", "count": 1, "reward": 1000},
		{"id": "inner_survey", "condition": "discover_count", "count": 2, "reward": 2000},
		{"id": "satellite_network", "condition": "operational_satellites", "count": 2, "reward": 3000}
	]
	var state := MissionSystem.new_state()
	var discoveries := SpaceDiscovery.new_campaign_state()
	var orbited := {}
	var progress := MissionSystem.progress(missions[0], discoveries, orbited, ["Mercury", "Venus"], 0)
	assert(not bool(progress.complete))
	SpaceDiscovery.mark_spotted(discoveries, "Mercury")
	SpaceDiscovery.mark_spotted(discoveries, "Venus")
	assert(bool(MissionSystem.progress(missions[1], discoveries, orbited, ["Mercury", "Venus"], 0).complete))
	var completed := MissionSystem.evaluate(missions, state, discoveries, orbited, ["Mercury", "Venus"], 0)
	assert(completed.size() == 1 and str(completed[0].id) == "inner_survey")
	orbited["Moon"] = true
	completed = MissionSystem.evaluate(missions, state, discoveries, orbited, ["Mercury", "Venus"], 2)
	assert(completed.size() == 2)
	assert(MissionSystem.evaluate(missions, state, discoveries, orbited, ["Mercury", "Venus"], 2).is_empty())
	var restored := MissionSystem.sanitize_state(state)
	assert(restored.completed.has("lunar_orbit"))
	assert(restored.completed.has("satellite_network"))
	print("Mission system tests passed.")
	quit()
