package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

// Shader source
vert_shader_source :: #load("vert_shader.wgsl", string)
frag_shader_source :: #load("frag_shader.wgsl", string)

Vec3 :: [3]f32
Vec4 :: [4]f32
Mat3 :: distinct matrix[3, 3]f32
Mat4 :: distinct matrix[4, 4]f32

Renderer :: struct {
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	surface:         wgpu.Surface,
	surface_config:  wgpu.SurfaceConfiguration,
	render_pipeline: wgpu.RenderPipeline,
	vertex_buffer:   wgpu.Buffer,
	uniform_buffer:  wgpu.Buffer,
	bind_group:      wgpu.BindGroup,
}

WindowSystemGlfw :: struct {
	window: glfw.WindowHandle,
	width:  u32,
	height: u32,
}

Camera :: struct {
	view_matrix: Mat4,
	proj_matrix: Mat4,
}

Vertex :: struct {
	position: Vec3,
	color:    Vec3,
}

Uniforms :: struct {
	view_proj: Mat4,
}

vertices := []Vertex {
	{{1.0, 1.0, -10.0}, {1.0, 0.0, 0.0}},
	{{-1.0, 1.0, -10.0}, {0.0, 0.0, 1.0}},
	{{-1.0, -1.0, -10.0}, {0.0, 0.0, 1.0}},
	{{1.0, 1.0, -10.0}, {1.0, 0.0, 0.0}},
	{{-1.0, -1.0, -10.0}, {0.0, 0.0, 1.0}},
	{{1.0, -1.0, -10.0}, {1.0, 0.0, 0.0}},
}

WgpuCallbackContext :: struct {
	adapter:   ^wgpu.Adapter,
	device:    ^wgpu.Device,
	completed: bool,
	success:   bool,
}

Engine :: struct {
	renderer:    Renderer,
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

	if !engine_init_wgpu(&engine.renderer, engine.window, engine.window_size) {
		fmt.eprintln("Failed to initialize WGPU")
		glfw.Terminate()
		return false
	}
	if !engine_init_render_pipeline(&engine.renderer) {
		fmt.eprintln("Failed to initialize render pipeline")
		glfw.Terminate()
		return false
	}
	if !engine_init_buffers(&engine.renderer) {
		fmt.eprintln("Failed to initialize buffers")
		glfw.Terminate()
		return false
	}

	update_matrices(engine)

	return true
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	engine := cast(^Engine)glfw.GetWindowUserPointer(window)
	engine.window_size.x = u32(width)
	engine.window_size.y = u32(height)
	engine.renderer.surface_config.width = engine.window_size.x
	engine.renderer.surface_config.height = engine.window_size.y
	wgpu.SurfaceConfigure(engine.renderer.surface, &engine.renderer.surface_config)
	context = {}
	update_matrices(engine)
}

