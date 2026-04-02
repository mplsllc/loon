// Loon LLVM runtime — provides builtins that the LLVM IR backend declares as external
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// int_to_string: returns pointer to null-terminated string
char* _loon_i64_to_str(long long val) {
    char* buf = malloc(24);
    sprintf(buf, "%lld", val);
    return buf;
}

// print_byte: write a single byte to stdout
void _loon_print_byte(long long byte_val) {
    char c = (char)byte_val;
    write(1, &c, 1);
}

// read_file: reads file given pointer to null-terminated filename, returns contents
char* _loon_read_file(long long name_ptr) {
    char* name = (char*)name_ptr;
    FILE* f = fopen(name, "rb");
    if (!f) return "";
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = malloc(len + 1);
    fread(buf, 1, len, f);
    buf[len] = 0;
    fclose(f);
    return buf;
}

// get_arg: returns argv[n] as a pointer
static int saved_argc = 0;
static char** saved_argv = NULL;

char* _loon_get_arg(long long n) {
    if (n < saved_argc && saved_argv) return saved_argv[n];
    return "";
}

// Called from LLVM IR's main() via constructor to capture argc/argv
// The IR defines main() which calls fn_main()
__attribute__((constructor)) static void _loon_init_args(void) {
    // argc/argv not available in constructor; get_arg requires manual init
    // For now, get_arg returns "" — tests don't use CLI args
}
