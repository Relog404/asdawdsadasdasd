extends CanvasLayer

const TEXT_MAIN := Color("#f3f1e8")
const TEXT_MUTED := Color("#afbbb1")
const ACCENT := Color("#d5ef9b")


func _ready() -> void:
	var screen := Control.new()
	screen.name = "Overlay"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)

	var header := _panel(screen, Rect2(30, 26, 278, 84), Color(0.075, 0.105, 0.09, 0.80))
	_label(header, "ПОЛЕ ТИШИНЫ", Vector2(17, 12), Vector2(245, 29), 20, TEXT_MAIN, true)
	_label(header, "свободная прогулка", Vector2(18, 45), Vector2(235, 21), 13, TEXT_MUTED)
	_label(
		screen,
		"●  МИР ЗАГРУЖЕН",
		Vector2(0, 34),
		Vector2(250, 22),
		12,
		ACCENT,
		true,
		HORIZONTAL_ALIGNMENT_RIGHT,
		true
	)

	var controls := _panel(screen, Rect2(30, -166, 314, 136), Color(0.075, 0.105, 0.09, 0.80))
	controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(30, -166)
	controls.size = Vector2(314, 136)
	_label(controls, "УПРАВЛЕНИЕ", Vector2(16, 12), Vector2(270, 20), 11, ACCENT, true)
	_label(
		controls,
		"W A S D   ходить    ·    Shift   бежать",
		Vector2(16, 39),
		Vector2(285, 20),
		13,
		TEXT_MAIN
	)
	_label(
		controls,
		"C / Ctrl   присесть    ·    Z   зига",
		Vector2(16, 64),
		Vector2(285, 20),
		13,
		TEXT_MAIN
	)
	_label(
		controls,
		"Мышь   обзор    ·    колесо   зум",
		Vector2(16, 89),
		Vector2(285, 20),
		13,
		TEXT_MUTED
	)

	var hint := _panel(screen, Rect2(-250, -55, 220, 35), Color(0.075, 0.105, 0.09, 0.72))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-250, -55)
	hint.size = Vector2(220, 35)
	_label(
		hint,
		"Кликни, чтобы вращать камеру",
		Vector2(12, 8),
		Vector2(198, 18),
		11,
		TEXT_MUTED,
		false,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _panel(parent: Control, rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_color = Color(0.82, 0.9, 0.76, 0.15)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(
	parent: Control,
	text: String,
	offset: Vector2,
	label_size: Vector2,
	font_size: int,
	color: Color,
	bold := false,
	alignment := HORIZONTAL_ALIGNMENT_LEFT,
	anchored_right := false
) -> void:
	var label := Label.new()
	label.text = text
	label.position = offset
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.18))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if anchored_right:
		label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		label.position = Vector2(-280, offset.y)
	parent.add_child(label)
