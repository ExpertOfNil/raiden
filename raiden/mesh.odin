package raiden

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "vendor:wgpu"

DEFAULT_INSTANCE_CAPACITY :: 100

MeshType :: enum {
	TRIANGLE,
	CUBE,
	TETRAHEDRON,
}

Mesh :: struct {
	vertices:          [dynamic]Vertex,
	indices:           [dynamic]u16,
	vertex_buffer:     wgpu.Buffer,
	index_buffer:      wgpu.Buffer,
	instance_buffer:   wgpu.Buffer,
	instance_capacity: u32,
}

mesh_destroy :: proc(mesh: ^Mesh) {
	using mesh
	if vertex_buffer != nil do wgpu.BufferDestroy(vertex_buffer)
	if index_buffer != nil do wgpu.BufferDestroy(index_buffer)
	if instance_buffer != nil do wgpu.BufferDestroy(instance_buffer)

	if vertices != nil do delete(vertices)
	if indices != nil do delete(indices)
}

mesh_create_buffers :: proc(mesh: ^Mesh, renderer: ^Renderer, n_vertices: int, n_indices: int) {
	// Create vertex buffer
	vertices_size := uint(n_vertices * size_of(Vertex))
	fmt.printfln("Cube vertices size: %v", vertices_size)
	vertex_buffer_desc := wgpu.BufferDescriptor {
		label            = "Cube Vertex Buffer",
		size             = u64(vertices_size),
		usage            = wgpu.BufferUsageFlags {
			wgpu.BufferUsage.Vertex,
			wgpu.BufferUsage.CopyDst,
		},
		mappedAtCreation = false,
	}
	mesh.vertex_buffer = wgpu.DeviceCreateBuffer(renderer.device, &vertex_buffer_desc)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		mesh.vertex_buffer,
		0,
		raw_data(mesh.vertices),
		vertices_size,
	)

	// Create index buffer
	indices_size := uint(n_indices * size_of(u16))
	fmt.printfln("Cube indices size: %v", indices_size)
	index_buffer_desc := wgpu.BufferDescriptor {
		label            = "Cube Index Buffer",
		size             = u64(indices_size),
		usage            = wgpu.BufferUsageFlags{wgpu.BufferUsage.Index, wgpu.BufferUsage.CopyDst},
		mappedAtCreation = false,
	}
	mesh.index_buffer = wgpu.DeviceCreateBuffer(renderer.device, &index_buffer_desc)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		mesh.index_buffer,
		0,
		raw_data(mesh.indices),
		indices_size,
	)

	// Create instance buffer
	mesh.instance_capacity = DEFAULT_INSTANCE_CAPACITY
	instances_size := uint(mesh.instance_capacity * size_of(Instance))
	fmt.printfln("Cube instance size: %v", instances_size)
	instance_buffer_desc := wgpu.BufferDescriptor {
		label            = "Cube Instance Buffer",
		size             = u64(instances_size),
		usage            = wgpu.BufferUsageFlags {
			wgpu.BufferUsage.Vertex,
			wgpu.BufferUsage.CopyDst,
		},
		mappedAtCreation = false,
	}
	mesh.instance_buffer = wgpu.DeviceCreateBuffer(renderer.device, &instance_buffer_desc)
}

mesh_realloc_instance_buffer :: proc(mesh: ^Mesh, renderer: ^Renderer, new_capacity: u32) {
	// Create new instance buffer
    for mesh.instance_capacity < new_capacity {
        mesh.instance_capacity *= 2
    }
	instances_size := uint(mesh.instance_capacity * size_of(Instance))
	fmt.printfln("Mesh instance size: %v", instances_size)
	instance_buffer_desc := wgpu.BufferDescriptor {
		label            = "Cube Instance Buffer",
		size             = u64(instances_size),
		usage            = wgpu.BufferUsageFlags {
			wgpu.BufferUsage.Vertex,
			wgpu.BufferUsage.CopyDst,
		},
		mappedAtCreation = false,
	}
	if mesh.instance_buffer != nil do wgpu.BufferDestroy(mesh.instance_buffer)
	mesh.instance_buffer = wgpu.DeviceCreateBuffer(renderer.device, &instance_buffer_desc)
}

