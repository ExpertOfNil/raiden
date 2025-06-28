package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "raiden"
import "vendor:glfw"
import "vendor:sdl3"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"
import "vendor:wgpu/sdl3glue"

Engine :: struct {
	renderer:    raiden.Renderer,
	window:      ^sdl3.Window,
	window_size: [2]u32,
	camera:      raiden.Camera,
}

engine_init_sdl3 :: proc(engine: ^Engine) -> bool {
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("Failed to initialize SDL3")
		return false
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	engine.window_size.x = 1920
	engine.window_size.y = 1080
	engine.window = sdl3.CreateWindow(
		"Raiden",
		i32(engine.window_size.x),
		i32(engine.window_size.y),
		{.RESIZABLE},
	)

	if engine.window == nil {
		fmt.eprintln("Failed to create window")
		sdl3.Quit()
		return false
	}

	if !raiden.init_wgpu_sdl3(&engine.renderer, engine.window, engine.window_size) {
		fmt.eprintln("Failed to initialize WGPU")
		glfw.Terminate()
		return false
	}
	if !raiden.init_render_pipeline(&engine.renderer) {
		fmt.eprintln("Failed to initialize render pipeline")
		glfw.Terminate()
		return false
	}
	if !raiden.init_buffers(&engine.renderer) {
		fmt.eprintln("Failed to initialize buffers")
		glfw.Terminate()
		return false
	}

	init_matrices(engine)

	return true
}

handle_window_resize :: proc(engine: ^Engine, width, height: i32) {
	engine.window_size.x = u32(width)
	engine.window_size.y = u32(height)
	engine.renderer.surface_config.width = engine.window_size.x
	engine.renderer.surface_config.height = engine.window_size.y
	wgpu.SurfaceConfigure(engine.renderer.surface, &engine.renderer.surface_config)
	raiden.init_depth_texture(&engine.renderer, engine.window_size)
	update_matrices(engine)
}

init_matrices :: proc(engine: ^Engine) {
	using engine.camera
	aspect := f32(engine.window_size.x) / f32(engine.window_size.y)
	fmt.println("Aspect: ", aspect)

	proj_matrix.data = linalg.matrix4_perspective_f32(
		math.to_radians_f32(60.0),
		aspect,
		0.1,
		100.0,
	)
	view_matrix.data = raiden.Mat4(1)
	uniforms := raiden.Uniforms {
		view_proj = proj_matrix.data * view_matrix.data,
	}
	wgpu.QueueWriteBuffer(
		engine.renderer.queue,
		engine.renderer.uniform_buffer,
		0,
		&uniforms,
		size_of(raiden.Uniforms),
	)
}

update_matrices :: proc(engine: ^Engine) {
	using engine.camera
	uniforms := raiden.Uniforms {
		view_proj = proj_matrix.data * view_matrix.data,
	}
	wgpu.QueueWriteBuffer(
		engine.renderer.queue,
		engine.renderer.uniform_buffer,
		0,
		&uniforms,
		size_of(raiden.Uniforms),
	)
}

cleanup :: proc(engine: ^Engine) {
	raiden.renderer_cleanup(&engine.renderer)

	if engine.window != nil do sdl3.DestroyWindow(engine.window)
	glfw.Terminate()
}

MouseState :: struct {
	is_rotating:    bool,
	is_translating: bool,
	angle_pitch:    f32,
	angle_yaw:      f32,
	pos:            [2]f32,
	rotation:       quaternion128,
}

