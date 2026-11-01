extends LineEdit

var blink_time := 0.0

func _ready() -> void:
	add_theme_color_override("caret_color", Color.TRANSPARENT)
	expand_to_text_length = true
	grab_focus()

func _process(delta: float) -> void:
	blink_time += delta
	queue_redraw()

func _draw() -> void:
	if not has_focus():
		return
	if fmod(blink_time, 1.0) >= 0.5:
		return

	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var before_cursor := text.substr(0, caret_column)
	var left_margin := get_theme_stylebox("normal").get_margin(SIDE_LEFT)

	var x := left_margin + font.get_string_size(
		before_cursor, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x
	var y := (size.y - font.get_height(font_size)) / 2.0
	y += font.get_ascent(font_size)

	draw_string(
		font, Vector2(x, y), "_",
		HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, get_theme_color("font_color")
	)
