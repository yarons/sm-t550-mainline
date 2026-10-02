#!/bin/sh
# RetroArch may be installed after gt510-tweaks (image builds): re-apply its defaults then.
/usr/libexec/gt510-retroarch-defaults
# postmarketos-release upgrades restore its os-release/issue (both under the watched /usr/lib or written with it):
# re-apply the unofficial-build name.
/usr/libexec/gt510-rebrand >/dev/null
exit 0
