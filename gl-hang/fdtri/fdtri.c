/*
 * fdtri — GLES 3.0 checks for the a306 (freedreno a3xx), headless (GBM + EGL, no window):
 *
 *  instances  Draw N one-pixel quads with glDrawArraysInstanced (gl_InstanceID picks the pixel) into a 64x64
 *             target and count the pixels drawn. The a3xx CP_DRAW_INDX packet carries (instances - 1) in 8 bits;
 *             a count above 256 wraps unless something splits the draw.
 *  instattr   The same with the pixel position in a per-instance vertex attribute (divisor 1), the way WebRender
 *             feeds its instances; also checks that each instance landed on its own pixel.
 *  cutout     WebRender's underlay cutout (ISSUES 23 black triangle): a 1024x512 RGBA8 + depth target (a picture
 *             cache tile) cleared to opaque, optionally covered by an opaque instanced draw first, then one instanced
 *             quad over (0,0)-(1024,160) with destination-out blending (alpha -> 0). Counts the pixels inside the quad
 *             that stayed opaque, per 128x128 block (the real bins for this target are 192x64, see binsim.py: x
 *             edges 0/192/384/576/768/960), and the pixels outside
 *             it that changed. The quad and an optional scissor can be given (e.g. the same quad at the top of a
 *             y-up target: 0 352 1024 512, or one pixel short of the right edge: 0 0 1023 160).
 *
 * Usage: fdtri instances [N…] | fdtri instattr [N…] | fdtri cutout [repeat] [opaque-first 0|1] [x0 y0 x1 y1 [sx sy sw sh]]
 * Env: FD_MESA_DEBUG=gmem forces tiled (GMEM) rendering, =nobin disables hw binning, =sysmem disables tiling.
 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void die(const char *m) { fprintf(stderr, "fdtri: %s (egl 0x%x gl 0x%x)\n", m, eglGetError(), glGetError()); exit(2); }

static void init_gl(void)
{
	int fd = open("/dev/dri/renderD128", O_RDWR);
	if (fd < 0) die("open renderD128");
	struct gbm_device *gbm = gbm_create_device(fd);
	if (!gbm) die("gbm_create_device");
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay d = gpd ? gpd(EGL_PLATFORM_GBM_KHR, gbm, NULL) : eglGetDisplay((EGLNativeDisplayType)gbm);
	if (d == EGL_NO_DISPLAY || !eglInitialize(d, NULL, NULL)) die("eglInitialize");
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint ca[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE };
	EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ca);
	if (c == EGL_NO_CONTEXT) die("eglCreateContext");
	if (!eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c)) die("eglMakeCurrent (surfaceless)");
	fprintf(stderr, "renderer: %s / %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
}

static GLuint shader(GLenum t, const char *src)
{
	GLuint s = glCreateShader(t);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) { char log[2048]; glGetShaderInfoLog(s, sizeof log, NULL, log); fprintf(stderr, "%s\n", log); die("compile"); }
	return s;
}

static GLuint program(const char *vs, const char *fs)
{
	GLuint p = glCreateProgram();
	glAttachShader(p, shader(GL_VERTEX_SHADER, vs));
	glAttachShader(p, shader(GL_FRAGMENT_SHADER, fs));
	glBindAttribLocation(p, 0, "aPosition");
	glBindAttribLocation(p, 1, "aRect");
	glLinkProgram(p);
	GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok) die("link");
	return p;
}

static GLuint target(int w, int h, int depth)
{
	GLuint fb, tex, rb;
	glGenFramebuffers(1, &fb); glBindFramebuffer(GL_FRAMEBUFFER, fb);
	glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	if (depth) {
		glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rb);
	}
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) die("fbo");
	glViewport(0, 0, w, h);
	return fb;
}

/* unit quad as two triangles, like WebRender's aPosition vertex buffer */
static void unit_quad(void)
{
	static const float q[] = { 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1 };
	GLuint vb; glGenBuffers(1, &vb); glBindBuffer(GL_ARRAY_BUFFER, vb);
	glBufferData(GL_ARRAY_BUFFER, sizeof q, q, GL_STATIC_DRAW);
	glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);
}

