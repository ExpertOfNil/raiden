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
	model_matrix:  struct #raw_union {
		data:   Mat4,
		fields: struct {
			xi, xj, xk, xw: f32,
			yi, yj, yk, yw: f32,
			zi, zj, zk, zw: f32,
			ti, tj, tk, tw: f32,
		},
	},
}

camera_get_rotation :: proc(cam: ^Camera) -> Mat3 {
	return Mat3(cam.view_matrix.data)
}
camera_set_rotation :: proc(cam: ^Camera, rot: Mat3) {
	(cast(^Mat3)&cam.view_matrix.fields.xi)^ = rot
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
