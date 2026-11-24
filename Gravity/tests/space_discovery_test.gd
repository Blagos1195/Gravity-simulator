extends SceneTree

const SpaceDiscovery = preload("res://scripts/space_discovery.gd")

func _initialize() -> void:
	_validate_campaign_defaults()
	_validate_telescope_range()
	_validate_permanent_knowledge()
	print("Space discovery tests passed.")
	quit()

func _validate_campaign_defaults() -> void:
	var state := SpaceDiscovery.new_campaign_state()
	assert(SpaceDiscovery.is_spotted(state, "Earth"))
	assert(SpaceDiscovery.is_visited(state, "Earth"))
	assert(SpaceDiscovery.is_spotted(state, "Moon"))
	assert(not SpaceDiscovery.is_visited(state, "Moon"))
	assert(not SpaceDiscovery.is_spotted(state, "Mars"))

func _validate_telescope_range() -> void:
	var state := SpaceDiscovery.new_campaign_state()
	var bodies: Array = [
		{"name": "Venus", "position": Vector2(0.7, 0.0)},
		{"name": "Mars", "position": Vector2(1.6, 0.0)},
		{"name": "Jupiter", "position": Vector2(5.2, 0.0)}
	]
	var found := SpaceDiscovery.scan_telescope(state, Vector2.ZERO, 1.0, bodies)
	assert(found == ["Venus"])
	assert(SpaceDiscovery.is_spotted(state, "Venus"))
	assert(not SpaceDiscovery.is_visited(state, "Venus"))
	assert(not SpaceDiscovery.is_spotted(state, "Mars"))
	assert(SpaceDiscovery.scan_telescope(state, Vector2.ZERO, 2.0, bodies, PI).is_empty())
	assert(not SpaceDiscovery.is_spotted(state, "Venus"))
	assert(SpaceDiscovery.scan_telescope(state, Vector2.ZERO, 1.0, bodies) == ["Venus"])
	assert(SpaceDiscovery.scan_telescope(state, Vector2(1.6, 0.0), 0.1, bodies) == ["Mars"])

func _validate_permanent_knowledge() -> void:
	var state := SpaceDiscovery.new_campaign_state()
	SpaceDiscovery.mark_visited(state, "Mars")
	assert(SpaceDiscovery.is_spotted(state, "Mars"))
	assert(SpaceDiscovery.is_visited(state, "Mars"))
	var restored := SpaceDiscovery.sanitize_state(state)
	assert(SpaceDiscovery.is_spotted(restored, "Mars"))
	assert(SpaceDiscovery.is_visited(restored, "Mars"))
	assert(SpaceDiscovery.is_spotted(restored, "Earth"))
