extends Node3D

@onready var vehicle: Node3D = $MerkabaCT2

@onready var magnitude_input: LineEdit = $HUD/Instructions/MagnitudeInput
@onready var prompt: Label = $HUD/Instructions/Prompt
@onready var equations: Label = $HUD/InstructionBlock/Equations
@onready var input_row: HBoxContainer = $HUD/Instructions


var moving := false
var stage := 0
var origin := Vector3.ZERO
var first_direction := Vector3.ZERO
var first_corner := Vector3.ZERO
var initial_row_position := Vector2.ZERO
var drawn_nodes: Array[Node] = []
var first_leg_label: Label3D
var shape_caption: Label3D
var square_opposite := Vector3.ZERO
var floor_display_map := Basis.IDENTITY
var root_two_trail: MeshInstance3D
var root_two_label: Label3D
var finished_cube: MeshInstance3D
var cube_outline_points: Array[Vector3] = []
var cube_upright_angle := 0.0
var ending_ready := false

const DIRECTIONS := {
	"upleft": Vector3(-1, 1, 0),
	"up": Vector3(0, 1, 0),
	"upright": Vector3(1, 1, 0),
	"left": Vector3(-1, 0, 0),
	"right": Vector3(1, 0, 0),
	"downleft": Vector3(-1, -1, 0),
	"down": Vector3(0, -1, 0),
	"downright": Vector3(1, -1, 0),
}


func _ready() -> void:
	if vehicle != null:
		origin = vehicle.position

	initial_row_position = input_row.global_position

	equations.text = ""
	prompt.text = "Enter magnitude of 1 and select a direction vector:"
	magnitude_input.text = ""
	magnitude_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	for button_name in DIRECTIONS:
		var button := get_node(
			"HUD/numberpad/" + button_name
		) as Button

		button.disabled = false
		button.pressed.connect(travel.bind(DIRECTIONS[button_name]))

	magnitude_input.grab_focus()


func read_magnitude() -> float:
	var entered := magnitude_input.text.strip_edges()

	if entered.begins_with("√"):
		var number := entered.substr(1).strip_edges()

		if number.is_valid_float():
			var value := float(number)

			if value >= 0.0:
				return sqrt(value)

		return -1.0

	if entered.is_valid_float():
		return float(entered)

	return -1.0


func travel(direction: Vector3) -> void:
	if moving or vehicle == null or stage >= 6:
		return

	if stage == 3:
		await retraverse_diagonal(direction)
		return

	if stage == 4:
		await extend_depth(direction)
		return
		
	if stage == 5:
		await return_from_depth(direction)
		return

	var magnitude := read_magnitude()
	var heading := direction.normalized()

	if stage < 2:
		if not is_equal_approx(magnitude, 1.0):
			return

		if stage == 1:
			if not is_zero_approx(first_direction.dot(heading)):
				return

	else:
		if not is_equal_approx(magnitude, sqrt(2.0)):
			return

		var return_direction := (
			origin - vehicle.position
		).normalized()

		if not heading.is_equal_approx(return_direction):
			return

	moving = true

	var start := vehicle.position
	var finish := start + heading * magnitude

	if stage == 2:
		finish = origin

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.CYAN

	var mesh := ImmediateMesh.new()
	var trail := MeshInstance3D.new()
	trail.mesh = mesh
	trail.material_override = material
	add_child(trail)
	drawn_nodes.append(trail)
	if stage == 2:
		root_two_trail = trail

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(vehicle, "position", finish, 0.5)
	tween.tween_method(
		update_trail.bind(start, mesh),
		start,
		finish,
		0.5
	)

	await tween.finished

	var label := Label3D.new()
	label.text = "√2" if stage == 2 else "1"
	label.font_size = 48
	label.pixel_size = 0.005
	label.no_depth_test = true
	add_child(label)
	drawn_nodes.append(label)
	if stage == 2:
		root_two_label = label

	if stage == 0:
		first_leg_label = label
		var sideways := Vector3(-heading.y, heading.x, 0)
		label.position = (start + finish) / 2.0 + sideways * 0.18
		label.position.z += 0.03

	elif stage == 1:
		# Position both unit labels outside the triangle.
		position_label_outside(
			first_leg_label, origin, first_corner, finish
		)
		position_label_outside(label, start, finish, origin)

	else:
		# Position the return label outside the triangle.
		position_label_outside(label, start, finish, first_corner)

	if stage == 0:
		first_direction = heading
		first_corner = finish

	stage += 1
	magnitude_input.clear()

	match stage:
		1:
			prompt.text = "Enter magnitude 1 and select a perpendicular vector:"

		2:
			equations.text = (
				"Return to the origin, find magnitude c:\n"
				+ "a² + b² = c²\n"
				+ "1² + 1² = c²"
			)

			prompt.text = "Enter Magnitude c and select the return vector:"

			# Allow the equations to finish resizing before positioning.
			await get_tree().process_frame

			input_row.global_position = equations.global_position + Vector2(
				0,
				equations.get_combined_minimum_size().y - 12
			)

		3:
			equations.text = ""
			prompt.text = ""
			magnitude_input.release_focus()

			await fade_in_other_half(start)
			await get_tree().create_timer(1.0).timeout
			await morph_to_rhombus(start)

			input_row.global_position = initial_row_position
			input_row.show()
			await get_tree().create_timer(2.0).timeout
			shape_caption.hide()
			prompt.text = "Retraverse the return vector:"
			magnitude_input.clear()
			magnitude_input.grab_focus()

			moving = false
			return
	moving = false
	magnitude_input.grab_focus()

