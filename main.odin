package main

import "core:fmt"
import "core:os"
import "raiden"

main :: proc() {
	engine := raiden.Engine{}

	if !raiden.engine_init_sdl3(&engine) {
		fmt.eprintln("Failed to initialize engine")
		os.exit(1)
	}
	defer raiden.cleanup(&engine)

	mouse_state := raiden.MouseState {
		button_left   = false,
		button_right  = false,
		button_middle = false,
	}

	// Make a cube to visualize the camera target location
	target := raiden.instance_from_position_rotation(raiden.Vec3(0), raiden.Mat3(1), scale = 0.2)

	running := true
	for running {
		running = raiden.handle_sdl3_events(&engine, &mouse_state)
		raiden.instance_set_position(&target, engine.camera.target)
		raiden.draw_cube_from_instance(&engine.renderer, target)

		// Draw cubes aligned with axes
		raiden.draw_cube(
			&engine.renderer,
			position = {4, 0, 0},
			scale = 0.1,
			color = {255, 0, 0, 255},
		)
		raiden.draw_cube(
			&engine.renderer,
			position = {0, 4, 0},
			scale = 0.1,
			color = {0, 255, 0, 255},
		)
		raiden.draw_cube(
			&engine.renderer,
			position = {0, 0, 4},
			scale = 0.1,
			color = {0, 0, 255, 255},
		)

		// Draw tetrahedrons aligned with axes
		raiden.draw_tetrahedron(
			&engine.renderer,
			position = {6, 0, 0},
			scale = 0.2,
			color = {255, 0, 0, 255},
		)
		raiden.draw_tetrahedron(
			&engine.renderer,
			position = {0, 6, 0},
			scale = 0.2,
			color = {0, 255, 0, 255},
		)
		raiden.draw_tetrahedron(
			&engine.renderer,
			position = {0, 0, 6},
			scale = 0.2,
			color = {0, 0, 255, 255},
		)
		raiden.render(&engine.renderer)
	}
}
