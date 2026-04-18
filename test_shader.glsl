//!HOOK MAIN
//!DESC Red Tint Test Shader
vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    c.r = 1.0;
    c.g = 0.0;
    c.b = 0.0;
    return c;
}