func update_trail(
	end: Vector3,
	start: Vector3,
	mesh: ImmediateMesh
) -> void:
	mesh.clear_surfaces()

	if start.is_equal_approx(end):
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()

func fade_in_other_half(opposite_corner: Vector3) -> void:
	var fourth_corner := origin + opposite_corner - first_corner
	square_opposite = opposite_corner

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0, 1, 1, 0)

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# First missing side.
	mesh.surface_add_vertex(origin)
	mesh.surface_add_vertex(fourth_corner)

	# Second missing side.
	mesh.surface_add_vertex(fourth_corner)
	mesh.surface_add_vertex(opposite_corner)

	mesh.surface_end()

	var outline := MeshInstance3D.new()
	outline.mesh = mesh
	outline.material_override = material
	add_child(outline)
	drawn_nodes.append(outline)

	var fade := create_tween()
	fade.tween_property(
		material,
		"albedo_color",
		Color.CYAN,
		1.0
	)
	await fade.finished
	update_shape_caption("The Unit Square", Basis.IDENTITY)
	
func restart_round() -> void:
	for node in drawn_nodes:
		if is_instance_valid(node):
			node.queue_free()

	drawn_nodes.clear()

	vehicle.position = origin
	first_direction = Vector3.ZERO
	first_corner = Vector3.ZERO
	stage = 0
	moving = false

	equations.text = ""
	input_row.global_position = initial_row_position
	prompt.text = "Enter magnitude of 1 and select a direction vector:"
	magnitude_input.clear()
	magnitude_input.grab_focus()

func position_label_outside(
	label: Label3D,
	start: Vector3,
	finish: Vector3,
	opposite_corner: Vector3
) -> void:
	var midpoint := (start + finish) / 2.0
	var along := (finish - start).normalized()
	var outward := Vector3(-along.y, along.x, 0)

	if outward.dot(opposite_corner - midpoint) > 0.0:
		outward = -outward

	label.position = midpoint + outward * 0.18
	label.position.z += 0.03

func morph_to_rhombus(opposite_corner: Vector3) -> void:
	var edge_u := first_direction.normalized()
	var edge_v := (opposite_corner - first_corner).normalized()

	var new_u := edge_u
	var new_v := edge_v

	# Move only one edge clockwise toward the other.
	if edge_u.cross(edge_v).z > 0.0:
		new_v = edge_v.rotated(Vector3.BACK, deg_to_rad(-30.0))
	else:
		new_u = edge_u.rotated(Vector3.BACK, deg_to_rad(-30.0))

	var original_basis := Basis(edge_u, edge_v, Vector3.BACK)
	var rhombus_basis := Basis(new_u, new_v, Vector3.BACK)
	var target_map := rhombus_basis * original_basis.inverse()

	var initial_transforms: Array[Transform3D] = []

	for node in drawn_nodes:
		initial_transforms.append((node as Node3D).transform)

	var morph := create_tween()
	morph.set_trans(Tween.TRANS_SINE)
	morph.set_ease(Tween.EASE_IN_OUT)
	morph.tween_method(
		apply_rhombus_morph.bind(target_map, initial_transforms),
		0.0,
		1.0,
		1.5
	)

	await morph.finished
	floor_display_map = target_map
	update_shape_caption("The Unit Parallelogram", target_map)


