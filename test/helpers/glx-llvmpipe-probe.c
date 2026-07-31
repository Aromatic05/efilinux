#define GL_GLEXT_PROTOTYPES 1

#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>
#include <X11/Xlib.h>

#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fail(const char *message)
{
    fprintf(stderr, "GLX_PROBE_FAIL:%s\n", message);
    exit(EXIT_FAILURE);
}

static void *require_gl_proc(const char *name)
{
    void *procedure = (void *) glXGetProcAddressARB((const GLubyte *) name);
    if (procedure == NULL) {
        fprintf(stderr, "GLX_PROBE_FAIL:missing procedure %s\n", name);
        exit(EXIT_FAILURE);
    }
    return procedure;
}

static GLuint compile_shader(
    GLenum type,
    const char *source,
    PFNGLCREATESHADERPROC create_shader,
    PFNGLSHADERSOURCEPROC shader_source,
    PFNGLCOMPILESHADERPROC compile_shader_proc,
    PFNGLGETSHADERIVPROC get_shader_iv,
    PFNGLGETSHADERINFOLOGPROC get_shader_info_log)
{
    GLuint shader = create_shader(type);
    GLint compiled = GL_FALSE;

    shader_source(shader, 1, &source, NULL);
    compile_shader_proc(shader);
    get_shader_iv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled != GL_TRUE) {
        char log[4096] = {0};
        get_shader_info_log(shader, sizeof(log), NULL, log);
        fprintf(stderr, "GLX_PROBE_FAIL:shader compilation: %s\n", log);
        exit(EXIT_FAILURE);
    }
    return shader;
}

static GLuint link_program(
    const GLuint *shaders,
    size_t shader_count,
    PFNGLCREATEPROGRAMPROC create_program,
    PFNGLATTACHSHADERPROC attach_shader,
    PFNGLLINKPROGRAMPROC link_program_proc,
    PFNGLGETPROGRAMIVPROC get_program_iv,
    PFNGLGETPROGRAMINFOLOGPROC get_program_info_log)
{
    GLuint program = create_program();
    GLint linked = GL_FALSE;

    for (size_t index = 0; index < shader_count; ++index)
        attach_shader(program, shaders[index]);
    link_program_proc(program);
    get_program_iv(program, GL_LINK_STATUS, &linked);
    if (linked != GL_TRUE) {
        char log[4096] = {0};
        get_program_info_log(program, sizeof(log), NULL, log);
        fprintf(stderr, "GLX_PROBE_FAIL:program link: %s\n", log);
        exit(EXIT_FAILURE);
    }
    return program;
}

