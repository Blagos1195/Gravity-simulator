extends SceneTree

const GravityTheme = preload("res://scripts/ui_theme.gd")

func _initialize() -> void:
	var theme := GravityTheme.create_theme()
	assert(theme.default_font_size == 14)
	assert(theme.get_stylebox("normal", "Button") is StyleBoxFlat)
	assert(theme.get_stylebox("hover", "Button") is StyleBoxFlat)
	assert(theme.get_stylebox("panel", "PanelContainer") is StyleBoxFlat)
	assert(theme.get_stylebox("normal", "OptionButton") is StyleBoxFlat)
	assert(theme.get_stylebox("focus", "LineEdit") is StyleBoxFlat)
	assert(theme.get_color("font_color", "Label").is_equal_approx(Color(0.82, 0.89, 0.96)))
	print("Shared UI theme tests passed.")
	quit()
