package raiden

import "core:math"
import "core:math/linalg"

Camera :: struct {
	view_matrix:  struct #raw_union {
		data:   Mat4,
		fields: struct {
			xi, xj, xk, xw: f32,
			yi, yj, yk, yw: f32,
			zi, zj, zk, zw: f32,
			ti, tj, tk, tw: f32,
		},
	},
	proj_matrix:  struct #raw_union {
		data:   Mat4,
		fields: struct {
			aspect_focal:   f32,
			_pad0:          [4]f32,
			focal_distance: f32,
			_pad1:          [4]f32,
			depth_ratio:    f32,
			_pad3:          [4]f32,
			depth_offset:   f32,
		},
	},
}

camera_get_rotation :: proc(cam: ^Camera) -> Mat3 {
	return Mat3(cam.view_matrix.data)
}
camera_set_rotation :: proc(cam: ^Camera, rot: Mat3) {
	cam.view_matrix.data[0, 0] = rot[0,0]
	cam.view_matrix.data[1, 0] = rot[1,0]
	cam.view_matrix.data[2, 0] = rot[2,0]
	cam.view_matrix.data[0, 1] = rot[0,1]
	cam.view_matrix.data[1, 1] = rot[1,1]
	cam.view_matrix.data[2, 1] = rot[2,1]
	cam.view_matrix.data[0, 2] = rot[0,2]
	cam.view_matrix.data[1, 2] = rot[1,2]
	cam.view_matrix.data[2, 2] = rot[2,2]
}
camera_get_position :: proc(cam: ^Camera) -> Vec3 {
    using cam.view_matrix.fields
	return Vec3{ti, tj, tk}
}
camera_set_position :: proc(cam: ^Camera, pos: Vec3) {
	using cam.view_matrix.fields
	ti = pos.x
	tj = pos.y
	tk = pos.z
}
camera_get_focal_distance :: proc(cam: ^Camera) -> f32 {
	using cam.proj_matrix
	return fields.focal_distance
}
camera_set_focal_distance :: proc(cam: ^Camera, dist: f32) {
	using cam.proj_matrix
	fields.aspect_focal = (fields.aspect_focal / fields.focal_distance) * dist
	fields.focal_distance = dist
}

/*
PanOrbitCamera :: struct {
	target:          Vec3,
	distance:        f32,
	angle_yaw:       f32,
	angle_pitch:     f32,
	distance_min:    f32,
	distance_max:    f32,
	angle_pitch_min: f32,
	angle_pitch_max: f32,
	mouse_speed:     f32,
	zoom_speed:      f32,
	pan_speed:       f32,
}

init_pan_orbit_camera :: proc(target: Vec3, distance: f32) -> PanOrbitCamera {
	pi_2 :: math.PI / 2
	return PanOrbitCamera {
		target = target,
		distance = distance,
		angle_yaw = pi_2 / 2,
		angle_pitch = pi_2 / 2,
		distance_min = 1.0,
		distance_max = 100.0,
		angle_pitch_min = -pi_2 + 0.01,
		angle_pitch_max = pi_2 - 0.01,
		mouse_speed = 0.005,
		zoom_speed = 2.0,
		pan_speed = 0.001,
	}
}

update_pan_orbit_camera :: proc(camera: ^PanOrbitCamera) -> rl.Camera {
	dt := rl.GetFrameTime()

	mouse_delta := rl.GetMouseDelta()
	// Mouse orbit controls
	if rl.IsMouseButtonDown(.RIGHT) {
		camera.angle_yaw -= mouse_delta.x * camera.mouse_speed
		camera.angle_pitch += mouse_delta.y * camera.mouse_speed
		camera.angle_pitch = math.clamp(
			camera.angle_pitch,
			camera.angle_pitch_min,
			camera.angle_pitch_max,
		)
	}

	// Mouse zoom controls
	mouse_scroll := rl.GetMouseWheelMove()
	if mouse_scroll != 0 {
		camera.distance -= mouse_scroll * camera.zoom_speed
		camera.distance = math.clamp(camera.distance, camera.distance_min, camera.distance_max)
	}

	cos_y := math.cos(camera.angle_pitch)
	sin_y := math.sin(camera.angle_pitch)
	cos_x := math.cos(camera.angle_yaw)
	sin_x := math.sin(camera.angle_yaw)
	// Mouse pan controls
	if rl.IsMouseButtonDown(.MIDDLE) {
		right := rl.Vector3{-sin_x, cos_x, 0}
		forward := rl.Vector3{cos_y * cos_x, cos_y * sin_x, sin_y}
		up := rl.Vector3 {
			forward.y * right.z - forward.z * right.y,
			forward.z * right.x - forward.x * right.z,
			forward.x * right.y - forward.y * right.x,
		}

		pan_distance := camera.distance * camera.pan_speed
		camera.target.x -= (right.x * mouse_delta.x - up.x * mouse_delta.y) * pan_distance
		camera.target.y -= (right.y * mouse_delta.x - up.y * mouse_delta.y) * pan_distance
		camera.target.z -= (right.z * mouse_delta.x - up.z * mouse_delta.y) * pan_distance
	}

	position := rl.Vector3 {
		camera.target.x + camera.distance * cos_y * cos_x,
		camera.target.y + camera.distance * cos_y * sin_x,
		camera.target.z + camera.distance * sin_y,
	}

	return rl.Camera {
		position = position,
		target = camera.target,
		up = {0.0, 0.0, 1.0},
		projection = .PERSPECTIVE,
		fovy = 60.0,
	}
}*/