static unsigned count_threads(void)
{
    DIR *directory = opendir("/proc/self/task");
    struct dirent *entry;
    unsigned count = 0;

    if (directory == NULL)
        fail("cannot inspect process threads");
    while ((entry = readdir(directory)) != NULL) {
        if (entry->d_name[0] >= '0' && entry->d_name[0] <= '9')
            ++count;
    }
    closedir(directory);
    return count;
}

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    int screen;
    int attributes[] = {
        GLX_RGBA,
        GLX_RED_SIZE, 8,
        GLX_GREEN_SIZE, 8,
        GLX_BLUE_SIZE, 8,
        None,
    };
    XVisualInfo *visual;
    Colormap colormap;
    XSetWindowAttributes window_attributes;
    Window window;
    GLXContext context;
    const char *renderer;
    const char *version;

    if (display == NULL)
        fail("cannot open X display");
    screen = DefaultScreen(display);
    visual = glXChooseVisual(display, screen, attributes);
    if (visual == NULL)
        fail("cannot choose a GLX visual");

    colormap = XCreateColormap(
        display,
        RootWindow(display, visual->screen),
        visual->visual,
        AllocNone);
    window_attributes.colormap = colormap;
    window_attributes.event_mask = StructureNotifyMask;
    window = XCreateWindow(
        display,
        RootWindow(display, visual->screen),
        0,
        0,
        64,
        64,
        0,
        visual->depth,
        InputOutput,
        visual->visual,
        CWColormap | CWEventMask,
        &window_attributes);
    XMapWindow(display, window);
    XSync(display, False);

    context = glXCreateContext(display, visual, NULL, True);
    if (context == NULL || !glXMakeCurrent(display, window, context))
        fail("cannot create a current GLX context");

    renderer = (const char *) glGetString(GL_RENDERER);
    version = (const char *) glGetString(GL_VERSION);
    if (renderer == NULL || strstr(renderer, "llvmpipe") == NULL) {
        fprintf(stderr, "GLX_PROBE_FAIL:unexpected renderer: %s\n",
                renderer != NULL ? renderer : "(null)");
        return EXIT_FAILURE;
    }

    PFNGLCREATESHADERPROC create_shader = require_gl_proc("glCreateShader");
    PFNGLSHADERSOURCEPROC shader_source = require_gl_proc("glShaderSource");
    PFNGLCOMPILESHADERPROC compile_shader_proc = require_gl_proc("glCompileShader");
    PFNGLGETSHADERIVPROC get_shader_iv = require_gl_proc("glGetShaderiv");
    PFNGLGETSHADERINFOLOGPROC get_shader_info_log = require_gl_proc("glGetShaderInfoLog");
    PFNGLCREATEPROGRAMPROC create_program = require_gl_proc("glCreateProgram");
    PFNGLATTACHSHADERPROC attach_shader = require_gl_proc("glAttachShader");
    PFNGLLINKPROGRAMPROC link_program_proc = require_gl_proc("glLinkProgram");
    PFNGLGETPROGRAMIVPROC get_program_iv = require_gl_proc("glGetProgramiv");
    PFNGLGETPROGRAMINFOLOGPROC get_program_info_log = require_gl_proc("glGetProgramInfoLog");
    PFNGLUSEPROGRAMPROC use_program = require_gl_proc("glUseProgram");
    PFNGLDELETESHADERPROC delete_shader = require_gl_proc("glDeleteShader");
    PFNGLDELETEPROGRAMPROC delete_program = require_gl_proc("glDeleteProgram");

    const char *vertex_source =
        "#version 120\n"
        "void main() { gl_Position = gl_Vertex; }\n";
    const char *fragment_source =
        "#version 120\n"
        "void main() { gl_FragColor = vec4(0.25, 0.50, 0.75, 1.0); }\n";
    GLuint vertex_shader = compile_shader(
        GL_VERTEX_SHADER,
        vertex_source,
        create_shader,
        shader_source,
        compile_shader_proc,
        get_shader_iv,
        get_shader_info_log);
    GLuint fragment_shader = compile_shader(
        GL_FRAGMENT_SHADER,
        fragment_source,
        create_shader,
        shader_source,
        compile_shader_proc,
        get_shader_iv,
        get_shader_info_log);
    GLuint graphics_shaders[] = {vertex_shader, fragment_shader};
    GLuint graphics_program = link_program(
        graphics_shaders,
        2,
        create_program,
        attach_shader,
        link_program_proc,
        get_program_iv,
        get_program_info_log);

    use_program(graphics_program);
    glViewport(0, 0, 64, 64);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glBegin(GL_TRIANGLES);
    glVertex2f(-1.0f, -1.0f);
    glVertex2f(1.0f, -1.0f);
    glVertex2f(0.0f, 1.0f);
    glEnd();
    glFinish();

    uint8_t pixel[4] = {0};
    glReadPixels(32, 24, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    if (pixel[0] < 48 || pixel[0] > 80 ||
        pixel[1] < 112 || pixel[1] > 144 ||
        pixel[2] < 176 || pixel[2] > 208)
        fail("GLSL draw/readback produced an unexpected pixel");

    PFNGLGENBUFFERSPROC gen_buffers = require_gl_proc("glGenBuffers");
    PFNGLBINDBUFFERPROC bind_buffer = require_gl_proc("glBindBuffer");
    PFNGLBUFFERDATAPROC buffer_data = require_gl_proc("glBufferData");
    PFNGLBINDBUFFERBASEPROC bind_buffer_base = require_gl_proc("glBindBufferBase");
    PFNGLDISPATCHCOMPUTEPROC dispatch_compute = require_gl_proc("glDispatchCompute");
    PFNGLMEMORYBARRIERPROC memory_barrier = require_gl_proc("glMemoryBarrier");
    PFNGLMAPBUFFERRANGEPROC map_buffer_range = require_gl_proc("glMapBufferRange");
    PFNGLUNMAPBUFFERPROC unmap_buffer = require_gl_proc("glUnmapBuffer");
    PFNGLDELETEBUFFERSPROC delete_buffers = require_gl_proc("glDeleteBuffers");

    const char *compute_source =
        "#version 430\n"
        "layout(local_size_x = 1) in;\n"
        "layout(std430, binding = 0) buffer Result { uint value; };\n"
        "void main() { value = 0x12345678u; }\n";
    GLuint compute_shader = compile_shader(
        GL_COMPUTE_SHADER,
        compute_source,
        create_shader,
        shader_source,
        compile_shader_proc,
        get_shader_iv,
        get_shader_info_log);
    GLuint compute_program = link_program(
        &compute_shader,
        1,
        create_program,
        attach_shader,
        link_program_proc,
        get_program_iv,
        get_program_info_log);
    GLuint buffer;
    uint32_t initial_value = 0;

    gen_buffers(1, &buffer);
    bind_buffer(GL_SHADER_STORAGE_BUFFER, buffer);
    buffer_data(
        GL_SHADER_STORAGE_BUFFER,
        sizeof(initial_value),
        &initial_value,
        GL_DYNAMIC_COPY);
    bind_buffer_base(GL_SHADER_STORAGE_BUFFER, 0, buffer);
    use_program(compute_program);
    dispatch_compute(1, 1, 1);
    memory_barrier(GL_SHADER_STORAGE_BARRIER_BIT | GL_BUFFER_UPDATE_BARRIER_BIT);

    uint32_t *computed_value = map_buffer_range(
        GL_SHADER_STORAGE_BUFFER,
        0,
        sizeof(*computed_value),
        GL_MAP_READ_BIT);
    if (computed_value == NULL || *computed_value != UINT32_C(0x12345678))
        fail("compute shader barrier/readback failed");
    if (unmap_buffer(GL_SHADER_STORAGE_BUFFER) != GL_TRUE)
        fail("compute buffer became invalid while mapped");

    unsigned thread_count = count_threads();
    if (thread_count < 2)
        fail("llvmpipe did not create worker threads");

    printf("EFILINUX_GL_RENDERER=llvmpipe\n");
    printf("EFILINUX_GL_RENDERER_STRING=%s\n", renderer);
    printf("EFILINUX_GL_VERSION=%s\n", version != NULL ? version : "unknown");
    printf("EFILINUX_GL_SHADER_OK\n");
    printf("EFILINUX_GL_COMPUTE_OK\n");
    printf("EFILINUX_LLVMPIPE_THREADS=%u\n", thread_count);

    delete_buffers(1, &buffer);
    delete_program(compute_program);
    delete_shader(compute_shader);
    delete_program(graphics_program);
    delete_shader(fragment_shader);
    delete_shader(vertex_shader);
    glXMakeCurrent(display, None, NULL);
    glXDestroyContext(display, context);
    XDestroyWindow(display, window);
    XFreeColormap(display, colormap);
    XFree(visual);
    XCloseDisplay(display);
    return EXIT_SUCCESS;
}
