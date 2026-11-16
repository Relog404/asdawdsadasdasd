extends CharacterBody3D

const MODEL_PATH := "res://dfgdrgrd.bbmodel"
const OBJ_PATH := "res://dfgdrgrd.obj"
const TEXTURE_PATH := "res://texture.png"
const PIXELS_PER_UNIT := 16.0
const MODEL_CENTER := Vector3(-2.5, 0.0, -1.0)
const WALK_SPEED := 3.6
const RUN_SPEED := 5.6
const CROUCH_SPEED := 1.35
const ACCELERATION := 18.0
const GRAVITY := 24.0

var _model_root: Node3D
var _group_nodes: Dictionary = {}
var _group_names: Dictionary = {}
var _group_origins: Dictionary = {}
var _group_rest_positions: Dictionary = {}
var _group_rest_rotations: Dictionary = {}
var _element_owners: Dictionary = {}
var _clips: Dictionary = {}
var _walk_clock := 0.0
var _crouch_time := 0.0
var _gesture_time := -1.0
var _was_z_down := false

@onready var camera_rig: Node3D = get_node_or_null("../CameraRig") as Node3D


func _ready() -> void:
	_build_character()
	_build_animation_library()


func _physics_process(delta: float) -> void:
	var crouch_held := Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL)
	var is_crouching := _crouch_time > 0.0 or crouch_held
	var crouch_length := _clip_length("prised", 1.29167)
	if crouch_held:
		_crouch_time = minf(_crouch_time + delta, crouch_length)
	else:
		_crouch_time = maxf(_crouch_time - delta, 0.0)

	var z_down := Input.is_key_pressed(KEY_Z)
	if z_down and not _was_z_down:
		_gesture_time = -1.0 if _gesture_time >= 0.0 else 0.0
	_was_z_down = z_down

	var move_input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if move_input.length_squared() > 1.0:
		move_input = move_input.normalized()

	var direction := Vector3(move_input.x, 0.0, move_input.y)
	if camera_rig != null:
		direction = direction.rotated(Vector3.UP, float(camera_rig.get("camera_yaw")))
	var moving := direction.length_squared() > 0.0001
	if moving:
		direction = direction.normalized()

	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif Input.is_key_pressed(KEY_SHIFT):
		speed = RUN_SPEED
	var target_velocity := direction * speed if moving else Vector3.ZERO
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if moving:
		var wanted_yaw := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, wanted_yaw, minf(delta * 12.0, 1.0))
	move_and_slide()

	if _gesture_time >= 0.0:
		if moving and not is_crouching:
			_gesture_time = -1.0
		else:
			_gesture_time = minf(_gesture_time + delta, _clip_length("ziga", 0.75))

	_update_pose(delta, moving and not is_crouching, is_crouching)


func _build_character() -> void:
	var model_file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if model_file == null:
		push_error("Не удалось открыть модель: " + MODEL_PATH)
		return
	var model_data: Variant = JSON.parse_string(model_file.get_as_text())
	if not model_data is Dictionary:
		push_error("Файл Blockbench не является корректным JSON.")
		return

	_model_root = Node3D.new()
	_model_root.name = "CharacterRig"
	add_child(_model_root)
	var groups_by_id: Dictionary = {}
	for group in model_data.get("groups", []):
		groups_by_id[str(group.get("uuid", ""))] = group
	var elements_by_id: Dictionary = {}
	for element in model_data.get("elements", []):
		elements_by_id[str(element.get("uuid", ""))] = element

	for root_item in model_data.get("outliner", []):
		_build_outliner_item(
			root_item, _model_root, Vector3.ZERO, true, groups_by_id, elements_by_id
		)

	var source_parts := _read_obj_parts()
	var texture := load(TEXTURE_PATH) as Texture2D
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for part in source_parts:
		var element_id := _match_element(part, model_data.get("elements", []))
		if element_id.is_empty() or not _element_owners.has(element_id):
			continue
		var element: Dictionary = elements_by_id[element_id]
		var owner_id: String = _element_owners[element_id]
		var owner_origin: Vector3 = _group_origins.get(owner_id, Vector3.ZERO)
		var mesh := _mesh_for_part(part, owner_origin)
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Block_" + element_id.left(8)
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(_group_nodes[owner_id] as Node3D).add_child(instance)


