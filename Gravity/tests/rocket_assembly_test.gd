extends SceneTree

const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	var original: Dictionary = design["stages"][0]
	var original_dry_mass := RocketDesign.stage_total_dry_mass(original)
	var original_fuel := RocketDesign.stage_total_fuel_capacity(original)
	var original_thrust := RocketDesign.stage_total_thrust(original)
	var original_vacuum_thrust := RocketDesign.stage_total_thrust(original, true)
	var original_flow := RocketDesign.stage_total_flow(original)
	var assembled := RocketAssembly.ensure_stage_components(original)
	assert(bool(assembled.get("component_assembly", false)))
	assert(assembled.get("components", []).size() == 2)
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(assembled), original_dry_mass))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(assembled), original_fuel))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(assembled), original_thrust))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(assembled, true), original_vacuum_thrust))
	assert(is_equal_approx(RocketDesign.stage_total_flow(assembled), original_flow))
	var with_tank := RocketAssembly.add_component(assembled, "medium_tank")
	assert(not with_tank.is_empty())
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(with_tank), original_dry_mass + 6000.0))
	assert(is_equal_approx(RocketDesign.stage_total_fuel_capacity(with_tank), original_fuel + 80000.0))
	var with_engine := RocketAssembly.add_component(with_tank, "vacuum_engine")
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(with_engine), original_dry_mass + 6900.0))
	assert(is_equal_approx(RocketDesign.stage_total_thrust(with_engine, true), original_vacuum_thrust + 310000.0))
	assert(is_equal_approx(RocketDesign.stage_total_flow(with_engine), original_flow + 85.0))
	var without_engine := RocketAssembly.remove_component(with_engine, with_engine.components.size() - 1)
	assert(is_equal_approx(RocketDesign.stage_total_thrust(without_engine, true), original_vacuum_thrust))
	var reordered := RocketAssembly.move_component(with_engine, 2, -1)
	assert(str(reordered.components[1].get("id", "")) == "medium_tank", "Component stack order was not updated")
	assert(is_equal_approx(RocketDesign.stage_total_dry_mass(reordered), RocketDesign.stage_total_dry_mass(with_engine)))
	assert(RocketAssembly.move_component(with_engine, 0, -1).is_empty())
	assert(RocketAssembly.move_component(with_engine, with_engine.components.size() - 1, 1).is_empty())
	assert(RocketAssembly.component_options().size() >= 10)
	assert(RocketAssembly.remove_component(assembled, 99).is_empty())
	design["stages"][0] = with_engine
	assert(RocketDesign.validation_errors(design).is_empty(), "A valid component-built stage failed rocket validation")
	var main := Main.new()
	root.add_child(main)
	main.rocket_design = design
	main._show_vehicle_editor()
	main._show_vehicle_component_editor(0)
	var editor_found := false
	for child in main.get_children():
		if child is Window and str(child.title).contains("COMPONENT ASSEMBLY"):
			editor_found = true
			break
	assert(editor_found, "The component assembly editor did not open")
	print("Rocket component assembly tests passed.")
	main.queue_free()
	quit()
