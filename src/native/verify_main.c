// Pass only the verifier's -j option to the scheduler. Keep all caller paths,
// configuration values and raw +RTS tokens outside Bend's runtime grammar.
#define main bend_main
#include "verify_generated.c"
#undef main

int main(int argc, char **argv) {
  char **args = calloc((size_t)argc + 6, sizeof(*args));
  if (!args || unsetenv("BENDRTS") != 0) {
    perror("verify-bend");
    return 2;
  }
  const char *threads = NULL;
  // Reserve space ahead of the verifier arguments for a trusted runtime prefix.
  int used = 5;
  for (int i = 1; i < argc; i++) {
    if (i >= 6 && strcmp(argv[i], "-j") == 0) {
      const char *value = ++i < argc ? argv[i] : "";
      long count = strtol(value, NULL, 10);
      if (value[strspn(value, "0123456789")] || count < 1 || count > CUBE_T) {
        fprintf(stderr, "verify-bend: -j expects a worker count from 1 to %d\n", CUBE_T);
        free(args);
        return 2;
      }
      threads = value;
    } else {
      args[used++] = argv[i];
      if (i >= 6 && i + 1 < argc && (!strcmp(argv[i], "-id") ||
          !strcmp(argv[i], "-policy") || !strcmp(argv[i], "-data"))) {
        args[used++] = argv[++i];
      }
    }
  }
  int start = threads ? 0 : 3;
  args[start] = argv[0];
  if (threads) {
    args[1] = "+RTS";
    args[2] = "--threads";
    args[3] = (char *)threads;
  }
  args[4] = "--RTS";
  int status = bend_main(used - start, args + start);
  free(args);
  return status;
}
