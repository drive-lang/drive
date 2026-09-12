#version 330
// Implemented by Claude

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

// Whatever's already been rendered behind this rectangle -- see raylib_shaders.prog, which renders
// the plain background into its own texture first, purely so this shader has something to read.
uniform sampler2D background;

// Must match SCREEN_WIDTH/SCREEN_HEIGHT in raylib_shaders.prog -- there's no vec2 uniform setter in
// the Backend binding yet, so this is a plain constant rather than something passed in per-frame.
const vec2 SCREEN_SIZE = vec2(800.0, 600.0);

void main() {
    // gl_FragCoord is real window-space pixel position (spec-defined, bottom-left origin) -- the same
    // convention a render texture is stored in, so (unlike DrawTexturePro's own Rectangle-based
    // addressing, which needs an explicit Y-flip to compensate) no manual flip is needed here.
    vec2 screenUV = gl_FragCoord.xy / SCREEN_SIZE;

    vec3 belowColor = texture(background, screenUV).rgb;
    finalColor = vec4(1.0 - belowColor, 1.0);
}
