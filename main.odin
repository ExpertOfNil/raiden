package main

import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"
import "raiden"

Cloud :: struct {
	ids:       [dynamic]string,
	positions: [dynamic]raiden.Vec3,
}

read_cloud_csv :: proc(path: string, cloud: ^Cloud, skip_header: bool = false) -> bool {
	file, err := os.open(path)
	if err != nil {
		log.error("Failed to open file:", err)
	}
	defer os.close(file)

	buffer: [4096]u8
	residual := ""
	line_index := 1
	for {
		bytes_read, err := os.read(file, buffer[:])
		if err != nil {
			log.error("Error reading file contents")
			break
		}
		if bytes_read == 0 {
			// EOF
			break
		}

		blob := strings.concatenate({residual, string(buffer[:bytes_read])})
		lines := strings.split(blob, "\n")

		if !strings.has_suffix(blob, "\n") {
			residual = lines[len(lines) - 1]
			lines = lines[:len(lines) - 1]
		} else {
			residual = ""
		}

		for line in lines {
			defer line_index += 1
			if line_index == 0 && skip_header do continue
			if line == "" do continue

			fields := strings.split(line, ",")
			if len(fields) != 4 {
				log.errorf("Malformed line [%v] with fields: %v", line_index, fields)
				log.errorf("lines: \n%v", lines)
				continue
			}

			if !deserialize_cloud_point(cloud, &fields) {
				continue
			}
		}

		if residual != "" {
			fields := strings.split(residual, ",")
			if len(fields) == 4 {
				if !deserialize_cloud_point(cloud, &fields) {
					continue
				}
			}
		}
	}
	return true
}

deserialize_cloud_point :: proc(cloud: ^Cloud, fields: ^[]string) -> bool {
	append(&cloud.ids, strings.trim_space(fields[0]))
	pos: raiden.Vec3
	if x, ok := strconv.parse_f32(strings.trim_space(fields[1])); ok {
		pos.x = x
	} else {
		log.errorf("Failed to parse x: %v", fields[1])
		return false
	}

	if y, ok := strconv.parse_f32(strings.trim_space(fields[2])); ok {
		pos.y = y
	} else {
		log.errorf("Failed to parse y: %v", fields[2])
		return false
	}

	if z, ok := strconv.parse_f32(strings.trim_space(fields[3])); ok {
		pos.z = z
	} else {
		log.errorf("Failed to parse z: %v", fields[3])
		return false
	}
	append(&cloud.positions, pos)
	return true
}

main :: proc() {
	context.logger = log.create_console_logger(.Debug)
	cloud := Cloud {
		ids       = make([dynamic]string),
		positions = make([dynamic]raiden.Vec3),
	}
	defer delete(cloud.ids)
	defer delete(cloud.positions)
	if !read_cloud_csv("test.csv", &cloud) {
		os.exit(1)
	}
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

		for pt in cloud.positions {
			raiden.draw_cube(
				&engine.renderer,
				position = pt,
				scale = 0.2,
				color = {255, 255, 0, 255},
			)
		}
		raiden.render(&engine.renderer)
	}
}
