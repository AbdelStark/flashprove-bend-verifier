// Execute the verifier installed beside this binary, preserving the checked argv.
#include <limits.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

static Term backend_exec(Env env, Term *fields, IoWork *work) {
  char resolved[PATH_MAX];
#ifdef __APPLE__
  char executable[PATH_MAX];
  uint32_t capacity = sizeof executable;
  if (_NSGetExecutablePath(executable, &capacity) != 0)
    return io_fail(env, ENAMETOOLONG, "cannot locate the running verifier");
#else
  const char *executable = "/proc/self/exe";
#endif
  if (!realpath(executable, resolved))
    return io_fail(env, errno, "cannot locate the running verifier");
  char *base = strrchr(resolved, '/');
  if (!base || sizeof resolved - (size_t)(base + 1 - resolved) < sizeof "bend_verify")
    return io_fail(env, ENAMETOOLONG, "cannot locate the sibling bend_verify");
  memcpy(base + 1, "bend_verify", sizeof "bend_verify");

  // IO.args decodes UTF-8. Require the raw argv handed to the worker to
  // round-trip, so a different filename cannot replace one checked in Bend.
  for (int i = 1; i < io_argc; ++i) {
    size_t size = strlen(io_argv[i]);
    u64 decoded_size;
    char *decoded = io_cstr(env, io_str(env, io_argv[i], size), &decoded_size);
    bool same = decoded_size == size && memcmp(decoded, io_argv[i], size) == 0;
    free(decoded);
    if (!same) return io_fail(env, EINVAL, "verify requires UTF-8 arguments");
  }
  io_argv[0] = resolved;
  io_argv[io_argc] = NULL;
  execv(resolved, io_argv);
  return io_fail(env, errno, "cannot execute the sibling bend_verify");
}

static void __attribute__((constructor)) register_backend_exec(void) {
  io_eff(CID(Backend.exec), backend_exec);
}
