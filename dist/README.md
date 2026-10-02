# Build output

The packages contain portable Ruby source. Native libpolycall binaries are
platform-specific and are not bundled: install the Polycall core
(https://github.com/obinexus/polycall, >= 1.1.0) and point `POLYCALL_LIBRARY`
at it, or put it on the system library search path.
