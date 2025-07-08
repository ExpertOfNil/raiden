package raiden

import "core:bytes"
import "core:fmt"
import "core:image"
import "core:image/bmp"
import "core:log"
import "core:math/linalg"
import "core:os"
import "core:time"
import "vendor:glfw"
import "vendor:sdl3"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"
import "vendor:wgpu/sdl3glue"

// Shader source
vert_shader_source :: #load("vert_shader.wgsl", string)
frag_shader_source :: #load("frag_shader.wgsl", string)

Vec2u :: [2]u32
Vec2f :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat3 :: distinct matrix[3, 3]f32
Mat4 :: distinct matrix[4, 4]f32
Color :: [4]u32

Renderer :: struct {
	adapter:           wgpu.Adapter,
	device:            wgpu.Device,
	queue:             wgpu.Queue,
	surface:           wgpu.Surface,
	surface_config:    wgpu.SurfaceConfiguration,
	render_pipeline:   wgpu.RenderPipeline,
	outline_pipeline:  wgpu.RenderPipeline,
	uniform_buffer:    wgpu.Buffer,
	bind_group:        wgpu.BindGroup,
	offscreen_texture: wgpu.Texture,
	offscreen_view:    wgpu.TextureView,
	depth_texture:     wgpu.Texture,
	depth_view:        wgpu.TextureView,
	commands:          DrawBatch,
	meshes:            map[MeshType]Mesh,
	offscreen:         bool,
}

OffscreenRenderer :: struct {
	device:           wgpu.Device,
	queue:            wgpu.Queue,
	render_pipeline:  wgpu.RenderPipeline,
	outline_pipeline: wgpu.RenderPipeline,
	uniform_buffer:   wgpu.Buffer,
	bind_group:       wgpu.BindGroup,
	texture:          wgpu.Texture,
	view:             wgpu.TextureView,
	depth_texture:    wgpu.Texture,
	depth_view:       wgpu.TextureView,
	commands:         DrawBatch,
	meshes:           map[MeshType]Mesh,
}

WgpuCallbackContext :: struct {
	adapter:   ^wgpu.Adapter,
	device:    ^wgpu.Device,
	completed: bool,
	success:   bool,
}

WgpuBufferMapContext :: struct {
	status:    wgpu.MapAsyncStatus,
	completed: bool,
	message:   string,
}

Uniforms :: struct {
	view_proj: Mat4,
}

Vertex :: struct {
	position: Vec3,
	color:    Vec3,
	normal:   Vec3,
}

Instance :: struct {
	model_matrix: Mat4,
	color:        Vec4,
}

instance_from_position_rotation :: proc(
	position: Vec3,
	rotation: Mat3,
	scale: f32 = 1.0,
	color := Color{255, 255, 255, 255},
) -> Instance {
	instance := Instance {
		model_matrix = Mat4(1),
		color        = Vec4(1),
	}
	instance.model_matrix[0, 0] = rotation[0, 0] * scale
	instance.model_matrix[1, 0] = rotation[1, 0]
	instance.model_matrix[2, 0] = rotation[2, 0]
	instance.model_matrix[0, 1] = rotation[0, 1]
	instance.model_matrix[1, 1] = rotation[1, 1] * scale
	instance.model_matrix[2, 1] = rotation[2, 1]
	instance.model_matrix[0, 2] = rotation[0, 2]
	instance.model_matrix[1, 2] = rotation[1, 2]
	instance.model_matrix[2, 2] = rotation[2, 2] * scale
	instance_set_position(&instance, position)
	instance.color = [4]f32 {
		f32(color.r) / 255,
		f32(color.g) / 255,
		f32(color.b) / 255,
		f32(color.a) / 255,
	}
	return instance
}

instance_set_position :: proc(instance: ^Instance, position: Vec3) {
	instance.model_matrix[0, 3] = position.x
	instance.model_matrix[1, 3] = position.y
	instance.model_matrix[2, 3] = position.z
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
		log.errorf("Adapter request failed: %s", message if len(message) != 0 else "Unknown Error")
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
		log.errorf("Device request failed: %s", message if len(message) != 0 else "Unknown Error")
		ctx.success = false
	}
}

