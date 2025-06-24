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

Camera :: struct {
	view_matrix:  raiden.Mat4,
	proj_matrix:  raiden.Mat4,
	model_matrix: raiden.Mat4,
}

Engine :: struct {
	renderer:    raiden.Renderer,
	window:      ^sdl3.Window,
	window_size: [2]u32,
	camera:      Camera,
}

engine_init_sdl3 :: proc(engine: ^Engine) -> bool {
	if !sdl3.Init({.VIDEO}) {
		fmt.eprintln("Failed to initialize SDL3")
		return false
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	engine.window_size.x = 1280
	engine.window_size.y = 720
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
	aspect := f32(engine.window_size.x) / f32(engine.window_size.y)

	engine.camera.proj_matrix = linalg.matrix4_perspective_f32(
		math.to_radians_f32(45.0),
		aspect,
		0.1,
		100.0,
	)
	engine.camera.view_matrix = raiden.Mat4(1)
    // odinfmt: disable
	engine.camera.model_matrix = raiden.Mat4 {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, -10,
        0, 0, 0, 1,
    }
    // odinfmt: enable
	camera := &engine.camera
	uniforms := raiden.Uniforms {
		view_proj = camera.proj_matrix * camera.view_matrix * camera.model_matrix,
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
	camera := &engine.camera
	uniforms := raiden.Uniforms {
		view_proj = camera.proj_matrix * camera.view_matrix * camera.model_matrix,
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
	if engine.renderer.vertex_buffer != nil do wgpu.BufferDestroy(engine.renderer.vertex_buffer)
	if engine.renderer.index_buffer != nil do wgpu.BufferDestroy(engine.renderer.index_buffer)
	if engine.renderer.uniform_buffer != nil do wgpu.BufferDestroy(engine.renderer.uniform_buffer)
	if engine.renderer.render_pipeline != nil do wgpu.RenderPipelineRelease(engine.renderer.render_pipeline)
	if engine.renderer.depth_view != nil do wgpu.TextureViewRelease(engine.renderer.depth_view)
	if engine.renderer.depth_texture != nil do wgpu.TextureRelease(engine.renderer.depth_texture)
	if engine.renderer.device != nil do wgpu.DeviceRelease(engine.renderer.device)
	if engine.renderer.adapter != nil do wgpu.AdapterRelease(engine.renderer.adapter)
	if engine.renderer.surface != nil do wgpu.SurfaceRelease(engine.renderer.surface)

	if engine.window != nil do sdl3.DestroyWindow(engine.window)
	glfw.Terminate()
}

MouseState :: struct {
	is_rotating: bool,
	angle_pitch: f32,
	angle_yaw:   f32,
	pos:         [2]f32,
	rotation:    quaternion128,
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
			case .MOUSE_BUTTON_DOWN:
				mouse_event := cast(^sdl3.MouseButtonEvent)&event
				if mouse_event.button == sdl3.BUTTON_LEFT {
					mouse_state.is_rotating = true
					mouse_state.pos.x = mouse_event.x
					mouse_state.pos.y = mouse_event.y
				}
			case .MOUSE_BUTTON_UP:
				mouse_event := cast(^sdl3.MouseButtonEvent)&event
				if mouse_event.button == sdl3.BUTTON_LEFT {
					mouse_state.is_rotating = false
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
					pos := linalg.matrix4_translate_f32({0, 0, -10})
					engine.camera.model_matrix = pos * rot
					update_matrices(&engine)
				}
				mouse_state.pos.x = mouse_event.x
				mouse_state.pos.y = mouse_event.y

			}
		}
		raiden.render(&engine.renderer)
	}
}