mesh_init_cube :: proc(renderer: ^Renderer) -> Mesh {
	n_vertices := len(CUBE_VERTICES)
	n_indices := len(CUBE_INDICES)
	mesh := Mesh {
		vertices = make([dynamic]Vertex, n_vertices),
		indices  = make([dynamic]u16, n_indices),
	}
	for &v, i in CUBE_VERTICES {
		mesh.vertices[i] = v
	}
	for &idx, i in CUBE_INDICES {
		mesh.indices[i] = idx
	}

	mesh_create_buffers(&mesh, renderer, n_vertices, n_indices)
	return mesh
}

align_buffer_size :: proc(size: uint, alignment: uint = 4) -> uint {
	return (size + alignment - 1) / alignment * alignment
}

mesh_init_triangle :: proc(renderer: ^Renderer) -> Mesh {
	n_vertices :: 3
	n_indices :: 4
	mesh := Mesh {
		vertices = make([dynamic]Vertex, n_vertices),
		indices  = make([dynamic]u16, n_indices),
	}

	mesh.vertices[0].position = Vec3{0.0, 1.0, 0.0}
	mesh.vertices[1].position = Vec3{1.0, -1.0, 0.0}
	mesh.vertices[2].position = Vec3{-1.0, -1.0, 0.0}

    // odinfmt: disable
	indices: []u16 = {
        0, 2, 1, 0
    }
    // odinfmt: enable
	for idx, i in indices {
		mesh.indices[i] = idx
	}
	va := linalg.normalize(mesh.vertices[0].position)
	vb := linalg.normalize(mesh.vertices[1].position)
	vc := linalg.normalize(mesh.vertices[2].position)
	n := linalg.cross(vb - va, vc - va)
	mesh.vertices[0].normal = n
	mesh.vertices[1].normal = n
	mesh.vertices[2].normal = n

	mesh_create_buffers(&mesh, renderer, n_vertices, n_indices)
	return mesh
}

mesh_init_tetrahedron :: proc(renderer: ^Renderer) -> Mesh {
	n_vertices :: 4
	n_indices :: 12
	mesh := Mesh {
		vertices = make([dynamic]Vertex, n_vertices),
		indices  = make([dynamic]u16, n_indices),
	}

	a := math.sqrt_f32(8.0 / 9.0)
	b := -1.0 / (2.0 * math.sqrt_f32(6.0))
	c := -math.sqrt_f32(2.0 / 9.0)
	d := math.sqrt_f32(2.0 / 3.0)
	e := math.sqrt_f32(3.0 / 8.0)
	// Base vertex aligned with y-axis
	mesh.vertices[0].position = Vec3{0.0, a, b}
	// Base vertex
	mesh.vertices[1].position = Vec3{d, c, b}
	// Base vertex
	mesh.vertices[2].position = Vec3{-d, c, b}
	// Top vertex aligned with z-axis
	mesh.vertices[3].position = Vec3{0.0, 0.0, e}

    // odinfmt: disable
	indices: []u16 = {
        0, 1, 2,
        0, 2, 3,
        2, 1, 3,
        1, 0, 3
    }
    // odinfmt: enable
	for idx, i in indices {
		mesh.indices[i] = idx
	}

	// Create normals
	for v: u16 = 0; v < n_vertices; v += 1 {
		v_norm := Vec3(0)
		for i := 0; i < len(indices); i += 3 {
			// Make sure the current vertex is in this triangle
			a := indices[i]
			b := indices[i + 1]
			c := indices[i + 2]
			if v != a && v != b && v != c {
				continue
			}
			// Find the face normal
			va := mesh.vertices[a].position
			vb := mesh.vertices[b].position
			vc := mesh.vertices[c].position
			n := linalg.cross(vb - va, vc - va)
			v_norm += n
		}
		mesh.vertices[v].normal = linalg.normalize(v_norm)
	}

	mesh_create_buffers(&mesh, renderer, n_vertices, n_indices)
	return mesh
}