func apply_rhombus_morph(
	weight: float,
	target_map: Basis,
	initial_transforms: Array[Transform3D]
) -> void:
	# Interpolate the drawing map, not the camera.
	var display_map := Basis(
		Vector3.RIGHT.lerp(target_map.x, weight),
		Vector3.UP.lerp(target_map.y, weight),
		Vector3.BACK
	)
	update_shape_caption("The Unit Square", display_map)
	
	for i in range(drawn_nodes.size()):
		var node := drawn_nodes[i] as Node3D
		var initial := initial_transforms[i]

		node.position = origin + display_map * (
			initial.origin - origin
		)

		if node is MeshInstance3D:
			node.basis = display_map * initial.basis

func update_shape_caption(
	caption_text: String,
	display_map: Basis
) -> void:
	if not is_instance_valid(shape_caption):
		shape_caption = Label3D.new()
		shape_caption.font_size = 36
		shape_caption.pixel_size = 0.005
		shape_caption.no_depth_test = true
		add_child(shape_caption)

	shape_caption.text = caption_text

	var fourth_corner := origin + square_opposite - first_corner
	var corners := [
		origin,
		first_corner,
		square_opposite,
		fourth_corner,
	]

	var left := INF
	var right := -INF
	var bottom := INF

	for corner in corners:
		var point: Vector3 = origin + display_map * (corner - origin)
		left = minf(left, point.x)
		right = maxf(right, point.x)
		bottom = minf(bottom, point.y)

	shape_caption.position = Vector3(
		(left + right) / 2.0,
		bottom - 0.4,
		origin.z + 0.05
	)

func retraverse_diagonal(direction: Vector3) -> void:
	if not is_equal_approx(read_magnitude(), sqrt(2.0)):
		return

	var original_diagonal := square_opposite - origin
	var correct_heading := original_diagonal.normalized()

	if not direction.normalized().is_equal_approx(correct_heading):
		return

	moving = true

	var destination := origin + floor_display_map * original_diagonal

	var tween := create_tween()
	tween.tween_property(vehicle, "position", destination, 0.5)
	await tween.finished

	stage = 4
	magnitude_input.clear()
	prompt.text = "Enter magnitude 1 and extend a vector of depth:"
	magnitude_input.grab_focus()
	moving = false

func extend_depth(direction: Vector3) -> void:
	if not is_equal_approx(read_magnitude(), 1.0):
		return

	# Find the two displayed sides of the floor.
	var side_u := floor_display_map * first_direction
	var side_v := floor_display_map * (
		square_opposite - first_corner
	)

	# The short diagonal sets our drawn depth direction.
	var depth_axis := (side_v - side_u).normalized()
	var selected := direction.normalized()

	# Accept left/right for a mostly horizontal axis,
	# or up/down for a mostly vertical axis.
	if absf(depth_axis.x) >= absf(depth_axis.y):
		if not (
			selected.is_equal_approx(Vector3.LEFT)
			or selected.is_equal_approx(Vector3.RIGHT)
		):
			return
	else:
		if not (
			selected.is_equal_approx(Vector3.UP)
			or selected.is_equal_approx(Vector3.DOWN)
		):
			return

	# Match the sign to the player's chosen arrow.
	if selected.dot(depth_axis) < 0.0:
		depth_axis = -depth_axis

	moving = true

	var start := vehicle.position
	var finish := start + depth_axis

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.CYAN

	var mesh := ImmediateMesh.new()
	var trail := MeshInstance3D.new()
	trail.mesh = mesh
	trail.material_override = material
	add_child(trail)
	drawn_nodes.append(trail)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(vehicle, "position", finish, 0.5)
	tween.tween_method(
		update_trail.bind(start, mesh),
		start,
		finish,
		0.5
	)
	await tween.finished

	var label := Label3D.new()
	label.text = "1"
	label.font_size = 48
	label.pixel_size = 0.005
	label.no_depth_test = true
	add_child(label)
	drawn_nodes.append(label)

	var sideways := Vector3(-depth_axis.y, depth_axis.x, 0)
	label.position = (start + finish) / 2.0 + sideways * 0.18
	label.position.z += 0.03

	stage = 5
	magnitude_input.clear()

	equations.text = (
		"Return to the origin, find magnitude c:\n"
		+ "a² + b² = c²\n"
		+ "1² + (√2)² = c²"
	)
	prompt.text = "Enter Magnitude c and select the return vector:"

	await get_tree().process_frame

	input_row.global_position = equations.global_position + Vector2(
		0,
		equations.get_combined_minimum_size().y - 12
	)

	moving = false
	magnitude_input.grab_focus()

