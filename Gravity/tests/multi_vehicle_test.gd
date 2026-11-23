extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

class FakeVehicle:
	extends SimulationView

	var step_calls := 0

	func _nearest_body_state(_position: Vector2, _position_components: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
		return {"name": "Earth", "distance": PlanetarySystem.EARTH_RADIUS + 2.0, "radius": PlanetarySystem.EARTH_RADIUS, "soi": 925000000.0}

	func _adaptive_step_size() -> float:
		return 0.0005

	func _physics_step(dt: float) -> void:
		sim_time += dt
		step_calls += 1

func _initialize() -> void:
	var main := Main.new()
	root.add_child(main)
	main.rocket_design = RocketDesign.create_default()
	main._start_flight()
	assert(main.fleet_sims.size() == 1)
	var first: SimulationView = main.fleet_sims[0]
	main._add_new_vehicle()
	assert(main.fleet_sims.size() == 2)
	var second: SimulationView = main.sim
	assert(first != second)
	assert(not first.visible)
	assert(second.visible)
	assert(not first.input_enabled)
	assert(second.input_enabled)
	assert(first.vehicle_name == "Vehicle 1")
	assert(second.vehicle_name == "Vehicle 2")
	main._switch_vehicle(0)
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_W
	key_event.pressed = true
	second._input(key_event)
	assert(not second.thrust_key_down)
	assert(main.sim == first)
	assert(first.visible)
	assert(not second.visible)
	assert(first.input_enabled)
	assert(not second.input_enabled)
	assert(first.get_save_data().get("vehicle_name", "") == "Vehicle 1")
	assert(second.get_save_data().get("vehicle_name", "") == "Vehicle 2")
	var fake_first := FakeVehicle.new()
	var fake_second := FakeVehicle.new()
	root.add_child(fake_first)
	root.add_child(fake_second)
	fake_first.visible = false
	fake_second.visible = false
	fake_first.set_process(false)
	fake_second.set_process(false)
	main.fleet_sims = [fake_first, fake_second]
	main.sim = fake_first
	main.fleet_time_backlog = 0.0
	main._advance_fleet(0.001)
	assert(is_equal_approx(fake_first.sim_time, fake_second.sim_time))
	assert(is_equal_approx(fake_first.sim_time, 0.001))
	assert(fake_first.step_calls == 2)
	assert(fake_second.step_calls == 2)
	print("Multi-vehicle simulation test passed.")
	main.queue_free()
	fake_first.queue_free()
	fake_second.queue_free()
	quit()
