#version 450

// Fullscreen triangle vertices (covers NDC space -1 to 1)
// Triangle covers entire screen with minimal overdraw
vec2 positions[3] = vec2[](
    vec2(-1.0, -1.0),  // Bottom-left
    vec2( 3.0, -1.0),  // Bottom-right (offscreen)
    vec2(-1.0,  3.0)   // Top-left (offscreen)
);

// Texture coordinates (0,0 = top-left, 1,1 = bottom-right)
vec2 texCoords[3] = vec2[](
    vec2(0.0, 0.0),
    vec2(2.0, 0.0),
    vec2(0.0, 2.0)
);

layout(location = 0) out vec2 fragTexCoord;

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    fragTexCoord = texCoords[gl_VertexIndex];
}
