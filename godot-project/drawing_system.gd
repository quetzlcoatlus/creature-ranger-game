extends Node2D

signal loop_completed(creature: Node2D)
signal line_broke
signal player_damaged(amount: int)

const MAX_LINE_LENGTH := 1200.0

@onready var capture_line: Line2D = $CaptureLine
@onready var line_break_effect: CPUParticles2D = $LineBreakEffect

var points: PackedVector2Array = []
var line_length := 0.0
var is_drawing := false

# Set by CaptureScene._ready() after the scene tree is built
var creature_layer: Node2D


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drawing(get_global_mouse_position())
		else:
			_clear_line()


func _process(_delta: float) -> void:
	if not is_drawing or points.is_empty():
		return

	var mouse_pos := get_global_mouse_position()
	var last := points[-1]
	var segment_len := last.distance_to(mouse_pos)

	if segment_len < 2.0:
		return

	if line_length + segment_len > MAX_LINE_LENGTH:
		_break_line()
		return

	# Check if the new segment crosses any earlier segment in the line.
	# Skip the last 2 recorded segments to avoid false positives near the cursor.
	for i in range(0, points.size() - 3):
		var intersection: Variant = Geometry2D.segment_intersects_segment(
			last, mouse_pos, points[i], points[i + 1]
		)
		if intersection != null:
			_close_loop_at(intersection, i)
			return

	if creature_layer:
		for creature in creature_layer.get_children():
			if not is_instance_valid(creature):
				continue
			if _segment_hits_area(last, mouse_pos, creature.get_node("CaptureHitbox")):
				_break_line()
				return
			var dmg_hitbox: Area2D = creature.get_node("DamageHitbox")
			if dmg_hitbox.monitoring and _segment_hits_area(last, mouse_pos, dmg_hitbox):
				emit_signal("player_damaged", creature.damage_amount)
				_break_line()
				return

	points.append(mouse_pos)
	line_length += segment_len
	capture_line.points = points


func _start_drawing(pos: Vector2) -> void:
	points = PackedVector2Array([pos])
	line_length = 0.0
	is_drawing = true
	capture_line.points = points


# Called when the current segment crosses an earlier segment at [intersection],
# which lies on the segment between points[segment_index] and points[segment_index+1].
# Closes the loop formed by points[0..segment_index] + intersection, tests enclosure,
# then restarts drawing fresh from the intersection point.
func _close_loop_at(intersection: Vector2, segment_index: int) -> void:
	var loop_polygon := PackedVector2Array()
	for i in range(segment_index + 1):
		loop_polygon.append(points[i])
	loop_polygon.append(intersection)

	_test_enclosure(loop_polygon)

	# Trim to the loop polygon — discard the tail, restart length tracking from the crossing point
	points = loop_polygon
	line_length = 0.0
	capture_line.points = points


func _test_enclosure(polygon: PackedVector2Array) -> void:
	if not creature_layer or polygon.size() < 3:
		return
	for creature in creature_layer.get_children():
		if not is_instance_valid(creature):
			continue
		if Geometry2D.is_point_in_polygon(creature.global_position, polygon):
			emit_signal("loop_completed", creature)


func _break_line() -> void:
	if line_break_effect:
		line_break_effect.global_position = points[-1] if not points.is_empty() else Vector2.ZERO
		line_break_effect.restart()
	_clear_line()
	emit_signal("line_broke")


func _clear_line() -> void:
	points = PackedVector2Array()
	line_length = 0.0
	is_drawing = false
	capture_line.clear_points()


# Returns true if the segment (seg_start → seg_end) intersects the Area2D's CollisionShape2D.
# Supports CircleShape2D and RectangleShape2D.
func _segment_hits_area(seg_start: Vector2, seg_end: Vector2, area: Area2D) -> bool:
	var shape_node: CollisionShape2D = area.get_node_or_null("CollisionShape2D")
	if not shape_node or not shape_node.shape:
		return false

	var shape := shape_node.shape

	if shape is CircleShape2D:
		var center := shape_node.global_transform.origin
		var closest := Geometry2D.get_closest_point_to_segment(center, seg_start, seg_end)
		return closest.distance_to(center) <= (shape as CircleShape2D).radius

	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size / 2.0
		var t := shape_node.global_transform
		var corners := [
			t * Vector2(-half.x, -half.y),
			t * Vector2( half.x, -half.y),
			t * Vector2( half.x,  half.y),
			t * Vector2(-half.x,  half.y),
		]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(seg_start, seg_end, corners[i], corners[(i + 1) % 4]) != null:
				return true
		return false

	return false
