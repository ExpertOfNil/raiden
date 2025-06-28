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
		instance       = instance_from_position_rotation(pos, rot, color),
	}
	append(&renderer.commands, command)
	// TODO (mmckenna) : Check instance buffer capacity
}

draw_cube_from_instance :: proc(renderer: ^Renderer, instance: Instance) {
	command := DrawCommand {
		primitive_type = .CUBE,
		instance       = instance,
	}
	append(&renderer.commands, command)
	// TODO (mmckenna) : Check instance buffer capacity
}
