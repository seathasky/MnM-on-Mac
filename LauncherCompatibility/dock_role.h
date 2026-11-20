#ifndef MNM_DOCK_ROLE_H
#define MNM_DOCK_ROLE_H

#include <strings.h>

static inline const char *mnm_dock_role(int launcher, int game, int argc, char *const *argv) {
    for (int index = 0; index < argc && index < 3; ++index) {
        const char *name = argv[index];
        if (!name) continue;
        for (const char *cursor = name; *cursor; ++cursor) {
            if (*cursor == '/' || *cursor == '\\') name = cursor + 1;
        }
        if (launcher && !strcasecmp(name, "mnm_launcher.exe")) return "L";
        if (game && !strcasecmp(name, "mnm.exe")) return "G";
    }
    return 0;
}

#endif