/*
mesh_init_sphere_uv :: proc(divisions: u32) -> Mesh {
	n := 2 * divisions * divisions + 2
	mesh := Mesh {
		vertices = make([dynamic]Vertex, n),
		indices  = make([dynamic]u16, n),
	}

	vidx := 0

	// Top pole
	vertex := &mesh.vertices[vidx]
	vertex.position = Vec3{0, 0, 1}
	vertex.normal = linalg.normalize(vertex.position)
	vertex.color = Vec3(1)

    // Middle
	ds: f32 = 360.0 / f32(n)
	for i in 1 ..= n {
		phi := f32(i) * ds
		for j in 0 ..< n {
			theta := f32(j) * ds
			vidx += 1
			vertex = &mesh.vertices[vidx]
			vertex.position = Vec3 {
				math.sin(theta) * math.cos(phi),
				math.sin(theta) * math.sin(phi),
				math.cos(theta),
			}
			vertex.normal = linalg.normalize(vertex.position)
			vertex.color = Vec3(1)
		}
	}

    // Bottom pole
    vidx += 1
	vertex = &mesh.vertices[vidx]
	vertex.position = Vec3{0, 0, -1}
	vertex.normal = linalg.normalize(vertex.position)
	vertex.color = Vec3(1)

	// Top cap
	for j in 0 ..< longitude {
		next := (j + 1) % longitude
		indices = append(indices, top_index, 1 + j, 1 + next)
	}

}

generate_uv_sphere :: proc(radius: f32, divisions: int) -> MeshData {
	longitude := 2 * divisions
	latitude := divisions

	vertex_count := 2 + (latitude - 1) * longitude
	index_count := 6 * longitude * (latitude - 1) // 2 tris per quad

	positions := make([]Vec3, vertex_count)
	normals := make([]Vec3, vertex_count)
	indices := make([]u32, 0, index_count)

	idx := 0

	// Top pole
	positions[idx] = Vec3{0, radius, 0}
	normals[idx] = normalize(positions[idx])
	top_index := idx
	idx += 1

	// Rings (excluding poles)
	for i in 1 ..< latitude {
		phi := f32(i) * f32(PI) / f32(latitude) // [0, π]
		y := radius * cos(phi)
		r := radius * sin(phi)

		for j in 0 ..< longitude {
			theta := f32(j) * 2.0 * f32(PI) / f32(longitude) // [0, 2π)
			x := r * cos(theta)
			z := r * sin(theta)

			positions[idx] = Vec3{x, y, z}
			normals[idx] = normalize(positions[idx])
			idx += 1
		}
	}

	// Bottom pole
	positions[idx] = Vec3{0, -radius, 0}
	normals[idx] = normalize(positions[idx])
	bottom_index := idx

	// === Indices ===

	// Top cap
	for j in 0 ..< longitude {
		next := (j + 1) % longitude
		indices = append(indices, top_index, 1 + j, 1 + next)
	}

	// Middle quads
	for i in 0 ..< (latitude - 2) {
		row := 1 + i * longitude
		next_row := row + longitude

		for j in 0 ..< longitude {
			next := (j + 1) % longitude

			a := row + j
			b := row + next
			c := next_row + j
			d := next_row + next

			indices = append(indices, a, c, b)
			indices = append(indices, b, c, d)
		}
	}

	// Bottom cap
	base := 1 + (latitude - 2) * longitude
	for j in 0 ..< longitude {
		next := (j + 1) % longitude
		indices = append(indices, base + j, bottom_index, base + next)
	}

	return MeshData{positions = positions, normals = normals, indices = indices}
}
*/