buffer_map_callback :: proc "c" (
	status: wgpu.MapAsyncStatus,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	if userdata1 != nil {
		ctx := cast(^WgpuBufferMapContext)userdata1
		ctx.completed = true
		ctx.status = status
		ctx.message = message if len(message) != 0 else ""
		if status != .Success {
			context = {}
			log.errorf(
				"Adapter request failed: %s",
				message if len(message) != 0 else "Unknown Error",
			)
		}
	}
}

init_wgpu_offscreen :: proc(renderer: ^Renderer, window_size: [2]u32) -> bool {
	instance := wgpu.CreateInstance(nil)
	if instance == nil {
		log.error("Failed to create WGPU instance")
		return false
	}

	// We don't need a surface for offscreen rendering
	renderer.surface = nil

	adapter_options := wgpu.RequestAdapterOptions {
		compatibleSurface = nil,
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
		log.error("Failed to get adapter")
		return false
	}
	log.debug("Adapter created:", renderer.adapter != nil)

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
		log.error("Failed to get device")
		return false
	}
	log.debug("Device created:", renderer.device != nil)
	renderer.queue = wgpu.DeviceGetQueue(renderer.device)

	// Create render texture
	if !init_offscreen_texture(renderer, window_size) {
		log.error("Failed to create offscreen texture")
		return false
	}

	// Create depth texture
	if !init_depth_texture(renderer, window_size) {
		log.error("Failed to create depth texture")
		return false
	}

	log.debug("WGPU initialized")
	return true
}

init_wgpu_sdl3 :: proc(renderer: ^Renderer, window: ^sdl3.Window, window_size: [2]u32) -> bool {
	instance := wgpu.CreateInstance(nil)
	if instance == nil {
		log.error("Failed to create WGPU instance")
		return false
	}

	renderer.surface = sdl3glue.GetSurface(instance, window)
	if renderer.surface == nil {
		log.error("Failed to create surface")
		return false
	}
	log.debug("Surface created:", renderer.surface != nil)

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
		log.error("Failed to get adapter")
		return false
	}
	log.debug("Adapter created:", renderer.adapter != nil)

	surface_caps, status := wgpu.SurfaceGetCapabilities(renderer.surface, renderer.adapter)
	if status != .Success {
		log.error("Failed to get surface capabilities")
		return false
	}

	if surface_caps.formatCount == 0 {
		log.error("No supported surface formats")
		return false
	}
	log.debug("Surface format count:", surface_caps.formatCount)

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
		log.error("Failed to get device")
		return false
	}
	log.debug("Device created:", renderer.device != nil)
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
		log.error("Failed to create depth texture")
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
		log.error("Failed to create WGPU instance")
		return false
	}

	renderer.surface = glfwglue.GetSurface(instance, window)
	if renderer.surface == nil {
		log.error("Failed to create surface")
		return false
	}
	log.debug("Surface created:", renderer.surface != nil)

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
		log.error("Failed to get adapter")
		return false
	}
	log.debug("Adapter created:", renderer.adapter != nil)

	surface_caps, status := wgpu.SurfaceGetCapabilities(renderer.surface, renderer.adapter)
	if status != .Success {
		log.error("Failed to get surface capabilities")
		return false
	}

	if surface_caps.formatCount == 0 {
		log.error("No supported surface formats")
		return false
	}
	log.debug("Surface format count:", surface_caps.formatCount)

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
		log.error("Failed to get device")
		return false
	}
	log.debug("Device created:", renderer.device != nil)
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
		log.error("Failed to create depth texture")
		return false
	}

	return true
}

