package raiden

import "vendor:wgpu"
import "core:fmt"
import "vendor:glfw"
import "vendor:wgpu/glfwglue"
import "vendor:sdl3"
import "vendor:wgpu/sdl3glue"

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
	index_buffer:    wgpu.Buffer,
	uniform_buffer:  wgpu.Buffer,
	bind_group:      wgpu.BindGroup,
	depth_texture:   wgpu.Texture,
	depth_view:      wgpu.TextureView,
}

WgpuCallbackContext :: struct {
	adapter:   ^wgpu.Adapter,
	device:    ^wgpu.Device,
	completed: bool,
	success:   bool,
}

Uniforms :: struct {
	view_proj: Mat4,
}

Vertex :: struct {
	position: Vec3,
	color:    Vec3,
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

init_wgpu_sdl3 :: proc(
	renderer: ^Renderer,
	window: ^sdl3.Window,
	window_size: [2]u32,
) -> bool {
	instance := wgpu.CreateInstance(nil)
	if instance == nil {
		fmt.eprintln("Failed to create WGPU instance")
		return false
	}

	renderer.surface = sdl3glue.GetSurface(instance, window)
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

	if !init_depth_texture(renderer, window_size) {
		fmt.eprintln("Failed to create depth texture")
		return false
	}

	return true
}

init_wgpu_glfw :: proc(
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

	if !init_depth_texture(renderer, window_size) {
		fmt.eprintln("Failed to create depth texture")
		return false
	}

	return true
}

init_render_pipeline :: proc(renderer: ^Renderer) -> bool {
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
		depthStencil = &wgpu.DepthStencilState {
			format = wgpu.TextureFormat.Depth24Plus,
			depthWriteEnabled = wgpu.OptionalBool.True,
			depthCompare = wgpu.CompareFunction.Less,
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

init_buffers :: proc(renderer: ^Renderer) -> bool {
	// Create vertex buffer
	vertices_size := uint(len(CUBE_VERTICES) * size_of(Vertex))
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
		raw_data(CUBE_VERTICES),
		vertices_size,
	)

	// Create index buffer
	indices_size := uint(len(CUBE_INDICES) * size_of(u16))
	index_buffer_desc := wgpu.BufferDescriptor {
		label            = "Index Buffer",
		size             = u64(indices_size),
		usage            = wgpu.BufferUsageFlags{wgpu.BufferUsage.Index, wgpu.BufferUsage.CopyDst},
		mappedAtCreation = false,
	}
	renderer.index_buffer = wgpu.DeviceCreateBuffer(renderer.device, &index_buffer_desc)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.index_buffer,
		0,
		raw_data(CUBE_INDICES),
		indices_size,
	)

	// Create uniform buffer
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

	// Create bind groups
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

init_depth_texture :: proc(renderer: ^Renderer, window_size: [2]u32) -> bool {
	if renderer.depth_view != nil {
		wgpu.TextureViewRelease(renderer.depth_view)
	}
	if renderer.depth_texture != nil {
		wgpu.TextureRelease(renderer.depth_texture)
	}

	depth_texture_desc := wgpu.TextureDescriptor {
		label = "Depth Texture",
		size = {width = window_size.x, height = window_size.y, depthOrArrayLayers = 1},
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = wgpu.TextureDimension._2D,
		format = wgpu.TextureFormat.Depth24Plus,
		usage = wgpu.TextureUsageFlags{.RenderAttachment},
	}
	renderer.depth_texture = wgpu.DeviceCreateTexture(renderer.device, &depth_texture_desc)
	if renderer.depth_texture == nil {
		fmt.eprintln("Failed to crate depth texture")
		return false
	}

	depth_view_desc := wgpu.TextureViewDescriptor {
		label           = "Depth View",
		format          = wgpu.TextureFormat.Depth24Plus,
		dimension       = wgpu.TextureViewDimension._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
	}
	renderer.depth_view = wgpu.TextureCreateView(renderer.depth_texture, &depth_view_desc)
	if renderer.depth_view == nil {
		fmt.eprintln("Failed to crate depth view")
		return false
	}

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
		label                  = "Render Pass",
		colorAttachmentCount   = 1,
		colorAttachments       = &wgpu.RenderPassColorAttachment {
			view = view,
			loadOp = .Clear,
			storeOp = .Store,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			clearValue = {0.1, 0.1, 0.1, 1.0},
		},
		depthStencilAttachment = &wgpu.RenderPassDepthStencilAttachment {
			view = renderer.depth_view,
			depthLoadOp = .Clear,
			depthStoreOp = .Store,
			depthClearValue = 1.0,
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
		u64(len(CUBE_VERTICES) * size_of(Vertex)),
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		render_pass,
		renderer.index_buffer,
		wgpu.IndexFormat.Uint16,
		0,
		u64(len(CUBE_INDICES) * size_of(u16)),
	)

	wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(len(CUBE_INDICES)), 1, 0, 0, 0)
	//wgpu.RenderPassEncoderDraw(render_pass, u32(len(vertices)), 1, 0, 0)
	wgpu.RenderPassEncoderEnd(render_pass)

	command_buffer_desc := wgpu.CommandBufferDescriptor {
		label = "Command Buffer",
	}
	command_buffer := wgpu.CommandEncoderFinish(command_encoder, &command_buffer_desc)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, {command_buffer})
	wgpu.SurfacePresent(renderer.surface)
}
