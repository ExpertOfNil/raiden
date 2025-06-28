package raiden

import "core:fmt"
import "core:math"
import "core:math/linalg"

Camera :: struct {
	view_matrix: struct #raw_union {
		data:   Mat4,
		fields: struct {
			xi, xj, xk, xw: f32,
			yi, yj, yk, yw: f32,
			zi, zj, zk, zw: f32,
			ti, tj, tk, tw: f32,
		},
	},
	proj_matrix: struct #raw_union {
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
	cam.view_matrix.data[0, 0] = rot[0, 0]
	cam.view_matrix.data[1, 0] = rot[1, 0]
	cam.view_matrix.data[2, 0] = rot[2, 0]
	cam.view_matrix.data[0, 1] = rot[0, 1]
	cam.view_matrix.data[1, 1] = rot[1, 1]
	cam.view_matrix.data[2, 1] = rot[2, 1]
	cam.view_matrix.data[0, 2] = rot[0, 2]
	cam.view_matrix.data[1, 2] = rot[1, 2]
	cam.view_matrix.data[2, 2] = rot[2, 2]
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

PanOrbitCamera :: struct {
	using camera:    Camera,
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

pan_orbit_camera_init :: proc(camera: ^PanOrbitCamera, target: Vec3, distance: f32) {
	pi_2 :: math.PI / 2
	camera.target = target
	camera.distance = distance
	camera.angle_yaw = pi_2 / 2
	camera.angle_pitch = pi_2 / 2
	camera.distance_min = 1.0
	camera.distance_max = 100.0
	camera.angle_pitch_min = -pi_2 + 0.01
	camera.angle_pitch_max = pi_2 - 0.01
	camera.mouse_speed = 0.005
	camera.zoom_speed = 0.5
	camera.pan_speed = 0.001
    pan_orbit_camera_update(camera)
}

pan_orbit_camera_orbit :: proc(camera: ^PanOrbitCamera, mouse_delta: [2]f32) {
	camera.angle_yaw -= mouse_delta.x * camera.mouse_speed
	camera.angle_pitch += mouse_delta.y * camera.mouse_speed
	pan_orbit_camera_update(camera)
}

pan_orbit_camera_zoom :: proc(camera: ^PanOrbitCamera, mouse_scroll: f32) {
	if mouse_scroll == 0 do return
	camera.distance -= mouse_scroll * camera.zoom_speed
	pan_orbit_camera_update(camera)
}

pan_orbit_camera_pan :: proc(camera: ^PanOrbitCamera, mouse_delta: [2]f32) {
	cos_y := math.cos(camera.angle_pitch)
	sin_y := math.sin(camera.angle_pitch)
	cos_x := math.cos(camera.angle_yaw)
	sin_x := math.sin(camera.angle_yaw)

	rt := linalg.normalize(Vec3{-sin_x, cos_x, 0})
	fw := linalg.normalize(Vec3{cos_y * cos_x, cos_y * sin_x, sin_y})
	up := linalg.normalize(linalg.cross(fw, rt))
	pan_distance := camera.distance * camera.pan_speed
	camera.target.x -= (rt.x * mouse_delta.x - up.x * mouse_delta.y) * pan_distance
	camera.target.y -= (rt.y * mouse_delta.x - up.y * mouse_delta.y) * pan_distance
	camera.target.z -= (rt.z * mouse_delta.x - up.z * mouse_delta.y) * pan_distance
	pan_orbit_camera_update(camera)
}

pan_orbit_camera_update :: proc(camera: ^PanOrbitCamera) {
	camera.distance = math.clamp(camera.distance, camera.distance_min, camera.distance_max)
	camera.angle_pitch = math.clamp(
		camera.angle_pitch,
		camera.angle_pitch_min,
		camera.angle_pitch_max,
	)

	cos_y := math.cos(camera.angle_pitch)
	sin_y := math.sin(camera.angle_pitch)
	cos_x := math.cos(camera.angle_yaw)
	sin_x := math.sin(camera.angle_yaw)

	position :=
		camera.target +
		Vec3 {
				cos_y * cos_x * camera.distance,
				cos_y * sin_x * camera.distance,
				sin_y * camera.distance,
			}

	camera.view_matrix.data = camera_look_at(position, camera.target, {0, 0, 1})
}

camera_look_at :: proc(position: Vec3, target: Vec3, up: Vec3) -> Mat4 {
	vz := linalg.normalize(position - target)
	vx := linalg.normalize(linalg.cross(up, vz))
	vy := linalg.normalize(linalg.cross(vz, vx))

    // odinfmt: disable
    return Mat4 {
        vx.x, vx.y, vx.z, -linalg.dot(vx, position),
        vy.x, vy.y, vy.z, -linalg.dot(vy, position),
        vz.x, vz.y, vz.z, -linalg.dot(vz, position),
        0, 0, 0, 1,
    }
    // odinfmt: enable
}