func return_from_depth(direction: Vector3) -> void:
	if not is_equal_approx(read_magnitude(), sqrt(3.0)):
		return

	var start := vehicle.position
	var toward_origin := origin - start

	# Use the visible horizontal and vertical direction.
	# Ignore tiny offsets caused by rounding.
	var tolerance := toward_origin.length() * 0.05
	var expected := Vector3.ZERO

	if absf(toward_origin.x) > tolerance:
		expected.x = signf(toward_origin.x)

	if absf(toward_origin.y) > tolerance:
		expected.y = signf(toward_origin.y)

	if not direction.normalized().is_equal_approx(expected.normalized()):
		return

	moving = true

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.CYAN

	var mesh := ImmediateMesh.new()
	var trail := MeshInstance3D.new()
	trail.mesh = mesh
	trail.material_override = material
	add_child(trail)
	drawn_nodes.append(trail)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(vehicle, "position", origin, 0.5)
	tween.tween_method(
		update_trail.bind(start, mesh),
		start,
		origin,
		0.5
	)
	await tween.finished

	var label := Label3D.new()
	label.text = "√3"
	label.font_size = 48
	label.pixel_size = 0.005
	label.no_depth_test = true
	add_child(label)
	drawn_nodes.append(label)

	var floor_center := origin + floor_display_map * (
		(square_opposite - origin) / 2.0
	)
	position_label_outside(label, start, origin, floor_center)

	stage = 6
	equations.text = ""
	prompt.text = ""
	magnitude_input.clear()
	magnitude_input.release_focus()

	await fade_in_cube(start)
	await center_cube_on_ct(start)
	
