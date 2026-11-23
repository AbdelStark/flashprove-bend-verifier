// Keep all user arguments in the verifier grammar. The Bend runtime otherwise
// handles +RTS --help before running main, including options set by BENDRTS.
#define main bend_main
#include "verify_generated.c"
#undef main

int main(int argc, char **argv) {
  char **args = calloc((size_t)argc + 2, sizeof(*args));
  if (!args || unsetenv("BENDRTS") != 0) {
    perror("verify");
    return 2;
  }
  args[0] = argv[0];
  args[1] = "--RTS";
  memcpy(args + 2, argv + 1, (size_t)argc * sizeof(*args));
  int status = bend_main(argc + 1, args);
  free(args);
  return status;
}