static int test_instances(int argc, char **argv)
{
	static const char *vs = "#version 300 es\nin vec2 aPosition;\nvoid main() {\n"
		"  vec2 px = vec2(float(gl_InstanceID % 64), float(gl_InstanceID / 64));\n"
		"  gl_Position = vec4((px + aPosition) / 32.0 - 1.0, 0.0, 1.0);\n}\n";
	static const char *fs = "#version 300 es\nprecision mediump float;\nout vec4 o;\nvoid main() { o = vec4(1.0); }\n";
	int ns[] = { 200, 255, 256, 257, 300, 513, 1000, 4096 }, nn = sizeof ns / sizeof *ns;
	if (argc > 0) { nn = argc; for (int i = 0; i < nn && i < 8; i++) ns[i] = atoi(argv[i]); }
	GLuint p = program(vs, fs);
	target(64, 64, 0); unit_quad();
	static unsigned char px[64 * 64 * 4];
	int bad = 0;
	for (int i = 0; i < nn; i++) {
		glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT);
		glUseProgram(p); glDrawArraysInstanced(GL_TRIANGLES, 0, 6, ns[i]);
		glReadPixels(0, 0, 64, 64, GL_RGBA, GL_UNSIGNED_BYTE, px);
		int lit = 0; for (int k = 0; k < 64 * 64; k++) lit += px[k * 4] > 128;
		printf("instances %5d: %5d pixels drawn%s\n", ns[i], lit, lit == ns[i] ? "" : "  <-- WRONG");
		bad |= lit != ns[i];
	}
	return bad;
}

static int test_instattr(int argc, char **argv)
{
	static const char *vs = "#version 300 es\nin vec2 aPosition;\nin vec4 aRect;\nvoid main() {\n"
		"  gl_Position = vec4((aRect.xy + aPosition) / 32.0 - 1.0, 0.0, 1.0);\n}\n";
	static const char *fs = "#version 300 es\nprecision mediump float;\nout vec4 o;\nvoid main() { o = vec4(1.0); }\n";
	int ns[] = { 200, 256, 257, 300, 513, 1000, 4096 }, nn = sizeof ns / sizeof *ns;
	if (argc > 0) { nn = argc; for (int i = 0; i < nn && i < 7; i++) ns[i] = atoi(argv[i]); }
	GLuint p = program(vs, fs);
	target(64, 64, 0); unit_quad();
	static float inst[4096 * 4];
	for (int k = 0; k < 4096; k++) { inst[k * 4] = k % 64; inst[k * 4 + 1] = k / 64; inst[k * 4 + 2] = inst[k * 4 + 3] = 0; }
	GLuint ib; glGenBuffers(1, &ib); glBindBuffer(GL_ARRAY_BUFFER, ib);
	glBufferData(GL_ARRAY_BUFFER, sizeof inst, inst, GL_STATIC_DRAW);
	glEnableVertexAttribArray(1); glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 0, 0); glVertexAttribDivisor(1, 1);
	static unsigned char px[64 * 64 * 4];
	int bad = 0;
	for (int i = 0; i < nn; i++) {
		glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT);
		glUseProgram(p); glDrawArraysInstanced(GL_TRIANGLES, 0, 6, ns[i]);
		glReadPixels(0, 0, 64, 64, GL_RGBA, GL_UNSIGNED_BYTE, px);
		int lit = 0, stray = 0;
		for (int k = 0; k < 64 * 64; k++) { int on = px[k * 4] > 128; lit += on; stray += on && k >= ns[i]; }
		printf("instattr  %5d: %5d pixels drawn, %d outside the first N%s\n", ns[i], lit, stray,
		       lit == ns[i] && !stray ? "" : "  <-- WRONG");
		bad |= lit != ns[i] || stray;
	}
	return bad;
}

