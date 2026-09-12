#version 330
// Implemented by Claude

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

out vec2 fragTexCoord;
out vec4 fragColor;

uniform mat4 mvp;
uniform float u_time;
uniform float wobble_speed = 8.0;
uniform float sin_mult = 2.0;
uniform float cos_mult = 1.6;
const float pi = 3.14159;

void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;

    vec3 pos = vertexPosition;

    // "Underwater" wobble: x and y each nudge using the *other* axis's own corner (0 or 1, always --
    // see below) as part of their phase, so opposite edges push in opposite directions (a shear/twist)
    // instead of the whole rectangle just sliding rigidly. `* 3.14159` (pi, a half cycle) is deliberate
    // here, not the more obvious-looking `2*pi`: sin has period 2*pi, so a corner at texcoord 1 would
    // land back on the *same* phase as texcoord 0 (sin(x) == sin(x + 2*pi) always) -- every corner
    // would move identically, which is a rigid translation, not a distortion. Half a cycle (pi) instead
    // puts texcoord-0 and texcoord-1 corners exactly out of phase (sin(x + pi) == -sin(x)), so they
    // push opposite ways. Amplitude (5.0 px) and frequency (2 rad/s, 1.6 rad/s) are a first guess --
    // tune to taste once you can actually see it move.
    //
    // Deliberately vertexTexCoord (0..1 across the quad's own corners), not vertexPosition (the
    // rectangle's real on-screen coordinates) -- vertexPosition changes as the rectangle moves, which
    // fed the rectangle's own movement speed/direction straight into the wobble's phase, the same
    // coupling bug the wave shader had earlier with fragTexCoord.y. vertexTexCoord is intrinsic to the
    // quad itself and never changes no matter where the rectangle is or how it's moving.
    pos.x += sin(u_time * sin_mult + vertexTexCoord.y * pi) * wobble_speed;
    pos.y += cos(u_time * cos_mult + vertexTexCoord.x * pi) * wobble_speed;

    gl_Position = mvp * vec4(pos, 1.0);
}
