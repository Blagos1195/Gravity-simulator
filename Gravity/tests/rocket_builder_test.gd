extends SceneTree

const RocketBuilder = preload("res://scripts/rocket_builder.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

func _initialize() -> void:
	var design := RocketDesign.create_default()
	var builder := RocketBuilder.new()
	builder.configure(design, 0)
	builder._build_interface()
	builder._refresh()
	assert(builder.title == "VEHICLE ASSEMBLY BUILDING")
	assert(builder._parts_list.get_child_count() >= 14)
	assert(builder._stage_list.get_child_count() == design.stages.size())
	builder._add_component("medium_tank", "stack", true, 1, -1)
	var stage: Dictionary = builder.design.stages[0]
	assert(stage.components.size() == 3)
	assert(str(stage.components[2].id) == "medium_tank")
	builder._add_component("solid_booster_pair", "radial", true, -1, 1)
	stage = builder.design.stages[0]
	assert(bool(stage.components[3].mirror))
	assert(str(stage.components[3].attachment) == "radial")
	assert(int(stage.components[3].mount_index) == 1)
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(stage).dry_mass), 16000.0))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(stage).fuel_capacity), 84000.0))
	builder._update_component_property("mirror", false)
	stage = builder.design.stages[0]
	assert(not bool(stage.components[3].mirror))
	assert(is_equal_approx(float(RocketDesign.stage_booster_stats(stage).dry_mass), 8000.0))
	builder._undo_change()
	stage = builder.design.stages[0]
	assert(bool(stage.components[3].mirror))
	builder._redo_change()
	stage = builder.design.stages[0]
	assert(not bool(stage.components[3].mirror))
	builder._on_component_moved(2, 0)
	stage = builder.design.stages[0]
	assert(str(stage.components[0].id) == "medium_tank")
	assert(int(stage.components[3].mount_index) == 2)
	builder._remove_selected_component()
	stage = builder.design.stages[0]
	assert(int(stage.components[2].mount_index) == 1)
	assert(RocketDesign.validation_errors(builder.design).is_empty())
	var stage_count: int = builder.design.stages.size()
	builder._duplicate_selected_stage()
	assert(builder.design.stages.size() == stage_count + 1)
	var moved_stage: Dictionary = builder.design.stages[1].duplicate(true)
	builder._move_stage(-1)
	assert(builder.design.stages[0] == moved_stage)
	var emitted_designs: Array[Dictionary] = []
	builder.design_changed.connect(func(updated: Dictionary): emitted_designs.append(updated))
	builder._emit_design()
	assert(not emitted_designs.is_empty())
	builder.free()
	print("KSP-style vehicle assembly builder tests passed.")
	quit()