func _build_outliner_item(
	item: Variant,
	parent_node: Node3D,
	parent_origin: Vector3,
	is_root: bool,
	groups_by_id: Dictionary,
	elements_by_id: Dictionary
) -> void:
	if item is String:
		var element_id: String = item
		if elements_by_id.has(element_id):
			_element_owners[element_id] = str(parent_node.get_meta("group_uuid", ""))
		return
	if not item is Dictionary:
		return

	var item_id := str(item.get("uuid", ""))
	if groups_by_id.has(item_id):
		var group: Dictionary = groups_by_id[item_id]
		var origin := _vector_from_array(group.get("origin", [0, 0, 0]))
		var group_node := Node3D.new()
		group_node.name = str(group.get("name", "Bone"))
		group_node.set_meta("group_uuid", item_id)
		var local_origin := origin + MODEL_CENTER if is_root else origin - parent_origin
		group_node.position = local_origin / PIXELS_PER_UNIT
		var base_rotation := _vector_from_array(group.get("rotation", [0, 0, 0]))
		group_node.rotation = Vector3(
			deg_to_rad(base_rotation.x), deg_to_rad(base_rotation.y), deg_to_rad(base_rotation.z)
		)
		parent_node.add_child(group_node)
		_group_nodes[item_id] = group_node
		_group_names[str(group.get("name", ""))] = item_id
		_group_origins[item_id] = origin
		_group_rest_positions[item_id] = group_node.position
		_group_rest_rotations[item_id] = group_node.rotation
		for child in item.get("children", []):
			_build_outliner_item(child, group_node, origin, false, groups_by_id, elements_by_id)
	elif elements_by_id.has(item_id):
		_element_owners[item_id] = str(parent_node.get_meta("group_uuid", ""))
		for child in item.get("children", []):
			_build_outliner_item(
				child, parent_node, parent_origin, false, groups_by_id, elements_by_id
			)


func _read_obj_parts() -> Array:
	var result: Array = []
	var file := FileAccess.open(OBJ_PATH, FileAccess.READ)
	if file == null:
		push_error("Не удалось открыть OBJ: " + OBJ_PATH)
		return result
	var positions: Array[Vector3] = []
	var texcoords: Array[Vector2] = []
	var normals: Array[Vector3] = []
	var active: Dictionary = {}
	var active_vertex_start := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var fields := line.split(" ", false)
		if fields.is_empty():
			continue
		match fields[0]:
			"o":
				if not active.is_empty():
					_finish_obj_part(active, active_vertex_start, positions, result)
				active = {
					"name": fields[1] if fields.size() > 1 else "part",
					"vertices": [],
					"uvs": [],
					"normals": []
				}
				active_vertex_start = positions.size()
			"v":
				if fields.size() >= 4:
					positions.append(
						Vector3(fields[1].to_float(), fields[2].to_float(), fields[3].to_float())
					)
			"vt":
				if fields.size() >= 3:
					texcoords.append(Vector2(fields[1].to_float(), fields[2].to_float()))
			"vn":
				if fields.size() >= 4:
					normals.append(
						(
							Vector3(
								fields[1].to_float(), fields[2].to_float(), fields[3].to_float()
							)
							. normalized()
						)
					)
			"f":
				if active.is_empty() or fields.size() < 4:
					continue
				var face: Array[Dictionary] = []
				for field_index in range(1, fields.size()):
					var indices := fields[field_index].split("/")
					if indices.size() < 2:
						continue
					var vertex_index := int(indices[0]) - 1
					var uv_index := int(indices[1]) - 1
					var normal_index := (
						int(indices[2]) - 1
						if indices.size() > 2 and not indices[2].is_empty()
						else -1
					)
					if (
						vertex_index < 0
						or vertex_index >= positions.size()
						or uv_index < 0
						or uv_index >= texcoords.size()
					):
						continue
					var uv := texcoords[uv_index]
					var normal := (
						normals[normal_index]
						if normal_index >= 0 and normal_index < normals.size()
						else Vector3.UP
					)
					face.append(
						{
							"position": positions[vertex_index],
							"uv": Vector2(uv.x, 1.0 - uv.y),
							"normal": normal
						}
					)
					if face.size() >= 3:
						for triangle_index in range(1, face.size() - 1):
							for corner in [face[0], face[triangle_index], face[triangle_index + 1]]:
								active["vertices"].append(corner["position"])
								active["uvs"].append(corner["uv"])
								active["normals"].append(corner["normal"])
	if not active.is_empty():
		_finish_obj_part(active, active_vertex_start, positions, result)
	return result