static int test_cutout(int argc, char **argv)
{
	/* WebRender-like: instance attribute aRect = (x0, y0, x1, y1) in pixels, projection uniform */
	static const char *vs = "#version 300 es\nin vec2 aPosition;\nin vec4 aRect;\nuniform mat4 uTransform;\n"
		"void main() { vec2 p = mix(aRect.xy, aRect.zw, aPosition); gl_Position = uTransform * vec4(p, 0.5, 1.0); }\n";
	static const char *fs = "#version 300 es\nprecision mediump float;\nuniform vec4 uColor;\nout vec4 o;\n"
		"void main() { o = uColor; }\n";
	int repeat = argc > 0 ? atoi(argv[0]) : 5, opaque_first = argc > 1 ? atoi(argv[1]) : 1;
	float cut[4] = { 0, 0, 1024, 160 };
	if (argc > 5) for (int i = 0; i < 4; i++) cut[i] = atof(argv[2 + i]);
	int sc = argc > 9, sx = sc ? atoi(argv[6]) : 0, sy = sc ? atoi(argv[7]) : 0, sw = sc ? atoi(argv[8]) : 0, sh = sc ? atoi(argv[9]) : 0;
	const int W = 1024, H = 512;
	GLuint p = program(vs, fs);
	target(W, H, 1); unit_quad();
	GLuint ib; glGenBuffers(1, &ib); glBindBuffer(GL_ARRAY_BUFFER, ib);
	glEnableVertexAttribArray(1); glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 0, 0); glVertexAttribDivisor(1, 1);
	glUseProgram(p);
	/* orthographic projection: pixels -> clip space (y down, like WebRender's render targets) */
	float m[16] = { 2.0f / W, 0, 0, 0, 0, 2.0f / H, 0, 0, 0, 0, 1, 0, -1, -1, 0, 1 };
	glUniformMatrix4fv(glGetUniformLocation(p, "uTransform"), 1, GL_FALSE, m);
	GLint ucol = glGetUniformLocation(p, "uColor");
	unsigned char *px = malloc(W * H * 4);
	int fails = 0;
	for (int r = 0; r < repeat; r++) {
		glDisable(GL_SCISSOR_TEST); glDisable(GL_BLEND);
		glClearColor(0, 0, 0, 1); glClearDepthf(1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		if (sc) { glEnable(GL_SCISSOR_TEST); glScissor(sx, sy, sw, sh); }
		if (opaque_first) { /* opaque pass: one full-target quad, depth write */
			float full[4] = { 0, 0, W, H };
			glBufferData(GL_ARRAY_BUFFER, sizeof full, full, GL_DYNAMIC_DRAW);
			glEnable(GL_DEPTH_TEST); glDepthFunc(GL_LEQUAL); glDepthMask(GL_TRUE);
			glUniform4f(ucol, 0.1f, 0.2f, 0.3f, 1.0f);
			glDrawArraysInstanced(GL_TRIANGLES, 0, 6, 1);
		}
		/* alpha pass: the cutout, premultiplied destination-out, depth test without write */
		glBufferData(GL_ARRAY_BUFFER, sizeof cut, cut, GL_DYNAMIC_DRAW);
		glDepthMask(GL_FALSE);
		glEnable(GL_BLEND); glBlendFuncSeparate(GL_ZERO, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE_MINUS_SRC_ALPHA);
		glUniform4f(ucol, 0, 0, 0, 1);
		glDrawArraysInstanced(GL_TRIANGLES, 0, 6, 1);
		glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
		int bin[4][8] = { 0 }, outside = 0, left = 0;
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++) {
				int inq = x >= cut[0] && x < cut[2] && y >= cut[1] && y < cut[3];
				int in = inq && (!sc || (x >= sx && x < sx + sw && y >= sy && y < sy + sh));
				unsigned a = px[(y * W + x) * 4 + 3];
				if (in && a != 0) { bin[y / 128][x / 128]++; left++; }
				if (!inq && a != 255) outside++;
			}
		printf("cutout run %d (quad %g,%g-%g,%g%s): opaque pixels left inside %d, changed outside %d%s\n", r,
		       cut[0], cut[1], cut[2], cut[3], sc ? ", scissored" : "", left, outside, left || outside ? "  <-- WRONG" : "");
		for (int by = 0; by < 4 && left; by++) {
			printf("  bins y %3d:", by * 128);
			for (int bx = 0; bx < 8; bx++) printf(" %6d", bin[by][bx]);
			printf("\n");
		}
		fails += left || outside;
	}
	free(px);
	return fails != 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: fdtri instances [N…] | fdtri instattr [N…] | fdtri cutout [repeat] [opaque-first] [x0 y0 x1 y1 [sx sy sw sh]]\n"); return 2; }
	init_gl();
	if (!strcmp(argv[1], "instances")) return test_instances(argc - 2, argv + 2);
	if (!strcmp(argv[1], "instattr")) return test_instattr(argc - 2, argv + 2);
	if (!strcmp(argv[1], "cutout")) return test_cutout(argc - 2, argv + 2);
	return 2;
}
