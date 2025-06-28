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
	camera:      raiden.PanOrbitCamera,
}

engine_init_sdl3 :: proc(engine: ^Engine) -> bool {
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("Failed to initialize SDL3")
		return false
	}

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

	raiden.pan_orbit_camera_init(&engine.camera, raiden.Vec3(0), 10)
	update_uniforms(engine)
	return true
}

handle_window_resize :: proc(engine: ^Engine, width, height: i32) {
	engine.window_size.x = u32(width)
	engine.window_size.y = u32(height)
	engine.renderer.surface_config.width = engine.window_size.x
	engine.renderer.surface_config.height = engine.window_size.y
	wgpu.SurfaceConfigure(engine.renderer.surface, &engine.renderer.surface_config)
	raiden.init_depth_texture(&engine.renderer, engine.window_size)
	update_uniforms(engine)
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

update_uniforms :: proc(engine: ^Engine) {
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
	button_left:   bool,
	button_right:  bool,
	button_middle: bool,
	position:      [2]f32,
}

main :: proc() {
	engine := Engine{}

	if !engine_init_sdl3(&engine) {
		fmt.eprintln("Failed to initialize engine")
		os.exit(1)
	}
	defer cleanup(&engine)

	mouse_state := MouseState {
		button_left   = false,
		button_right  = false,
		button_middle = false,
	}

	// Make a cube to visualize the camera target location
	target := raiden.instance_from_position_rotation(raiden.Vec3(0), raiden.Mat3(1), scale = 0.2)

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
				raiden.pan_orbit_camera_zoom(&engine.camera, wheel_event.y)
			case .MOUSE_BUTTON_DOWN:
				mouse_event := cast(^sdl3.MouseButtonEvent)&event
				if mouse_event.button == sdl3.BUTTON_LEFT {
					mouse_state.button_left = true
				} else if mouse_event.button == sdl3.BUTTON_RIGHT {
					mouse_state.button_right = true
				} else if mouse_event.button == sdl3.BUTTON_MIDDLE {
					mouse_state.button_middle = true
				}
				mouse_state.position.x = mouse_event.x
				mouse_state.position.y = mouse_event.y
			case .MOUSE_BUTTON_UP:
				mouse_event := cast(^sdl3.MouseButtonEvent)&event
				if mouse_event.button == sdl3.BUTTON_LEFT {
					mouse_state.button_left = false
				} else if mouse_event.button == sdl3.BUTTON_RIGHT {
					mouse_state.button_right = false
				} else if mouse_event.button == sdl3.BUTTON_MIDDLE {
					mouse_state.button_middle = false
				}
				mouse_state.position.x = mouse_event.x
				mouse_state.position.y = mouse_event.y
			case .MOUSE_MOTION:
				mouse_event := cast(^sdl3.MouseMotionEvent)&event
				delta := [2]f32 {
					mouse_event.x - mouse_state.position.x,
					mouse_event.y - mouse_state.position.y,
				}
				if mouse_state.button_left {
					raiden.pan_orbit_camera_orbit(&engine.camera, delta)
				} else if mouse_state.button_right {
					raiden.pan_orbit_camera_pan(&engine.camera, delta)
				} else if mouse_state.button_middle {
					// Nothing currently
				}
				mouse_state.position.x = mouse_event.x
				mouse_state.position.y = mouse_event.y
			}
		}
		update_uniforms(&engine)
		raiden.instance_set_position(&target, engine.camera.target)
		raiden.draw_cube_from_instance(&engine.renderer, target)
		raiden.draw_cube(&engine.renderer, position = {2, 0, 0}, color = {255, 0, 0, 255})
		raiden.draw_cube(&engine.renderer, position = {0, 2, 0}, color = {0, 255, 0, 255})
		raiden.draw_cube(&engine.renderer, position = {0, 0, 2}, color = {0, 0, 255, 255})
		raiden.render(&engine.renderer)
	}
}