func fade_in_cube(depth_endpoint: Vector3) -> void:
	var side_u := floor_display_map * first_direction
	var side_v := floor_display_map * (
		square_opposite - first_corner
	)
	var depth := depth_endpoint - (origin + side_u + side_v)

	var corners: Array[Vector3] = [
		origin,
		origin + side_u,
		origin + side_v,
		origin + side_u + side_v,
		origin + depth,
		origin + side_u + depth,
		origin + side_v + depth,
		origin + side_u + side_v + depth,
	]

	var center := Vector3.ZERO
	for corner in corners:
		center += corner
	center /= 8.0

	# Find the visible corner that projects onto the center.
	var visible_center := 4
	var closest := INF

	for i in range(4, 8):
		var distance := corners[i].distance_to(center)
		if distance < closest:
			closest = distance
			visible_center = i

	# Save the six outer vertices relative to the center.
	cube_outline_points.clear()
	cube_upright_angle = 0.0
	var smallest_turn := INF

	for corner in corners:
		var relative := corner - center

		if relative.length() < 0.0001:
			continue

		cube_outline_points.append(relative)

		# Find the smallest rotation that puts a vertex straight up.
		var turn := wrapf(
			-atan2(relative.y, relative.x),
			-PI,
			PI
		)

		if absf(turn) < smallest_turn:
			smallest_turn = absf(turn)
			cube_upright_angle = turn

	# Reach an upright vertex by turning clockwise.
	if cube_upright_angle > 0.0:
		cube_upright_angle -= PI / 3.0
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Six outer edges.
	for i in range(8):
		for axis in [1, 2, 4]:
			var neighbor: int = i ^ axis

			if neighbor <= i:
				continue
			if corners[i].distance_to(center) < 0.0001:
				continue
			if corners[neighbor].distance_to(center) < 0.0001:
				continue

			mesh.surface_add_vertex(corners[i] - center)
			mesh.surface_add_vertex(corners[neighbor] - center)

	# Three visible spokes; the hidden three are omitted.
	for axis in [1, 2, 4]:
		var neighbor: int = visible_center ^ axis
		mesh.surface_add_vertex(corners[visible_center] - center)
		mesh.surface_add_vertex(corners[neighbor] - center)

	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = Color(0, 1, 1, 0)

	finished_cube = MeshInstance3D.new()
	finished_cube.mesh = mesh
	finished_cube.material_override = material
	add_child(finished_cube)
	finished_cube.position = center

	if is_instance_valid(shape_caption):
		shape_caption.hide()

	var fade := create_tween()
	fade.set_parallel(true)

	fade.tween_property(
		material, "albedo_color", Color.CYAN, 1.5
	)

	# Remove the old construction, including both diagonals
	# and every numerical label.
	for node in drawn_nodes:
		if not is_instance_valid(node):
			continue

		if node is MeshInstance3D:
			var old_material := (
				node.material_override as StandardMaterial3D
			)

			if old_material != null:
				old_material.transparency = \
					BaseMaterial3D.TRANSPARENCY_ALPHA

				var transparent := old_material.albedo_color
				transparent.a = 0.0

				fade.tween_property(
					old_material,
					"albedo_color",
					transparent,
					1.5
				)

		elif node is Label3D:
			fade.tween_property(
				node, "modulate", Color(1, 1, 1, 0), 1.5
			)
			fade.tween_property(
				node, "outline_modulate", Color(0, 0, 0, 0), 1.5
			)

	await fade.finished

	for node in drawn_nodes:
		if is_instance_valid(node):
			(node as Node3D).hide()
			node.queue_free()

	drawn_nodes.clear()
	drawn_nodes.append(finished_cube)

func center_cube_on_ct(_depth_endpoint: Vector3) -> void:
	if not is_instance_valid(finished_cube):
		return

	# Shift and rotate together.
	var settle := create_tween()
	settle.set_parallel(true)
	settle.set_trans(Tween.TRANS_SINE)
	settle.set_ease(Tween.EASE_IN_OUT)

	settle.tween_property(
		finished_cube,
		"position",
		vehicle.position,
		1.0
	)
	settle.tween_property(
		finished_cube,
		"rotation:z",
		cube_upright_angle,
		1.0
	)

	await settle.finished

	# Find the bottom of the rotated outline.
	var bottom := INF

	for point in cube_outline_points:
		var rotated := point.rotated(
			Vector3.BACK,
			cube_upright_angle
		)
		bottom = minf(bottom, rotated.y + vehicle.position.y)

	if not is_instance_valid(shape_caption):
		shape_caption = Label3D.new()
		add_child(shape_caption)

	shape_caption.text = "The Unit Cube"
	shape_caption.font_size = 36
	shape_caption.pixel_size = 0.005
	shape_caption.no_depth_test = true
	shape_caption.position = Vector3(
		vehicle.position.x,
		bottom - 0.4,
		vehicle.position.z + 0.05
	)
	shape_caption.show()
	await get_tree().create_timer(2.0).timeout
	shape_caption.hide()
	await reveal_six_hexagons()

