//
//  PlayRedirect.c
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <unistd.h>
#include <crt_externs.h>

static int matches_game(const char *path) {
    const char *expected = getenv("MNM_PLAY_GAME");
    const char *bridge = getenv("MNM_PLAY_BRIDGE");
    char actual_path[PATH_MAX], expected_path[PATH_MAX];
    if (!path || !expected || !bridge || bridge[0] != '/' || access(bridge, X_OK)) return 0;
    return realpath(path, actual_path) && realpath(expected, expected_path) && !strcmp(actual_path, expected_path);
}

static int redirected_spawn(pid_t *pid, const posix_spawn_file_actions_t *actions,
                            const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
    const char *bridge = getenv("MNM_PLAY_BRIDGE");
    const char *game = getenv("MNM_PLAY_GAME");
    if (!argv || !argv[0] || !argv[1] || strcmp(argv[1], "--token") || !argv[2] || argv[3]) return EINVAL;
    char *const replacement[] = {(char *)bridge, "--from-patcher", (char *)game, "--token", argv[2], NULL};
    char *const *environment = envp ? envp : *_NSGetEnviron();
    size_t count = 0;
    while (environment[count]) { if (++count > 4096) return E2BIG; }
    char *clean[count + 1];
    size_t kept = 0;
    for (size_t i = 0; i < count; i++) {
        if (!strncmp(environment[i], "DYLD_INSERT_LIBRARIES=", 22) || !strncmp(environment[i], "MNM_PLAY_", 9)) continue;
        clean[kept++] = environment[i];
    }
    clean[kept] = NULL;
    return posix_spawn(pid, bridge, actions, attributes, replacement, clean);
}

static int mnm_spawnp(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                      const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
    if (matches_game(path)) return redirected_spawn(pid, actions, attributes, argv, envp);
    return posix_spawnp(pid, path, actions, attributes, argv, envp);
}
static int mnm_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                     const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
    if (matches_game(path)) return redirected_spawn(pid, actions, attributes, argv, envp);
    return posix_spawn(pid, path, actions, attributes, argv, envp);
}

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *replacement; const void *original; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = { (const void *)replacement, (const void *)original }
INTERPOSE(mnm_spawnp, posix_spawnp);
INTERPOSE(mnm_spawn, posix_spawn);
