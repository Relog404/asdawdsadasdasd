extends Node3D

@export var target_path: NodePath
@export var mouse_sensitivity := 0.003
@export var follow_smoothing := 12.0

var camera_yaw := 0.0
var camera_pitch := 0.24
var distance := 6.2
var _target: Node3D
var _camera: Camera3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		push_error("CameraRig ожидает дочернюю Camera3D.")
		return
	_update_camera(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - 0.45, 3.0, 10.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + 0.45, 3.0, 10.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * mouse_sensitivity
		camera_pitch = clampf(camera_pitch + event.relative.y * mouse_sensitivity, -0.03, 0.88)


func _process(delta: float) -> void:
	_update_camera(minf(delta * follow_smoothing, 1.0))


func _update_camera(weight: float) -> void:
	if _target == null or _camera == null:
		return
	var focus := _target.global_position + Vector3(0.0, 1.0, 0.0)
	var elevation := camera_pitch
	var offset := (
		Vector3(
			sinf(camera_yaw) * cosf(elevation), sinf(elevation), cosf(camera_yaw) * cosf(elevation)
		)
		* distance
	)
	var desired_position := focus + offset
	global_position = global_position.lerp(desired_position, weight)
	_camera.look_at(focus, Vector3.UP)