init_render_pipeline :: proc(renderer: ^Renderer) -> bool {
	if !init_commands(renderer) {
		log.error("Failed to initialize commands")
		return false
	}
	vert_shader_desc := wgpu.ShaderModuleDescriptor {
		label       = "Vertex Shader",
		nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = vert_shader_source},
	}
	vert_shader := wgpu.DeviceCreateShaderModule(renderer.device, &vert_shader_desc)
	if vert_shader == nil {
		log.error("Failed to create vertex shader")
		return false
	}

	frag_shader_desc := wgpu.ShaderModuleDescriptor {
		label       = "Fragment Shader",
		nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = frag_shader_source},
	}
	frag_shader := wgpu.DeviceCreateShaderModule(renderer.device, &frag_shader_desc)
	if frag_shader == nil {
		log.error("Failed to create fragment shader")
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
		{format = wgpu.VertexFormat.Float32x3, offset = 1 * size_of([3]f32), shaderLocation = 1},
		{format = wgpu.VertexFormat.Float32x3, offset = 2 * size_of([3]f32), shaderLocation = 2},
	}

	instance_attributes := []wgpu.VertexAttribute {
		{format = wgpu.VertexFormat.Float32x4, offset = 0, shaderLocation = 3},
		{format = wgpu.VertexFormat.Float32x4, offset = 1 * size_of([4]f32), shaderLocation = 4},
		{format = wgpu.VertexFormat.Float32x4, offset = 2 * size_of([4]f32), shaderLocation = 5},
		{format = wgpu.VertexFormat.Float32x4, offset = 3 * size_of([4]f32), shaderLocation = 6},
		{format = wgpu.VertexFormat.Float32x4, offset = 4 * size_of([4]f32), shaderLocation = 7},
	}

	vertex_buffer_layouts := []wgpu.VertexBufferLayout {
		{
			arrayStride = size_of(Vertex),
			stepMode = wgpu.VertexStepMode.Vertex,
			attributeCount = len(vertex_attributes),
			attributes = raw_data(vertex_attributes),
		},
		{
			arrayStride = size_of(Instance),
			stepMode = wgpu.VertexStepMode.Instance,
			attributeCount = len(instance_attributes),
			attributes = raw_data(instance_attributes),
		},
	}

	texture_format :=
		wgpu.TextureFormat.RGBA8Unorm if renderer.offscreen else renderer.surface_config.format
	log.debug("Texture format: ", texture_format)
	pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Render Pipeline",
		layout = pipeline_layout,
		vertex = {
			module = vert_shader,
			entryPoint = "vs_main",
			bufferCount = len(vertex_buffer_layouts),
			buffers = raw_data(vertex_buffer_layouts),
		},
		fragment = &wgpu.FragmentState {
			module = frag_shader,
			entryPoint = "fs_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState {
				format = texture_format,
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
		log.error("Failed to create render pipeline")
		return false
	}
	log.debug("Render pipeline created")
	return true
}

init_buffers :: proc(renderer: ^Renderer) -> bool {
	renderer.meshes = make(map[MeshType]Mesh)

	renderer.meshes[.CUBE] = mesh_init_cube(renderer)
	renderer.meshes[.TETRAHEDRON] = mesh_init_tetrahedron(renderer)
	renderer.meshes[.TRIANGLE] = mesh_init_triangle(renderer)
	renderer.meshes[.SPHERE] = mesh_init_sphere_uv(renderer, 10)

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

init_offscreen_texture :: proc(renderer: ^Renderer, window_size: [2]u32) -> bool {
	if renderer.offscreen_view != nil {
		wgpu.TextureViewRelease(renderer.offscreen_view)
	}
	if renderer.offscreen_texture != nil {
		wgpu.TextureRelease(renderer.offscreen_texture)
	}

	texture_desc := wgpu.TextureDescriptor {
		label = "Offscreen Texture",
		size = {width = window_size.x, height = window_size.y, depthOrArrayLayers = 1},
		mipLevelCount = 1,
		sampleCount = 1,
		dimension = wgpu.TextureDimension._2D,
		format = wgpu.TextureFormat.RGBA8Unorm,
		usage = wgpu.TextureUsageFlags{.RenderAttachment, .TextureBinding, .CopySrc},
	}
	renderer.offscreen_texture = wgpu.DeviceCreateTexture(renderer.device, &texture_desc)
	if renderer.offscreen_texture == nil {
		log.error("Failed to crate offscreen texture")
		return false
	}

	offscreen_view_desc := wgpu.TextureViewDescriptor {
		label           = "Offscreen View",
		format          = wgpu.TextureFormat.RGBA8Unorm,
		dimension       = wgpu.TextureViewDimension._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
		aspect          = .All,
	}
	renderer.offscreen_view = wgpu.TextureCreateView(
		renderer.offscreen_texture,
		&offscreen_view_desc,
	)
	if renderer.offscreen_view == nil {
		log.error("Failed to crate depth view")
		return false
	}

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
		log.error("Failed to crate depth texture")
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
		log.error("Failed to crate depth view")
		return false
	}

	return true
}

init_commands :: proc(renderer: ^Renderer) -> bool {
	renderer.commands = make(DrawBatch)
	return true
}

