extends CanvasLayer

const KEYS := {
	KEY_KP_7: "upleft",
	KEY_KP_8: "up",
	KEY_KP_9: "upright",
	KEY_KP_4: "left",
	KEY_KP_5: "center",
	KEY_KP_6: "right",
	KEY_KP_1: "downleft",
	KEY_KP_2: "down",
	KEY_KP_3: "downright",
}

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not KEYS.has(event.keycode):
		return

	# Stop keypad directions from typing into the input.
	get_viewport().set_input_as_handled()

	if event.echo:
		return

	var button := get_node("numberpad/" + KEYS[event.keycode]) as Button

	if button.disabled:
		return

	if event.pressed:
		var dark := StyleBoxFlat.new()
		dark.bg_color = Color("#151515")
		button.add_theme_stylebox_override("normal", dark)
		button.add_theme_stylebox_override("hover", dark)
		button.pressed.emit()
	else:
		button.remove_theme_stylebox_override("normal")
		button.remove_theme_stylebox_override("hover")
		
func _ready() -> void:
	$sqrt.focus_mode = Control.FOCUS_NONE
	$sqrt.pressed.connect(insert_square_root)

func insert_square_root() -> void:
	var field := $Instructions/MagnitudeInput as LineEdit
	field.grab_focus()
	field.insert_text_at_caret("√")
