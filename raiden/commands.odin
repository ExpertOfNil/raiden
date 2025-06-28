package raiden

import "core:fmt"

DrawCommand :: struct {
	primitive_type: PrimitiveType,
	instance:       Instance,
}

DrawBatch :: [dynamic]DrawCommand

draw_cube :: proc(renderer: ^Renderer, color: Color, pos: Vec3, rot: Mat3 = Mat3(1)) {
	command := DrawCommand {
		primitive_type = .CUBE,
		instance = Instance{model_matrix = Mat4(1), color = Vec4(1)},
	}
	command.instance.model_matrix[0, 0] = rot[0,0]
	command.instance.model_matrix[1, 0] = rot[1,0]
	command.instance.model_matrix[2, 0] = rot[2,0]
	command.instance.model_matrix[0, 1] = rot[0,1]
	command.instance.model_matrix[1, 1] = rot[1,1]
	command.instance.model_matrix[2, 1] = rot[2,1]
	command.instance.model_matrix[0, 2] = rot[0,2]
	command.instance.model_matrix[1, 2] = rot[1,2]
	command.instance.model_matrix[2, 2] = rot[2,2]
	command.instance.model_matrix[0, 3] = pos.x
	command.instance.model_matrix[1, 3] = pos.y
	command.instance.model_matrix[2, 3] = pos.z
	command.instance.color = [4]f32 {
		f32(color.r) / 255,
		f32(color.g) / 255,
		f32(color.b) / 255,
		f32(color.a) / 255,
	}
	append(&renderer.commands, command)
    // Check instance buffer capacity
}