engine_init_wgpu :: proc(
	renderer: ^Renderer,
	window: glfw.WindowHandle,
	window_size: [2]u32,
) -> bool {
	instance := wgpu.CreateInstance(nil)
	if instance == nil {
		fmt.eprintln("Failed to create WGPU instance")
		return false
	}

	renderer.surface = glfwglue.GetSurface(instance, window)
	if renderer.surface == nil {
		fmt.eprintln("Failed to create surface")
		return false
	}
	fmt.println("Surface created:", renderer.surface != nil)

	adapter_options := wgpu.RequestAdapterOptions {
		compatibleSurface = renderer.surface,
		powerPreference   = wgpu.PowerPreference.HighPerformance,
	}
	wgpu_ctx := WgpuCallbackContext {
		adapter = &renderer.adapter,
		device  = &renderer.device,
	}
	adapter_callback := wgpu.RequestAdapterCallbackInfo {
		callback  = adapter_request_callback,
		userdata1 = &wgpu_ctx,
	}
	wgpu.InstanceRequestAdapter(instance, &adapter_options, adapter_callback)
	for !wgpu_ctx.completed {
		wgpu.InstanceProcessEvents(instance)
	}

	if !wgpu_ctx.success {
		fmt.eprintln("Failed to get adapter")
		return false
	}
	fmt.println("Adapter created:", renderer.adapter != nil)

	surface_caps, status := wgpu.SurfaceGetCapabilities(renderer.surface, renderer.adapter)
	if status != .Success {
		fmt.eprintln("Failed to get surface capabilities")
		return false
	}

	if surface_caps.formatCount == 0 {
		fmt.eprintln("No supported surface formats")
		return false
	}
	fmt.println("Surface format count:", surface_caps.formatCount)

	// Reset completion status for device
	wgpu_ctx.completed = false
	wgpu_ctx.success = false
	device_desc := wgpu.DeviceDescriptor {
		label = "Device",
	}

	device_callback := wgpu.RequestDeviceCallbackInfo {
		callback  = device_request_callback,
		userdata1 = &wgpu_ctx,
	}
	wgpu.AdapterRequestDevice(renderer.adapter, &device_desc, device_callback)

	for !wgpu_ctx.completed {
		wgpu.InstanceProcessEvents(instance)
	}

	if !wgpu_ctx.completed {
		fmt.eprintln("Failed to get device")
		return false
	}
	fmt.println("Device created:", renderer.device != nil)
	renderer.queue = wgpu.DeviceGetQueue(renderer.device)

	renderer.surface_config = wgpu.SurfaceConfiguration {
		usage       = wgpu.TextureUsageFlags{wgpu.TextureUsage.RenderAttachment},
		format      = surface_caps.formats[0],
		width       = window_size.x,
		height      = window_size.y,
		presentMode = wgpu.PresentMode.Fifo,
		device      = renderer.device,
	}
	wgpu.SurfaceConfigure(renderer.surface, &renderer.surface_config)

	return true
}

adapter_request_callback :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	ctx := cast(^WgpuCallbackContext)userdata1
	ctx.completed = true
	if status == wgpu.RequestAdapterStatus.Success {
		ctx.adapter^ = adapter
		ctx.success = true
	} else {
		context = {}
		fmt.eprintln(
			"Adapter request failed: %s",
			message if len(message) != 0 else "Unknown Error",
		)
		ctx.success = false
	}
}

device_request_callback :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	ctx := cast(^WgpuCallbackContext)userdata1
	ctx.completed = true
	if status == wgpu.RequestDeviceStatus.Success {
		ctx.device^ = device
		ctx.success = true
	} else {
		context = {}
		fmt.eprintln(
			"Device request failed: %s",
			message if len(message) != 0 else "Unknown Error",
		)
		ctx.success = false
	}
}

update_matrices :: proc(engine: ^Engine) {
	aspect := f32(engine.window_size.x) / f32(engine.window_size.y)

	engine.camera.proj_matrix = linalg.matrix4_perspective_f32(
		math.to_radians_f32(45.0),
		aspect,
		0.1,
		100.0,
	)
	fmt.println("Proj Matrix: %v", engine.camera.proj_matrix)
	engine.camera.view_matrix = Mat4(1)
	fmt.println("View Matrix: %v", engine.camera.view_matrix)

	uniforms := Uniforms {
		view_proj = engine.camera.proj_matrix * engine.camera.view_matrix,
	}
	fmt.println("View-Proj Matrix: %v", uniforms.view_proj)
	wgpu.QueueWriteBuffer(
		engine.renderer.queue,
		engine.renderer.uniform_buffer,
		0,
		&uniforms,
		size_of(Uniforms),
	)
}

