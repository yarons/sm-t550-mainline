#version 100
#define COSITED
#extension GL_OES_EGL_image_external: enable
#define RAW10P
/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Based on the code from http://jgt.akpeters.com/papers/McGuire08/
 *
 * Efficient, High-Quality Bayer Demosaic Filtering on GPUs
 *
 * Morgan McGuire
 *
 * This paper appears in issue Volume 13, Number 4.
 * ---------------------------------------------------------
 * Copyright (c) 2008, Morgan McGuire. All rights reserved.
 *
 *
 * Modified by Linaro Ltd for 10/12-bit packed vs 8-bit raw Bayer format,
 * and for simpler demosaic algorithm.
 * Copyright (C) 2020, Linaro
 *
 * bayer_1x_packed.frag - Fragment shader code for raw Bayer 10-bit and 12-bit
 * packed formats
 */

#ifdef GL_ES
precision highp float;
#endif

/*
 * These constants are used to select the bytes containing the HS part of
 * the pixel value:
 * BPP - bytes per pixel,
 * THRESHOLD_L = fract(BPP) * 0.5 + 0.02
 * THRESHOLD_H = 1.0 - fract(BPP) * 1.5 + 0.02
 * Let X is the x coordinate in the texture measured in bytes (so that the
 * range is from 0 to (stride_-1)) aligned on the nearest pixel.
 * E.g. for RAW10P:
 * -------------+-------------------+-------------------+--
 *  pixel No    |  0   1    2   3   |  4   5    6   7   | ...
 * -------------+-------------------+-------------------+--
 *  byte offset | 0   1   2   3   4 | 5   6   7   8   9 | ...
 * -------------+-------------------+-------------------+--
 *      X       | 0.0 1.25 2.5 3.75 | 5.0 6.25 7.5 8.75 | ...
 * -------------+-------------------+-------------------+--
 * If fract(X) < THRESHOLD_L then the previous byte contains the LS
 * bits of the pixel values and needs to be skipped.
 * If fract(X) > THRESHOLD_H then the next byte contains the LS bits
 * of the pixel values and needs to be skipped.
 */
#if defined(RAW10P)
#define BPP		1.25
#define THRESHOLD_L	0.14
#define THRESHOLD_H	0.64
#elif defined(RAW12P)
#define BPP		1.5
#define THRESHOLD_L	0.27
#define THRESHOLD_H	0.27
#else
#error Invalid raw format
#endif


varying vec2 textureOut;

/* the texture size in pixels */
uniform vec2 tex_size;
uniform vec2 tex_step;
uniform vec2 tex_bayer_first_red;

uniform sampler2D tex_y;
uniform vec3 awb;
uniform mat3 ccm;
uniform vec3 blacklevel;
uniform float gamma;
uniform float contrastExp;

#if defined (QUAD_BAYER)
vec2 quad_cell(vec2 pixel)
{
	return clamp(floor(pixel / 2.0) * 2.0, vec2(0.0), tex_size - vec2(2.0));
}

float quad_fetch(vec2 pixel)
{
	vec2 cell = quad_cell(pixel);
	vec2 byte_pos = vec2(floor(BPP * cell.x + 0.02), cell.y) * tex_step;
	vec2 byte_pos_x1 = vec2(floor(BPP * (cell.x + 1.0) + 0.02), cell.y) * tex_step;
	vec2 byte_pos_y1 = byte_pos + vec2(0.0, tex_step.y);
	vec2 byte_pos_xy1 = vec2(byte_pos_x1.x, byte_pos_y1.y);
	return (texture2D(tex_y, byte_pos).r +
		texture2D(tex_y, byte_pos_x1).r +
		texture2D(tex_y, byte_pos_y1).r +
		texture2D(tex_y, byte_pos_xy1).r) * 0.25;
}
#endif

float apply_contrast(float value)
{
	// Apply simple S-curve
	if (value < 0.5)
		return 0.5 * pow(value / 0.5, contrastExp);
	else
		return 1.0 - 0.5 * pow((1.0 - value) / 0.5, contrastExp);
}

void main(void)
{
	vec4 cell = texture2D(tex_y, textureOut);
	gl_FragColor = vec4(cell.rgb, 1.0);
}
