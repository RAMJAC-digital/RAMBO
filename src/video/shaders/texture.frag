#version 450

layout(binding = 0) uniform sampler2D texSampler;

layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
    // Sample NES frame texture (256×240)
    // Use nearest-neighbor filtering for pixel-perfect scaling
    outColor = texture(texSampler, fragTexCoord);
}
