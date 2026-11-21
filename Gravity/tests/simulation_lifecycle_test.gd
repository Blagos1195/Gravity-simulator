extends SceneTree

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

func _initialize() -> void:
	_validate_launch_and_fuel()
	_validate_staging()
	_validate_atmospheric_forces()
	_validate_surface_contact()
	print("Simulation lifecycle tests passed.")
	quit()

func _validate_launch_and_fuel() -> void:
	var simulation: Variant = SimulationView.new()
	var design := RocketDesign.create_default()
	simulation.set_rocket_design(design)
	simulation.realism = "Realistic"
	simulation.landed = true
	simulation.landed_body_name = "Earth"
	simulation.landed_surface_normal = Vector2.UP
	simulation._set_rocket_position_components(0.0, -PlanetarySystem.EARTH_RADIUS - 0.5)
	var initial_mass: float = simulation._current_vehicle_mass()
	var initial_fuel: float = simulation.fuel
	simulation.thrust_key_down = true
	simulation._physics_step(0.05)
	assert(not simulation.landed)
	var elapsed := 0.0
	while elapsed < 60.0 and not simulation.crashed:
		var step: float = minf(simulation._adaptive_step_size(), 60.0 - elapsed)
		assert(step > 0.000001)
		simulation._physics_step(step)
		elapsed += step
	assert(not simulation.crashed)
	assert(simulation.rocket_position.length() > PlanetarySystem.EARTH_RADIUS + 1000.0)
	assert(simulation.fuel < initial_fuel)
	assert(simulation._current_vehicle_mass() < initial_mass)
	assert(simulation.velocity.length() > 100.0)
	simulation.free()

func _validate_staging() -> void:
	var simulation: Variant = SimulationView.new()
	var design := RocketDesign.create_default()
	simulation.set_rocket_design(design)
	simulation.fuel = 0.0
	var first_stage_dry_mass: float = float(design.stages[0].dry_mass)
	var first_stage_fuel: float = float(design.stages[0].fuel_capacity)
	var second_stage_fuel: float = float(design.stages[1].fuel_capacity)
	simulation._separate_stage()
	assert(simulation.stage_index == 1)
	assert(is_equal_approx(simulation.fuel, second_stage_fuel))
	assert(is_equal_approx(simulation.discarded_stage_mass, first_stage_dry_mass))
	assert(not simulation.thrust_key_down)
	var mass_after_separation: float = simulation._current_vehicle_mass()
	assert(mass_after_separation < RocketDesign.total_initial_mass(design) - first_stage_fuel)
	simulation._separate_stage()
	assert(simulation.stage_index == 1)
	simulation.free()

func _validate_atmospheric_forces() -> void:
	var simulation: Variant = SimulationView.new()
	simulation.realism = "Realistic"
	var earth_radius: float = PlanetarySystem.EARTH_RADIUS
	var atmospheric_position := Vector2(0.0, -earth_radius - 10000.0)
	var atmospheric_velocity := Vector2(2000.0, 0.0)
	var drag: Vector2 = simulation._aerodynamic_acceleration(atmospheric_position, atmospheric_velocity, 10000.0, 0.0, PackedFloat64Array([atmospheric_position.x, atmospheric_position.y]))
	assert(drag.is_finite())
	assert(drag.length() > 0.0001)
	assert(drag.dot(atmospheric_velocity) < 0.0)
	var vacuum_position := Vector2(0.0, -earth_radius - 200000.0)
	var vacuum_drag: Vector2 = simulation._aerodynamic_acceleration(vacuum_position, atmospheric_velocity, 10000.0, 0.0, PackedFloat64Array([vacuum_position.x, vacuum_position.y]))
	assert(vacuum_drag.length() < 0.000001)
	simulation.free()

func _validate_surface_contact() -> void:
	var simulation: Variant = SimulationView.new()
	var earth: Dictionary = simulation._surface_body_state("Earth")
	var normal := Vector2.RIGHT
	simulation._set_rocket_position_relative_to_body(earth, normal * (float(earth.radius) + 0.1))
	simulation.velocity = earth.velocity + Vector2(-normal.y, normal.x) * float(earth.radius) * float(earth.rotation_rate)
	simulation._handle_body_contact()
	assert(simulation.landed)
	assert(not simulation.crashed)
	assert(simulation.landed_body_name == "Earth")
	simulation.free()
