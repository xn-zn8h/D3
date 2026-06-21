shader_type canvas_item;
render_mode unshaded;

#hint_default_value 4.0
uniform float pixel_size: float = 4.0;
hint_range(0.5, 8.0)
uniform float intensity: float = 1.0;

void fragment() {
	// Quantize UV coordinates to create pixel grid
	vec2 pixelated_size = vec2(1.0 / (pixel_size * intensity));
	vec2 quantized = floor(UV / pixelated_size) * pixelated_size;
	
	// Sample texture at quantized coordinates
	vec4 color = texture(TEXTURE, quantized);
	
	// Apply color
	COLOR = color;
}
