extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const SimulationView = preload("res://scripts/simulation_view.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const SpaceDiscovery = preload("res://scripts/space_discovery.gd")

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
	assert(first.visible == false)
	assert(second.visible)
	assert(not first.input_enabled)
	assert(second.input_enabled)
	assert(not first.is_processing(), "Fleet vehicles must not advance both through their own process and the fleet manager")
	assert(first.vehicle_name == "Vehicle 1")
	assert(second.vehicle_name == "Vehicle 2")
	main._switch_vehicle(0)
	first.rocket_position = Vector2(1.0e9, 0.0)
	second.landed = false
	second.rocket_position = Vector2(0.0, -(PlanetarySystem.EARTH_RADIUS + 200000.0))
	second.velocity = Vector2(FlightComputer.circular_orbit_speed(PlanetarySystem.EARTH_RADIUS + 200000.0), 0.0)
	main._update_passive_orbit_states()
	assert(second.passive_orbit_active, "Inactive stable spacecraft was not moved to passive orbit propagation")
	var passive_start := second.rocket_position
	main._advance_passive_vehicle(second, 120.0)
	assert(second.rocket_position.distance_to(passive_start) > 1000.0, "Passive spacecraft did not advance along its orbit")
	assert(is_equal_approx(second.sim_time, 120.0))
	second.payload_visual = {"visual_type": "satellite", "telescope_range_au": 100.0}
	main._update_discovery_state()
	assert(not SpaceDiscovery.is_spotted(main.discovery_state, "Mars"), "An inactive telescope revealed Mars")
	var ephemeris := PlanetarySystem.gravity_body_states(main.sim.sim_time)
	var telescope_position: Vector2 = ephemeris.get("earth_heliocentric_position", Vector2.ZERO) + second.rocket_position
	for body in ephemeris.get("heliocentric_bodies", []):
		if str(body.get("name", "")) == "Mars":
			second.telescope_direction_angle = (Vector2(body.get("position", Vector2.ZERO)) - telescope_position).angle()
	second.telescope_active = true
	main._update_discovery_state()
	assert(SpaceDiscovery.is_spotted(main.discovery_state, "Mars"), "An active telescope aimed at Mars did not reveal it")
	assert(not SpaceDiscovery.is_visited(main.discovery_state, "Mars"), "Telescope discovery incorrectly unlocked autopilot")
	second.passive_orbit_forced = true
	second.passive_orbit_active = false
	second.passive_orbit_data.clear()
	second.sim_time = first.sim_time
	first.rocket_position = Vector2(0.0, -PlanetarySystem.EARTH_RADIUS - 2.0)
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
	second.landed = false
	second.rocket_position = Vector2(PlanetarySystem.EARTH_RADIUS + 200000.0, 0.0)
	second.velocity = Vector2(0.0, 7780.0)
	second.autopilot_enabled = true
	second.autopilot_phase = "TRANSFER_COAST"
	var second_start_position := second.rocket_position
	main._advance_fleet(0.02)
	assert(first.sim_time > 0.0)
	assert(is_equal_approx(first.sim_time, second.sim_time))
	assert(second.rocket_position.distance_to(second_start_position) > 0.0)
	assert(second.autopilot_enabled)
	assert(first.vehicle_name == "Vehicle 1")
	assert(second.vehicle_name == "Vehicle 2")
	main._switch_vehicle(1)
	assert(main.sim == second)
	assert(main._rename_vehicle("Vehicle 2", "Lunar Relay"))
	assert(not main._rename_vehicle("Lunar Relay", "Vehicle 1"))
	assert(main.fleet_sims[1].vehicle_name == "Lunar Relay")
	SpaceDiscovery.mark_visited(main.discovery_state, "Mars")
	main.save_slot = 8
	main._save_game(false)
	var save_path := "user://saves/slot_08.json"
	assert(FileAccess.file_exists(save_path))
	var save_file := FileAccess.open(save_path, FileAccess.READ)
	var saved_data: Dictionary = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	assert(saved_data.get("vehicles", []).size() == 2)
	assert(int(saved_data.get("active_vehicle_index", -1)) == 1)
	assert(bool(saved_data.discovery_state.Mars.visited))
	main.discovery_state = SpaceDiscovery.new_campaign_state()
	main._load_game_from_path(save_path)
	assert(SpaceDiscovery.is_visited(main.discovery_state, "Mars"), "Saved planetary discoveries were not restored")
	assert(main.fleet_sims.size() == 2)
	assert(main.active_vehicle_index == 1)
	assert(main.sim.vehicle_name == "Lunar Relay")
	first = main.fleet_sims[0]
	assert(is_equal_approx(main.fleet_sims[0].sim_time, main.fleet_sims[1].sim_time))
	for i in range(12):
		main._add_new_vehicle()
	assert(main.fleet_sims.size() == 14)
	first.landed = false
	first.crashed = false
	first._set_rocket_position_components(0.0, -(PlanetarySystem.EARTH_RADIUS + 200000.0))
	first.velocity = Vector2(FlightComputer.circular_orbit_speed(PlanetarySystem.EARTH_RADIUS + 200000.0), 0.0)
	var parent_position := first.rocket_position_precise.duplicate()
	var parent_velocity := first.velocity
	var separated_fuel := first.fuel
	first._separate_stage()
	main._advance_fleet(0.0)
	assert(main.fleet_sims.size() == 15, "Separated stage was not added to the spacecraft fleet")
	var debris: SimulationView
	for vehicle in main.fleet_sims:
		if vehicle.is_debris:
			debris = vehicle
			break
	assert(debris != null, "Separated stage was not marked as debris")
	assert(debris.rocket_position.distance_to(Vector2(parent_position[0], parent_position[1])) < 1.0)
	assert(is_equal_approx(debris.fuel, separated_fuel))
	assert(debris.rocket_stages.size() == 1)
	assert(debris.velocity.distance_to(parent_velocity) > 0.1)
	assert(not debris.input_enabled)
	main._save_game(false)
	save_file = FileAccess.open(save_path, FileAccess.READ)
	saved_data = JSON.parse_string(save_file.get_as_text())
	save_file.close()
	var saved_debris_found := false
	for saved_vehicle in saved_data.get("vehicles", []):
		if bool(saved_vehicle.get("state", {}).get("is_debris", false)):
			saved_debris_found = true
			break
	assert(saved_debris_found, "Discarded stage was not persisted in the campaign save")
	debris._set_rocket_position_components(0.0, -(PlanetarySystem.EARTH_RADIUS + 0.5))
	main._advance_fleet(0.0)
	assert(not main.fleet_sims.has(debris), "Debris that reached a planet was not removed")
	var collision_target: SimulationView = main.fleet_sims[1]
	for vehicle in main.fleet_sims:
		vehicle.landed = true
		vehicle.crashed = false
		vehicle.passive_orbit_active = false
		vehicle.thrust_key_down = false
		vehicle.autopilot_enabled = false
	first.landed = false
	collision_target.landed = false
	first._set_rocket_position_components(1000000000.0, 0.0)
	collision_target._set_rocket_position_components(1000000010.0, 0.0)
	first.velocity = Vector2(1000.0, 0.0)
	collision_target.velocity = Vector2(-1000.0, 0.0)
	main._switch_vehicle(0)
	main._advance_fleet(0.02)
	assert(first.crashed, "First spacecraft did not crash after a swept collision")
	assert(collision_target.crashed, "Second spacecraft did not crash after a swept collision")
	assert(not first.input_enabled and not collision_target.input_enabled, "A crashed spacecraft still accepted flight controls")
	assert(not first.collision_effects.is_empty(), "A spacecraft collision did not create an explosion effect")
	var wreck_start := first.rocket_position
	var wreck_velocity := first.velocity
	first._physics_step(1.0)
	assert(first.rocket_position.distance_to(wreck_start) > 0.1, "A crashed wreck stopped moving instead of continuing under physics")
	assert(first.velocity.distance_to(wreck_velocity) > 0.000001, "A crashed wreck stopped responding to gravity")
	assert(first.crashed and not first.input_enabled and is_zero_approx(first.throttle), "Wreck physics restored control or engine thrust")
	first._set_rocket_position_components(0.0, -(PlanetarySystem.EARTH_RADIUS + 200000.0))
	first.velocity = Vector2(FlightComputer.circular_orbit_speed(PlanetarySystem.EARTH_RADIUS + 200000.0), 0.0)
	main._switch_vehicle(1)
	main._update_passive_orbit_states()
	assert(first.passive_orbit_active, "A stable wreck was excluded from normal passive orbit simulation")
	var passive_wreck_start := first.rocket_position
	main._advance_passive_vehicle(first, first.sim_time + 60.0)
	assert(first.rocket_position.distance_to(passive_wreck_start) > 100.0, "A passively simulated wreck did not continue around its orbit")
	var live_vehicle: SimulationView = main.fleet_sims[2]
	live_vehicle.landed = false
	live_vehicle.crashed = false
	live_vehicle._set_rocket_position_components(first.rocket_position.x + 5.0, first.rocket_position.y)
	first._set_rocket_position_components(1000000000.0, 0.0)
	live_vehicle._set_rocket_position_components(1000000005.0, 0.0)
	first.velocity = Vector2(100.0, 0.0)
	live_vehicle.velocity = Vector2(-100.0, 0.0)
	var positions_before := {first: first.rocket_position, live_vehicle: live_vehicle.rocket_position}
	main._resolve_spacecraft_collisions(positions_before)
	assert(first.crashed and live_vehicle.crashed, "A live spacecraft passed through an existing wreck")
	assert(bool(first.get_save_data().crashed) and bool(collision_target.get_save_data().crashed), "Crash state was not included in save data")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Multi-vehicle simulation test passed.")
	main.queue_free()
	quit()