engine_init_render_pipeline :: proc(renderer: ^Renderer) -> bool {
	vert_shader_desc := wgpu.ShaderModuleDescriptor {
		label       = "Vertex Shader",
		nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = vert_shader_source},
	}
	vert_shader := wgpu.DeviceCreateShaderModule(renderer.device, &vert_shader_desc)
	if vert_shader == nil {
		fmt.eprintln("Failed to create vertex shader")
		return false
	}

	frag_shader_desc := wgpu.ShaderModuleDescriptor {
		label       = "Fragment Shader",
		nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = frag_shader_source},
	}
	frag_shader := wgpu.DeviceCreateShaderModule(renderer.device, &frag_shader_desc)
	if frag_shader == nil {
		fmt.eprintln("Failed to create fragment shader")
		return false
	}

	bind_group_layout_entry := wgpu.BindGroupLayoutEntry {
		binding = 0,
		visibility = wgpu.ShaderStageFlags{wgpu.ShaderStage.Vertex},
		buffer = {
			type = wgpu.BufferBindingType.Uniform,
			hasDynamicOffset = false,
			minBindingSize = size_of(Uniforms),
		},
	}

	bind_group_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Bind Group Layout",
		entryCount = 1,
		entries    = &bind_group_layout_entry,
	}

	bind_group_layout := wgpu.DeviceCreateBindGroupLayout(renderer.device, &bind_group_layout_desc)

	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &bind_group_layout,
	}

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(renderer.device, &pipeline_layout_desc)

	vertex_attributes := []wgpu.VertexAttribute {
		{format = wgpu.VertexFormat.Float32x3, offset = 0, shaderLocation = 0},
		{format = wgpu.VertexFormat.Float32x3, offset = size_of([3]f32), shaderLocation = 1},
	}

	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Vertex),
		stepMode       = wgpu.VertexStepMode.Vertex,
		attributeCount = len(vertex_attributes),
		attributes     = raw_data(vertex_attributes),
	}

	pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Render Pipeline",
		layout = pipeline_layout,
		vertex = {
			module = vert_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		fragment = &wgpu.FragmentState {
			module = frag_shader,
			entryPoint = "fs_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = renderer.surface_config.format,
				blend = &wgpu.BlendState {
					color = {
						operation = wgpu.BlendOperation.Add,
						srcFactor = wgpu.BlendFactor.SrcAlpha,
						dstFactor = wgpu.BlendFactor.OneMinusSrcAlpha,
					},
					alpha = {
						operation = wgpu.BlendOperation.Add,
						srcFactor = wgpu.BlendFactor.One,
						dstFactor = wgpu.BlendFactor.Zero,
					},
				},
				writeMask = wgpu.ColorWriteMaskFlags_All,
			},
		},
		primitive = {
			topology = wgpu.PrimitiveTopology.TriangleList,
			stripIndexFormat = wgpu.IndexFormat.Undefined,
			frontFace = wgpu.FrontFace.CCW,
			cullMode = wgpu.CullMode.Back,
		},
		multisample = {count = 1, mask = ~cast(u32)0, alphaToCoverageEnabled = false},
	}

	renderer.render_pipeline = wgpu.DeviceCreateRenderPipeline(renderer.device, &pipeline_desc)
	if renderer.render_pipeline == nil {
		fmt.eprintln("Failed to create render pipeline")
		return false
	}
	fmt.println("Render pipeline created")
	return true
}

engine_init_buffers :: proc(renderer: ^Renderer) -> bool {
	vertices_size := uint(len(vertices) * size_of(Vertex))
	vertex_buffer_desc := wgpu.BufferDescriptor {
		label            = "Vertex Buffer",
		size             = u64(vertices_size),
		usage            = wgpu.BufferUsageFlags {
			wgpu.BufferUsage.Vertex,
			wgpu.BufferUsage.CopyDst,
		},
		mappedAtCreation = false,
	}
	renderer.vertex_buffer = wgpu.DeviceCreateBuffer(renderer.device, &vertex_buffer_desc)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.vertex_buffer,
		0,
		raw_data(vertices),
		vertices_size,
	)

	uniform_buffer_desc := wgpu.BufferDescriptor {
		label            = "Uniform Buffer",
		size             = size_of(Uniforms),
		usage            = wgpu.BufferUsageFlags {
			wgpu.BufferUsage.Uniform,
			wgpu.BufferUsage.CopyDst,
		},
		mappedAtCreation = false,
	}
	renderer.uniform_buffer = wgpu.DeviceCreateBuffer(renderer.device, &uniform_buffer_desc)

	bind_group_entry := wgpu.BindGroupEntry {
		binding = 0,
		buffer  = renderer.uniform_buffer,
		offset  = 0,
		size    = size_of(Uniforms),
	}

	bind_group_desc := wgpu.BindGroupDescriptor {
		label      = "Bind Group",
		layout     = wgpu.RenderPipelineGetBindGroupLayout(renderer.render_pipeline, 0),
		entryCount = 1,
		entries    = &bind_group_entry,
	}
	renderer.bind_group = wgpu.DeviceCreateBindGroup(renderer.device, &bind_group_desc)

	return true
}

