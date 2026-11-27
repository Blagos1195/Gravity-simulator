extends RefCounted

static func create_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 14
	result.set_color("font_color", "Label", Color(0.82, 0.89, 0.96))
	result.set_color("font_color", "Button", Color(0.86, 0.93, 1.0))
	result.set_color("font_hover_color", "Button", Color(0.96, 0.99, 1.0))
	result.set_color("font_pressed_color", "Button", Color(1.0, 1.0, 1.0))
	result.set_color("font_disabled_color", "Button", Color(0.38, 0.46, 0.56))
	result.set_color("font_color", "OptionButton", Color(0.86, 0.93, 1.0))
	result.set_color("font_color", "LineEdit", Color(0.9, 0.95, 1.0))
	result.set_color("font_placeholder_color", "LineEdit", Color(0.42, 0.51, 0.62))
	result.set_color("font_color", "SpinBox", Color(0.9, 0.95, 1.0))
	result.set_color("font_color", "CheckBox", Color(0.82, 0.89, 0.96))
	result.set_color("font_color", "CheckButton", Color(0.82, 0.89, 0.96))
	result.set_stylebox("panel", "PanelContainer", _surface(Color(0.025, 0.043, 0.071, 0.96), Color(0.16, 0.29, 0.42, 0.9), 9, 14))
	result.set_stylebox("normal", "Button", _surface(Color(0.055, 0.095, 0.15), Color(0.19, 0.34, 0.48), 6, 12))
	result.set_stylebox("hover", "Button", _surface(Color(0.085, 0.16, 0.24), Color(0.28, 0.57, 0.76), 6, 12))
	result.set_stylebox("pressed", "Button", _surface(Color(0.08, 0.24, 0.34), Color(0.31, 0.72, 0.91), 6, 12))
	result.set_stylebox("disabled", "Button", _surface(Color(0.035, 0.055, 0.08), Color(0.12, 0.18, 0.25), 6, 12))
	result.set_stylebox("focus", "Button", _outline(Color(0.3, 0.72, 0.94), 6))
	for type in ["OptionButton", "MenuButton"]:
		result.set_stylebox("normal", type, _surface(Color(0.035, 0.065, 0.105), Color(0.17, 0.3, 0.43), 6, 10))
		result.set_stylebox("hover", type, _surface(Color(0.06, 0.12, 0.18), Color(0.27, 0.52, 0.7), 6, 10))
		result.set_stylebox("pressed", type, _surface(Color(0.07, 0.2, 0.29), Color(0.3, 0.66, 0.85), 6, 10))
		result.set_stylebox("disabled", type, _surface(Color(0.03, 0.05, 0.07), Color(0.1, 0.16, 0.22), 6, 10))
		result.set_stylebox("focus", type, _outline(Color(0.3, 0.72, 0.94), 6))
	for type in ["LineEdit", "SpinBox"]:
		result.set_stylebox("normal", type, _surface(Color(0.018, 0.035, 0.06), Color(0.16, 0.29, 0.42), 5, 9))
		result.set_stylebox("focus", type, _surface(Color(0.025, 0.05, 0.08), Color(0.3, 0.65, 0.86), 5, 9))
		result.set_stylebox("read_only", type, _surface(Color(0.03, 0.045, 0.065), Color(0.12, 0.19, 0.27), 5, 9))
	result.set_stylebox("panel", "PopupMenu", _surface(Color(0.025, 0.045, 0.075), Color(0.2, 0.36, 0.5), 7, 8))
	result.set_stylebox("hover", "PopupMenu", _surface(Color(0.08, 0.17, 0.25), Color(0.08, 0.17, 0.25), 4, 8))
	result.set_stylebox("tab_selected", "TabContainer", _surface(Color(0.08, 0.19, 0.28), Color(0.28, 0.62, 0.82), 6, 10))
	result.set_stylebox("tab_unselected", "TabContainer", _surface(Color(0.035, 0.065, 0.1), Color(0.14, 0.24, 0.34), 6, 10))
	result.set_stylebox("tab_hovered", "TabContainer", _surface(Color(0.06, 0.12, 0.18), Color(0.22, 0.42, 0.58), 6, 10))
	result.set_stylebox("background", "ProgressBar", _surface(Color(0.018, 0.03, 0.05), Color(0.13, 0.23, 0.33), 4, 2))
	result.set_stylebox("fill", "ProgressBar", _surface(Color(0.12, 0.48, 0.68), Color(0.12, 0.48, 0.68), 4, 2))
	for type in ["TextEdit", "CodeEdit"]:
		result.set_stylebox("normal", type, _surface(Color(0.018, 0.035, 0.06), Color(0.16, 0.29, 0.42), 5, 9))
		result.set_stylebox("focus", type, _surface(Color(0.025, 0.05, 0.08), Color(0.3, 0.65, 0.86), 5, 9))
		result.set_stylebox("read_only", type, _surface(Color(0.03, 0.045, 0.065), Color(0.12, 0.19, 0.27), 5, 9))
		result.set_color("font_color", type, Color(0.88, 0.93, 1.0))
		result.set_color("font_placeholder_color", type, Color(0.42, 0.51, 0.62))
		result.set_color("caret_color", type, Color(0.35, 0.75, 0.98))
		result.set_color("selection_color", type, Color(0.12, 0.38, 0.58, 0.65))
	for type in ["Tree", "ItemList"]:
		result.set_stylebox("panel", type, _surface(Color(0.018, 0.035, 0.06), Color(0.14, 0.25, 0.36), 6, 8))
		result.set_stylebox("focus", type, _outline(Color(0.3, 0.72, 0.94), 5))
		result.set_color("font_color", type, Color(0.82, 0.89, 0.96))
		result.set_color("font_selected_color", type, Color(0.98, 1.0, 1.0))
		result.set_color("font_hovered_color", type, Color(0.65, 0.86, 1.0))
	result.set_stylebox("hover", "Tree", _surface(Color(0.055, 0.12, 0.18), Color(0.15, 0.3, 0.42), 3, 4))
	result.set_stylebox("selected", "Tree", _surface(Color(0.07, 0.2, 0.29), Color(0.24, 0.54, 0.72), 3, 4))
	result.set_stylebox("selected_focus", "Tree", _surface(Color(0.08, 0.22, 0.32), Color(0.3, 0.66, 0.85), 3, 4))
	result.set_stylebox("cursor", "ItemList", _surface(Color(0.07, 0.2, 0.29), Color(0.24, 0.54, 0.72), 3, 4))
	result.set_stylebox("cursor_unfocused", "ItemList", _surface(Color(0.045, 0.09, 0.14), Color(0.16, 0.29, 0.42), 3, 4))
	result.set_stylebox("normal", "RichTextLabel", _surface(Color(0.018, 0.035, 0.06), Color(0.14, 0.25, 0.36), 5, 8))
	result.set_color("default_color", "RichTextLabel", Color(0.82, 0.89, 0.96))
	result.set_color("selection_color", "RichTextLabel", Color(0.12, 0.38, 0.58, 0.65))
	for type in ["HSlider", "VSlider"]:
		result.set_stylebox("slider", type, _surface(Color(0.018, 0.03, 0.05), Color(0.13, 0.23, 0.33), 4, 2))
		result.set_stylebox("grabber_area", type, _surface(Color(0.12, 0.48, 0.68), Color(0.12, 0.48, 0.68), 4, 2))
		result.set_stylebox("grabber_area_highlight", type, _surface(Color(0.2, 0.62, 0.82), Color(0.2, 0.62, 0.82), 4, 2))
	for item in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		result.set_stylebox(item, "ScrollBar", _surface(Color(0.035, 0.065, 0.1), Color(0.16, 0.29, 0.42), 5, 3))
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 8)
	result.set_constant("h_separation", "GridContainer", 8)
	result.set_constant("v_separation", "GridContainer", 8)
	return result


static func _surface(background: Color, border: Color, radius: int, padding: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.65
	style.content_margin_bottom = padding * 0.65
	return style


static func _outline(border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
