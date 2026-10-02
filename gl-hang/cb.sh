#!/bin/sh
# camerabin like Aperture: wrappercamerabinsrc + pipewiresrc, viewfinder = gtk4paintablesink
N=libcamera_input._base_soc_0_cci_1b0c000_i2c-bus_0_camera_28
case "$1" in
cb) exec gst-launch-1.0 camerabin mode=1 \
	camera-source="wrappercamerabinsrc video-source=\"pipewiresrc target-object=$N\"" \
	viewfinder-sink="gtk4paintablesink sync=false" ;;
cbsrc) exec gst-launch-1.0 wrappercamerabinsrc video-source="pipewiresrc target-object=$N" name=s \
	s.vfsrc ! gtk4paintablesink sync=false ;;
esac
