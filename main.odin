package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "raiden"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

WindowSystemGlfw :: struct {
	window: glfw.WindowHandle,
	width:  u32,
	height: u32,
}

Camera :: struct {
	view_matrix:  raiden.Mat4,
	proj_matrix:  raiden.Mat4,
	model_matrix: raiden.Mat4,
}

Engine :: struct {
	renderer:    raiden.Renderer,
	window:      glfw.WindowHandle,
	window_size: [2]u32,
	camera:      Camera,
}

engine_init :: proc(engine: ^Engine) -> bool {
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		return false
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	engine.window_size.x = 1280
	engine.window_size.y = 720
	engine.window = glfw.CreateWindow(
		i32(engine.window_size.x),
		i32(engine.window_size.y),
		"Raiden",
		nil,
		nil,
	)

	if engine.window == nil {
		fmt.eprintln("Failed to create window")
		glfw.Terminate()
		return false
	}

	glfw.SetWindowUserPointer(engine.window, engine)
	glfw.SetFramebufferSizeCallback(engine.window, framebuffer_size_callback)

	if !raiden.init_wgpu_glfw(&engine.renderer, engine.window, engine.window_size) {
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

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = {}
	engine := cast(^Engine)glfw.GetWindowUserPointer(window)
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

	if engine.window != nil do glfw.DestroyWindow(engine.window)
	glfw.Terminate()
}

mouse_move_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	context = {}
	state := cast(^MouseState)glfw.GetWindowUserPointer(window)
	if state.rotating {
		delta := xpos - state.pos.x
		state.angle += f32(delta) * 0.01
	}
	state.pos.x = xpos
	state.pos.y = ypos
}

mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	context = {}
	state := cast(^MouseState)glfw.GetWindowUserPointer(window)
	if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
		state.rotating = true
		state.pos.x, state.pos.y = glfw.GetCursorPos(window)
	} else {
		state.rotating = false
	}
}

MouseState :: struct {
	rotating: bool,
	angle:    f32,
	pos:      [2]f64,
}

main :: proc() {
	engine := Engine{}

	if !engine_init(&engine) {
		fmt.eprintln("Failed to initialize engine")
		os.exit(1)
	}
	defer cleanup(&engine)

	mouse_state := MouseState{}
	glfw.SetWindowUserPointer(engine.window, &mouse_state)
	glfw.SetCursorPosCallback(engine.window, mouse_move_callback)
	glfw.SetMouseButtonCallback(engine.window, mouse_button_callback)
	glfw.SetInputMode(engine.window, glfw.STICKY_MOUSE_BUTTONS, 1)
	for !glfw.WindowShouldClose(engine.window) {
		glfw.PollEvents()
		if mouse_state.rotating {
			rot := linalg.matrix4_rotate_f32(mouse_state.angle, {0, 1, 0})
			pos := linalg.matrix4_translate_f32({0, 0, -10})
			engine.camera.model_matrix = pos * rot
			update_matrices(&engine)
		}
		raiden.render(&engine.renderer)
	}
}