func _finish_obj_part(
	part: Dictionary, vertex_start: int, source_positions: Array[Vector3], result: Array
) -> void:
	var bounds: Array[Vector3] = []
	for index in range(vertex_start, source_positions.size()):
		bounds.append(source_positions[index])
	if bounds.is_empty():
		return
	var minimum := bounds[0]
	var maximum := bounds[0]
	for point in bounds:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	part["minimum"] = minimum
	part["maximum"] = maximum
	result.append(part)


func _match_element(part: Dictionary, elements: Array) -> String:
	var part_min: Vector3 = part["minimum"]
	var part_max: Vector3 = part["maximum"]
	for element in elements:
		var expected_min := _vector_from_array(element.get("from", [0, 0, 0])) / PIXELS_PER_UNIT
		var expected_max := _vector_from_array(element.get("to", [0, 0, 0])) / PIXELS_PER_UNIT
		if (
			part_min.distance_to(expected_min) < 0.002
			and part_max.distance_to(expected_max) < 0.002
		):
			return str(element.get("uuid", ""))
	return ""


func _mesh_for_part(part: Dictionary, owner_origin: Vector3) -> ArrayMesh:
	var vertices: Array = part.get("vertices", [])
	if vertices.is_empty():
		return null
	var local_vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var mesh_normals := PackedVector3Array()
	for index in range(vertices.size()):
		local_vertices.append(vertices[index] - owner_origin / PIXELS_PER_UNIT)
		uvs.append(part["uvs"][index])
		mesh_normals.append(part["normals"][index])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = local_vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_animation_library() -> void:
	var file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	var groups_by_id: Dictionary = {}
	for group in data.get("groups", []):
		groups_by_id[str(group.get("uuid", ""))] = group
	for clip_data in data.get("animations", []):
		var clip_name := str(clip_data.get("name", ""))
		var clip := {"length": float(clip_data.get("length", 1.0)), "tracks": {}}
		for group_id in clip_data.get("animators", {}).keys():
			if not groups_by_id.has(group_id):
				continue
			var group_name: String = str(groups_by_id[group_id].get("name", ""))
			var tracks := {"rotation": [], "position": []}
			for keyframe in clip_data["animators"][group_id].get("keyframes", []):
				var channel := str(keyframe.get("channel", ""))
				if not tracks.has(channel):
					continue
				var data_points: Array = keyframe.get("data_points", [])
				if data_points.is_empty():
					continue
				var point: Dictionary = data_points[0]
				var value := Vector3(
					str(point.get("x", "0")).strip_edges().to_float(),
					str(point.get("y", "0")).strip_edges().to_float(),
					str(point.get("z", "0")).strip_edges().to_float()
				)
				tracks[channel].append({"time": float(keyframe.get("time", 0.0)), "value": value})
			for channel_name in tracks.keys():
				tracks[channel_name].sort_custom(
					func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"]
				)
			clip["tracks"][group_name] = tracks
		_clips[clip_name] = clip