renderer_cleanup :: proc(renderer: ^Renderer) {
	using renderer
	for key, &value in meshes {
		mesh_destroy(&value)
	}
	if meshes != nil do delete(meshes)
	if uniform_buffer != nil do wgpu.BufferDestroy(uniform_buffer)
	if render_pipeline != nil do wgpu.RenderPipelineRelease(render_pipeline)
	if outline_pipeline != nil do wgpu.RenderPipelineRelease(outline_pipeline)
	if depth_view != nil do wgpu.TextureViewRelease(depth_view)
	if depth_texture != nil do wgpu.TextureRelease(depth_texture)
	if offscreen_view != nil do wgpu.TextureViewRelease(offscreen_view)
	if offscreen_texture != nil do wgpu.TextureRelease(offscreen_texture)
	if device != nil do wgpu.DeviceRelease(device)
	if adapter != nil do wgpu.AdapterRelease(adapter)
	if surface != nil do wgpu.SurfaceRelease(surface)
	if commands != nil do delete(commands)
}

render_offscreen :: proc(renderer: ^Renderer, window_size: [2]u32) {
	// Clear the command list.
	// This must be done before returning to prevent accumulation of draw commands.
	defer clear(&renderer.commands)

	command_encoder_desc := wgpu.CommandEncoderDescriptor {
		label = "Command Encoder",
	}
	command_encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &command_encoder_desc)
	defer wgpu.CommandEncoderRelease(command_encoder)

	// Render passes
	solid_render_pass(renderer, renderer.offscreen_view, command_encoder)
	outline_render_pass(renderer, renderer.offscreen_view, command_encoder)

	// Transfer texture to CPU
	bytes_per_row := 4 * window_size.x
	buffer_size := bytes_per_row * window_size.y

	buffer_desc := wgpu.BufferDescriptor {
		size             = u64(buffer_size),
		usage            = wgpu.BufferUsageFlags{.CopyDst, .MapRead},
		mappedAtCreation = false,
	}
	staging_buffer := wgpu.DeviceCreateBuffer(renderer.device, &buffer_desc)
	if staging_buffer == nil {
		log.error("Failed to create staging buffer")
		return
	}
	defer wgpu.BufferRelease(staging_buffer)

	texel_texture_info := wgpu.TexelCopyTextureInfo {
		texture  = renderer.offscreen_texture,
		mipLevel = 0,
		origin   = {0, 0, 0},
		aspect   = .All,
	}

	texel_buffer_info := wgpu.TexelCopyBufferInfo {
		buffer = staging_buffer,
		layout = wgpu.TexelCopyBufferLayout {
			offset = 0,
			bytesPerRow = bytes_per_row,
			rowsPerImage = window_size.y,
		},
	}

	copy_size := wgpu.Extent3D {
		width              = window_size.x,
		height             = window_size.y,
		depthOrArrayLayers = 1,
	}

	wgpu.CommandEncoderCopyTextureToBuffer(
		command_encoder,
		&texel_texture_info,
		&texel_buffer_info,
		&copy_size,
	)

	command_buffer_desc := wgpu.CommandBufferDescriptor {
		label = "Command Buffer",
	}
	command_buffer := wgpu.CommandEncoderFinish(command_encoder, &command_buffer_desc)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, {command_buffer})

	buffer_map_context := WgpuBufferMapContext {
		completed = false,
		status    = .Unknown,
		message   = "",
	}
	callback_info := wgpu.BufferMapCallbackInfo {
		mode      = .WaitAnyOnly,
		callback  = buffer_map_callback,
		userdata1 = &buffer_map_context,
	}

	wgpu.BufferMapAsync(staging_buffer, {.Read}, 0, uint(buffer_size), callback_info)
	timeout := 1000
	for !buffer_map_context.completed && timeout > 0 {
		wgpu.DevicePoll(renderer.device, false)
		time.sleep(time.Millisecond)
		timeout -= 1
	}

	mapped_data := wgpu.BufferGetMappedRange(staging_buffer, 0, uint(buffer_size))
	wgpu.BufferUnmap(staging_buffer)

	image_buffer: bytes.Buffer
	bytes.buffer_init(&image_buffer, mapped_data)
	defer bytes.buffer_destroy(&image_buffer)
	img := bmp.Image {
		width    = int(window_size.x),
		height   = int(window_size.y),
		channels = 4,
		depth    = 8,
		pixels   = image_buffer,
	}
	if err := bmp.save_to_file("test.bmp", &img); err != nil {
		log.error("Failed to save image to file: ", err)
		return
	}
}

