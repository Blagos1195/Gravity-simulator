extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Variant = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	assert(main.mode == "menu")
	assert(main.menu_root != null)
	main.rocket_design = RocketAssembly.add_preset_hardware(RocketDesign.create_default())
	main._start_flight()
	await process_frame
	assert(main.mode == "flight")
	assert(main.sim != null)
	assert(main.fleet_sims.size() == 1)
	assert(main.flight_hud_top != null)
	assert(main.flight_hud_right_panel != null)
	assert(main.flight_hud_bottom != null)
	var vehicle = main.sim
	vehicle.landed = true
	vehicle.landed_body_name = "Earth"
	vehicle.landed_surface_normal = Vector2.UP
	vehicle._set_rocket_position_components(0.0, -PlanetarySystem.EARTH_RADIUS - 0.5)
	vehicle.thrust_key_down = true
	var elapsed := 0.0
	while elapsed < 10.0 and not vehicle.crashed:
		var step: float = minf(vehicle._adaptive_step_size(), 10.0 - elapsed)
		assert(step > 0.000001)
		vehicle._physics_step(step)
		elapsed += step
	assert(not vehicle.crashed)
	assert(vehicle.velocity.length() > 10.0)
	main.free()
	await process_frame
	print("Main menu, flight HUD and live vehicle runtime smoke tests passed.")
	quit()