func _update_pose(delta: float, walking: bool, crouching: bool) -> void:
	if _model_root == null:
		return
	if crouching and _crouch_time > 0.0:
		_apply_clip("prised", _crouch_time)
		_model_root.position.y = 0.0
	elif _gesture_time >= 0.0:
		_apply_clip("ziga", _gesture_time)
		_model_root.position.y = 0.0
	elif walking:
		_walk_clock += delta
		var walk_length := _clip_length("walking", 0.75)
		_apply_clip("walking", fposmod(_walk_clock, walk_length))
		_apply_walking_legs(_walk_clock)
		_model_root.position.y = absf(sin(_walk_clock * TAU / walk_length)) * 0.035
	else:
		_apply_rest_pose()
		_model_root.position.y = 0.0


func _apply_clip(clip_name: String, time: float) -> void:
	_apply_rest_pose()
	if not _clips.has(clip_name):
		return
	var clip: Dictionary = _clips[clip_name]
	for group_name in clip["tracks"].keys():
		if not _group_names.has(group_name):
			continue
		var group_id: String = _group_names[group_name]
		var node: Node3D = _group_nodes[group_id]
		var tracks: Dictionary = clip["tracks"][group_name]
		if not tracks["position"].is_empty():
			var position_offset: Vector3 = _sample_track(tracks["position"], time) / PIXELS_PER_UNIT
			node.position = _group_rest_positions[group_id] + position_offset
		if not tracks["rotation"].is_empty():
			var rotation_offset: Vector3 = _sample_track(tracks["rotation"], time)
			var rest_rotation: Vector3 = _group_rest_rotations[group_id]
			node.rotation = (
				rest_rotation
				+ Vector3(
					deg_to_rad(rotation_offset.x),
					deg_to_rad(rotation_offset.y),
					deg_to_rad(rotation_offset.z)
				)
			)


func _sample_track(keys: Array, time: float) -> Vector3:
	if keys.size() == 1 or time <= float(keys[0]["time"]):
		return keys[0]["value"]
	if time >= float(keys[keys.size() - 1]["time"]):
		return keys[keys.size() - 1]["value"]
	for index in range(keys.size() - 1):
		var first: Dictionary = keys[index]
		var second: Dictionary = keys[index + 1]
		if time >= float(first["time"]) and time <= float(second["time"]):
			var span := float(second["time"]) - float(first["time"])
			var weight := 0.0 if span <= 0.0 else (time - float(first["time"])) / span
			return first["value"].lerp(second["value"], weight)
	return keys[keys.size() - 1]["value"]


func _apply_rest_pose() -> void:
	for group_id in _group_nodes.keys():
		var node: Node3D = _group_nodes[group_id]
		node.position = _group_rest_positions[group_id]
		node.rotation = _group_rest_rotations[group_id]


func _apply_walking_legs(clock: float) -> void:
	var phase := clock * TAU / _clip_length("walking", 0.75)
	var swing := sin(phase) * deg_to_rad(24.0)
	_set_bone_x_rotation("foot1", swing)
	_set_bone_x_rotation("foot2", -swing)
	_set_bone_x_rotation("koleno3", maxf(0.0, -swing) * 0.8)
	_set_bone_x_rotation("koleno4", maxf(0.0, swing) * 0.8)


func _set_bone_x_rotation(group_name: String, value: float) -> void:
	if not _group_names.has(group_name):
		return
	var group_id: String = _group_names[group_name]
	var node: Node3D = _group_nodes[group_id]
	node.rotation.x = _group_rest_rotations[group_id].x + value


func _clip_length(clip_name: String, fallback: float) -> float:
	return float(_clips[clip_name].get("length", fallback)) if _clips.has(clip_name) else fallback


func _vector_from_array(value: Array) -> Vector3:
	if value.size() < 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
