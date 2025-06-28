package raiden

import "core:fmt"

DrawCommand :: struct {
	primitive_type: PrimitiveType,
	instance:       Instance,
}

DrawBatch :: [dynamic]DrawCommand

draw_cube :: proc(
	renderer: ^Renderer,
	position: Vec3,
	rotation: Mat3 = Mat3(1),
	scale: f32 = 1,
	color := Color{255, 255, 255, 255},
) {
	command := DrawCommand {
		primitive_type = .CUBE,
		instance       = instance_from_position_rotation(position, rotation, scale, color),
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
