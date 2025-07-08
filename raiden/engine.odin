package raiden

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "vendor:sdl3"
import "vendor:wgpu"

Engine :: struct {
	renderer:    Renderer,
	window:      ^sdl3.Window,
	window_size: [2]u32,
	camera:      PanOrbitCamera,
}

engine_init_offscreen :: proc(engine: ^Engine, window_size: [2]u32) -> bool {
	engine.window = nil
	engine.window_size = window_size
    engine.renderer.offscreen = true
	if !init_wgpu_offscreen(&engine.renderer, engine.window_size) {
		log.error("Failed to initialize WGPU")
		sdl3.Quit()
		return false
	}
	if !init_render_pipeline(&engine.renderer) {
		log.error("Failed to initialize render pipeline")
		sdl3.Quit()
		return false
	}
	if !init_outline_pipeline(&engine.renderer) {
		fmt.eprintln("Failed to initialize render pipeline")
		sdl3.Quit()
		return false
	}
	if !init_buffers(&engine.renderer) {
		log.error("Failed to initialize buffers")
		sdl3.Quit()
		return false
	}

	init_matrices(engine)

	pan_orbit_camera_init(&engine.camera, Vec3(0), 10)
	update_uniforms(engine)
	return true
}

engine_init_sdl3 :: proc(engine: ^Engine, window_size: [2]u32) -> bool {
	if !sdl3.Init({.VIDEO}) {
		log.error("Failed to initialize SDL3")
		return false
	}

	engine.window_size = window_size
	engine.window = sdl3.CreateWindow(
		"Raiden",
		i32(engine.window_size.x),
		i32(engine.window_size.y),
		{.RESIZABLE},
	)

	if engine.window == nil {
		log.error("Failed to create window")
		sdl3.Quit()
		return false
	}

	if !init_wgpu_sdl3(&engine.renderer, engine.window, engine.window_size) {
		log.error("Failed to initialize WGPU")
		sdl3.Quit()
		return false
	}
	if !init_render_pipeline(&engine.renderer) {
		log.error("Failed to initialize render pipeline")
		sdl3.Quit()
		return false
	}
	if !init_outline_pipeline(&engine.renderer) {
		fmt.eprintln("Failed to initialize render pipeline")
		sdl3.Quit()
		return false
	}
	if !init_buffers(&engine.renderer) {
		log.error("Failed to initialize buffers")
		sdl3.Quit()
		return false
	}

	init_matrices(engine)

	pan_orbit_camera_init(&engine.camera, Vec3(0), 10)
	update_uniforms(engine)
	return true
}

handle_window_resize :: proc(engine: ^Engine, width, height: i32) {
	engine.window_size.x = u32(width)
	engine.window_size.y = u32(height)
	engine.renderer.surface_config.width = engine.window_size.x
	engine.renderer.surface_config.height = engine.window_size.y
	wgpu.SurfaceConfigure(engine.renderer.surface, &engine.renderer.surface_config)
	init_depth_texture(&engine.renderer, engine.window_size)

	// Update projection matrix
	aspect := f32(engine.window_size.x) / f32(engine.window_size.y)
	engine.camera.proj_matrix.data = linalg.matrix4_perspective_f32(
		fovy = math.to_radians_f32(60.0),
		aspect = aspect,
		near = 0.1,
		far = 1000.0,
	)
	update_uniforms(engine)
}

init_matrices :: proc(engine: ^Engine) {
	using engine.camera
	aspect := f32(engine.window_size.x) / f32(engine.window_size.y)
	log.debug("Aspect: ", aspect)

	proj_matrix.data = linalg.matrix4_perspective_f32(
		math.to_radians_f32(60.0),
		aspect,
		0.1,
		1000.0,
	)
	view_matrix.data = Mat4(1)
	uniforms := Uniforms {
		view_proj = proj_matrix.data * view_matrix.data,
	}
	wgpu.QueueWriteBuffer(
		engine.renderer.queue,
		engine.renderer.uniform_buffer,
		0,
		&uniforms,
		size_of(Uniforms),
	)
}

update_uniforms :: proc(engine: ^Engine) {
	using engine.camera
	uniforms := Uniforms {
		view_proj = proj_matrix.data * view_matrix.data,
	}
	wgpu.QueueWriteBuffer(
		engine.renderer.queue,
		engine.renderer.uniform_buffer,
		0,
		&uniforms,
		size_of(Uniforms),
	)
}

cleanup :: proc(engine: ^Engine) {
	renderer_cleanup(&engine.renderer)

	if engine.window != nil do sdl3.DestroyWindow(engine.window)
	sdl3.Quit()
}

MouseState :: struct {
	button_left:   bool,
	button_right:  bool,
	button_middle: bool,
	position:      [2]f32,
}

handle_sdl3_events :: proc(engine: ^Engine, mouse_state: ^MouseState) -> bool {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			return false
		case .WINDOW_RESIZED:
			window_event := cast(^sdl3.WindowEvent)&event
			if sdl3.GetWindowFromID(window_event.windowID) == engine.window {
				handle_window_resize(engine, window_event.data1, window_event.data2)
			}
		case .WINDOW_PIXEL_SIZE_CHANGED:
			window_event := cast(^sdl3.WindowEvent)&event
			if sdl3.GetWindowFromID(window_event.windowID) == engine.window {
				handle_window_resize(engine, window_event.data1, window_event.data2)
			}
		case .MOUSE_WHEEL:
			wheel_event := cast(^sdl3.MouseWheelEvent)&event
			pan_orbit_camera_zoom(&engine.camera, wheel_event.y)
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
				pan_orbit_camera_orbit(&engine.camera, delta)
			} else if mouse_state.button_right {
				pan_orbit_camera_pan(&engine.camera, delta)
			} else if mouse_state.button_middle {
				// Nothing currently
			}
			mouse_state.position.x = mouse_event.x
			mouse_state.position.y = mouse_event.y
		}
	}
	update_uniforms(engine)
	return true
}

engine_render :: proc(engine: ^Engine) {
    if engine.renderer.offscreen {
        render_offscreen(&engine.renderer, engine.window_size)
    } else {
        render(&engine.renderer)
    }
}