render :: proc(renderer: ^Renderer) {
	// Clear the command list.
	// This must be done before returning to prevent accumulation of draw commands.
	defer clear(&renderer.commands)

	surface_texture := wgpu.SurfaceGetCurrentTexture(renderer.surface)
	if surface_texture.status != wgpu.SurfaceGetCurrentTextureStatus.SuccessOptimal {
		log.debug("Surface texture status:", surface_texture.status)
		if surface_texture.texture != nil do wgpu.TextureRelease(surface_texture.texture)
		// Reconfigure surface and regenerate depth texture
		wgpu.SurfaceConfigure(renderer.surface, &renderer.surface_config)
		init_depth_texture(
			renderer,
			{renderer.surface_config.width, renderer.surface_config.height},
		)
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
		log.error("Failed to create texture view")
	}
	defer wgpu.TextureViewRelease(view)

	command_encoder_desc := wgpu.CommandEncoderDescriptor {
		label = "Command Encoder",
	}
	command_encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &command_encoder_desc)
	defer wgpu.CommandEncoderRelease(command_encoder)

	solid_render_pass(renderer, view, command_encoder)
	outline_render_pass(renderer, view, command_encoder)

	command_buffer_desc := wgpu.CommandBufferDescriptor {
		label = "Command Buffer",
	}
	command_buffer := wgpu.CommandEncoderFinish(command_encoder, &command_buffer_desc)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, {command_buffer})
	wgpu.SurfacePresent(renderer.surface)
}

solid_render_pass :: proc(
	renderer: ^Renderer,
	view: wgpu.TextureView,
	command_encoder: wgpu.CommandEncoder,
) {
	render_pass_desc := wgpu.RenderPassDescriptor {
		label                  = "Render Pass",
		colorAttachmentCount   = 1,
		colorAttachments       = &wgpu.RenderPassColorAttachment {
			view = view,
			loadOp = .Load,
			storeOp = .Store,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			clearValue = {0.01, 0.01, 0.01, 1.0},
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

	// Draw
	for mesh_type in renderer.meshes {
		switch mesh_type {
		case .TRIANGLE:
			render_mesh(mesh_type, renderer, render_pass)
		case .CUBE:
			render_mesh(mesh_type, renderer, render_pass)
		case .TETRAHEDRON:
			render_mesh(mesh_type, renderer, render_pass)
		case .SPHERE:
			render_mesh(mesh_type, renderer, render_pass)
		}
	}
	wgpu.RenderPassEncoderEnd(render_pass)
}

render_mesh :: proc(
	mesh_type: MeshType,
	renderer: ^Renderer,
	render_pass: wgpu.RenderPassEncoder,
) {
	mesh, ok := &renderer.meshes[mesh_type]
	if !ok {
		log.warn("Could not find mesh type ", mesh_type)
	}
	instances := make([dynamic]Instance)
	defer delete(instances)
	for cmd in renderer.commands {
		if cmd.primitive_type == mesh_type {
			append(&instances, cmd.instance)
		}
	}
	instance_count := uint(len(instances))
	// No instances.  Nothing to do.
	if instance_count == 0 do return

	if u32(instance_count) > mesh.instance_capacity {
		log.debugf(
			"Instance count: [%v]%v, capacity: %v",
			len(renderer.commands),
			u32(instance_count),
			mesh.instance_capacity,
		)
		mesh_realloc_instance_buffer(mesh, renderer, u32(instance_count))
		log.debugf(
			"[%v] required: %v, new capacity: %v",
			mesh_type,
			instance_count,
			mesh.instance_capacity,
		)
	}

	wgpu.QueueWriteBuffer(
		renderer.queue,
		mesh.instance_buffer,
		0,
		raw_data(instances),
		instance_count * size_of(Instance),
	)

	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		mesh.vertex_buffer,
		0,
		u64(len(mesh.vertices) * size_of(Vertex)),
	)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		1,
		mesh.instance_buffer,
		0,
		u64(instance_count * size_of(Instance)),
	)

	wgpu.RenderPassEncoderSetIndexBuffer(
		render_pass,
		mesh.index_buffer,
		wgpu.IndexFormat.Uint16,
		0,
		u64(len(mesh.indices) * size_of(u16)),
	)

	wgpu.RenderPassEncoderDrawIndexed(
		render_pass,
		u32(len(mesh.indices)),
		u32(instance_count),
		0,
		0,
		0,
	)
}
