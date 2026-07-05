#include <string.h>

#if defined(_WIN32)
#define POLYCALL_EXPORT __declspec(dllexport)
#else
#define POLYCALL_EXPORT __attribute__((visibility("default")))
#endif

POLYCALL_EXPORT int polycall_ffi_run_config(
    const char *config_path,
    int validate
) {
    if (validate != 1) {
        return 92;
    }
    if (config_path && strcmp(config_path, "__status_37__") == 0) {
        return 37;
    }
    return 0;
}