render :: proc(renderer: ^Renderer) {
	surface_texture := wgpu.SurfaceGetCurrentTexture(renderer.surface)
	if surface_texture.status != wgpu.SurfaceGetCurrentTextureStatus.SuccessOptimal {
		fmt.println("Surface texture status:", surface_texture.status)
		return
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	view_desc := wgpu.TextureViewDescriptor {
		label           = "Surface View",
		format          = renderer.surface_config.format,
		dimension       = wgpu.TextureViewDimension._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
	}
	view := wgpu.TextureCreateView(surface_texture.texture, &view_desc)
	if view == nil {
		fmt.eprintln("Failed to create texture view")
	}
	defer wgpu.TextureViewRelease(view)

	command_encoder_desc := wgpu.CommandEncoderDescriptor {
		label = "Command Encoder",
	}
	command_encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &command_encoder_desc)
	defer wgpu.CommandEncoderRelease(command_encoder)

	render_pass_desc := wgpu.RenderPassDescriptor {
		label                = "Render Pass",
		colorAttachmentCount = 1,
		colorAttachments     = &wgpu.RenderPassColorAttachment {
			view = view,
			loadOp = .Clear,
			storeOp = .Store,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			clearValue = {0.1, 0.1, 0.1, 1.0},
		},
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(command_encoder, &render_pass_desc)

	wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.render_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, renderer.bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		renderer.vertex_buffer,
		0,
		u64(len(vertices) * size_of(Vertex)),
	)
	wgpu.RenderPassEncoderDraw(render_pass, u32(len(vertices)), 1, 0, 0)
	wgpu.RenderPassEncoderEnd(render_pass)

	command_buffer_desc := wgpu.CommandBufferDescriptor {
		label = "Command Buffer",
	}
	command_buffer := wgpu.CommandEncoderFinish(command_encoder, &command_buffer_desc)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, {command_buffer})
	wgpu.SurfacePresent(renderer.surface)
}

cleanup :: proc(engine: ^Engine) {
	if engine.renderer.vertex_buffer != nil do wgpu.BufferDestroy(engine.renderer.vertex_buffer)
	if engine.renderer.uniform_buffer != nil do wgpu.BufferDestroy(engine.renderer.uniform_buffer)
	if engine.renderer.render_pipeline != nil do wgpu.RenderPipelineRelease(engine.renderer.render_pipeline)
	if engine.renderer.device != nil do wgpu.DeviceRelease(engine.renderer.device)
	if engine.renderer.adapter != nil do wgpu.AdapterRelease(engine.renderer.adapter)
	if engine.renderer.surface != nil do wgpu.SurfaceRelease(engine.renderer.surface)

	if engine.window != nil do glfw.DestroyWindow(engine.window)
	glfw.Terminate()
}

main :: proc() {
	engine := Engine{}

	if !engine_init(&engine) {
		fmt.eprintln("Failed to initialize engine")
		os.exit(1)
	}
	defer cleanup(&engine)

	for !glfw.WindowShouldClose(engine.window) {
		glfw.PollEvents()
		render(&engine.renderer)
	}
}