func reveal_six_hexagons() -> void:
	# Get the center hexagon's vertices in their final orientation.
	var points: Array[Vector3] = []

	for point in cube_outline_points:
		points.append(finished_cube.basis * point)

	points.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			return atan2(a.y, a.x) < atan2(b.y, b.x)
	)

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Each neighbor sits across one side of the center hexagon.
	for i in range(6):
		var neighbor_center := points[i] + points[(i + 1) % 6]

		for j in range(6):
			mesh.surface_add_vertex(
				neighbor_center + points[j]
			)
			mesh.surface_add_vertex(
				neighbor_center + points[(j + 1) % 6]
			)

	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = Color(0, 1, 1, 0)

	var neighbors := MeshInstance3D.new()
	neighbors.mesh = mesh
	neighbors.material_override = material
	add_child(neighbors)
	neighbors.position = finished_cube.position
	drawn_nodes.append(neighbors)

	var fade := create_tween()
	fade.tween_property(
		material,
		"albedo_color",
		Color.CYAN,
		1.5
	)
	await fade.finished

	await get_tree().create_timer(0.5).timeout

	# Expand the cube to the six neighboring centers.
	# The tessellation itself stays stationary.
	var expand := create_tween()
	expand.set_parallel(true)
	expand.set_trans(Tween.TRANS_SINE)
	expand.set_ease(Tween.EASE_IN_OUT)

	expand.tween_property(
		finished_cube,
		"scale",
		Vector3.ONE * sqrt(3.0),
		1.5
	)
	expand.tween_property(
		finished_cube,
		"rotation:z",
		finished_cube.rotation.z - PI / 6.0,
		1.5
	)

	await expand.finished
	await reveal_planet_glyphs()
	show_hive_ending()
	
func reveal_planet_glyphs() -> void:
	var points: Array[Vector3] = []

	for point in cube_outline_points:
		points.append(finished_cube.basis * point)

	# Clockwise ordering, starting at the top.
	points.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			var angle_a := wrapf(
				PI / 2.0 - atan2(a.y, a.x), 0.0, TAU
			)
			var angle_b := wrapf(
				PI / 2.0 - atan2(b.y, b.x), 0.0, TAU
			)
			return angle_a < angle_b
	)

	var symbols := ["♄", "♃", "♀", "☽", "☿", "♂"]

	var symbol_font := SystemFont.new()
	symbol_font.font_names = PackedStringArray(["Segoe UI Symbol"])
	symbol_font.allow_system_fallback = false
	var glyphs: Array[Label3D] = []

	var fade := create_tween()
	fade.set_parallel(true)

	for i in range(6):
		var glyph := Label3D.new()
		glyph.font = symbol_font
		glyph.text = symbols[i]
		glyph.font_size = 56
		glyph.pixel_size = 0.005
		glyph.no_depth_test = true
		glyph.modulate = Color(1, 1, 1, 0)
		glyph.outline_modulate = Color(0, 0, 0, 0)

		add_child(glyph)

		# Position just outside the corresponding cube corner.
		glyph.position = finished_cube.position + points[i]
		glyph.position += points[i].normalized() * 0.18
		glyph.position.z += 0.05

		glyphs.append(glyph)
		drawn_nodes.append(glyph)

		fade.tween_property(
			glyph, "modulate", Color.WHITE, 1.2
		)
		fade.tween_property(
			glyph, "outline_modulate", Color.BLACK, 1.2
		)

	await fade.finished

	for glyph in glyphs:
		start_glyph_bounce(glyph)


func start_glyph_bounce(glyph: Label3D) -> void:
	var resting_y := glyph.position.y

	var bounce := create_tween()
	bounce.set_loops()
	bounce.set_trans(Tween.TRANS_SINE)
	bounce.set_ease(Tween.EASE_IN_OUT)

	bounce.tween_property(
		glyph, "position:y", resting_y + 0.04, 0.8
	)
	bounce.tween_property(
		glyph, "position:y", resting_y, 0.8
	)
func show_hive_ending() -> void:
	equations.text = ""
	shape_caption.hide()
	magnitude_input.release_focus()
	magnitude_input.hide()

	input_row.show()
	input_row.global_position = initial_row_position
	prompt.text = "The Hive — TBC"

	var thanks := Label.new()
	thanks.text = "Thanks for playing. Press Enter to restart."
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thanks.add_theme_font_size_override("font_size", 20)
	$HUD.add_child(thanks)

	thanks.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	thanks.offset_left = 0
	thanks.offset_right = 0
	thanks.offset_top = -52
	thanks.offset_bottom = -20
	thanks.mouse_filter = Control.MOUSE_FILTER_IGNORE

	ending_ready = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not ending_ready:
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				get_viewport().set_input_as_handled()
				get_tree().reload_current_scene()
