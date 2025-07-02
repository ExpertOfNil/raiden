struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let ambient_color = vec4<f32>(vec3<f32>(0.5), 1.0);
    return vec4<f32>(ambient_color * input.color);
}