main :: proc() {
	engine := Engine{}

	if !engine_init_sdl3(&engine) {
		fmt.eprintln("Failed to initialize engine")
		os.exit(1)
	}
	defer cleanup(&engine)

	mouse_state := MouseState{}
	mouse_state.rotation = quaternion128(1)

	running := true
	for running {
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .WINDOW_RESIZED:
				window_event := cast(^sdl3.WindowEvent)&event
				if sdl3.GetWindowFromID(window_event.windowID) == engine.window {
					handle_window_resize(&engine, window_event.data1, window_event.data2)
				}
			case .MOUSE_WHEEL:
				wheel_event := cast(^sdl3.MouseWheelEvent)&event
				focal_distance := raiden.camera_get_focal_distance(&engine.camera)
				focal_distance += wheel_event.y * 0.2
				focal_distance = 0.001 if focal_distance <= 0.001 else focal_distance
				raiden.camera_set_focal_distance(&engine.camera, focal_distance)
				update_matrices(&engine)
			case .MOUSE_BUTTON_DOWN:
				mouse_event := cast(^sdl3.MouseButtonEvent)&event
				if mouse_event.button == sdl3.BUTTON_LEFT {
					mouse_state.is_rotating = true
					mouse_state.pos.x = mouse_event.x
					mouse_state.pos.y = mouse_event.y
				}
				if mouse_event.button == sdl3.BUTTON_RIGHT {
					mouse_state.is_translating = true
					mouse_state.pos.x = mouse_event.x
					mouse_state.pos.y = mouse_event.y
				}
			case .MOUSE_BUTTON_UP:
				mouse_event := cast(^sdl3.MouseButtonEvent)&event
				if mouse_event.button == sdl3.BUTTON_LEFT {
					mouse_state.is_rotating = false
				}
				if mouse_event.button == sdl3.BUTTON_RIGHT {
					mouse_state.is_translating = false
				}
			case .MOUSE_MOTION:
				mouse_event := cast(^sdl3.MouseMotionEvent)&event
				if mouse_state.is_rotating {
					delta_x := mouse_event.x - mouse_state.pos.x
					mouse_state.angle_yaw += f32(delta_x) * 0.01
					delta_y := mouse_event.y - mouse_state.pos.y
					mouse_state.angle_pitch += f32(delta_y) * 0.01

					delta_pitch := linalg.quaternion_angle_axis_f32(f32(delta_y) * 0.01, {1, 0, 0})
					delta_yaw := linalg.quaternion_angle_axis_f32(f32(delta_x) * 0.01, {0, 1, 0})

					mouse_state.rotation = linalg.quaternion_mul_quaternion(
						delta_yaw,
						mouse_state.rotation,
					)
					mouse_state.rotation = linalg.quaternion_mul_quaternion(
						delta_pitch,
						mouse_state.rotation,
					)
					mouse_state.rotation = linalg.quaternion_normalize(mouse_state.rotation)

					rot := linalg.matrix4_from_quaternion_f32(mouse_state.rotation)
					for &cmd in engine.renderer.commands {
						pos := linalg.matrix4_translate_f32(
							{
								cmd.instance.model_matrix[0, 3],
								cmd.instance.model_matrix[1, 3],
								cmd.instance.model_matrix[2, 3],
							},
						)
						cmd.instance.model_matrix = pos * rot
						fmt.println("Model Matrix: ", cmd.instance.model_matrix)
					}
					update_matrices(&engine)
				}
				if mouse_state.is_translating {
					delta_x := mouse_event.x - mouse_state.pos.x
					delta_y := mouse_event.y - mouse_state.pos.y
					pos := raiden.camera_get_position(&engine.camera)
					pos.x += delta_x * 0.01
					pos.y -= delta_y * 0.01
					raiden.camera_set_position(&engine.camera, pos)
					update_matrices(&engine)
				}
				mouse_state.pos.x = mouse_event.x
				mouse_state.pos.y = mouse_event.y

			}
		}
		raiden.draw_cube(&engine.renderer, {255, 0, 255, 255}, {2, 2, -10})
		raiden.draw_cube(&engine.renderer, {255, 255, 255, 255}, {-2, -2, -10})
		raiden.draw_cube(&engine.renderer, {255, 0, 0, 255}, {2, 0, -10})
		raiden.draw_cube(&engine.renderer, {0, 255, 0, 255}, {0, 2, -10})
		raiden.render(&engine.renderer)
	}
}
