struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec3<f32>,
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let ambient_color = vec3<f32>(1.0) * 0.3;
    return vec4<f32>(ambient_color * input.color, 1.0);
}
