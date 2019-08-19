#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

static const char *RANDOM_SOURCE = "/dev/urandom";

int main(int argc, char **argv)
{
    unsigned n;
    if (argc != 2 || sscanf(argv[1], "%u", &n) != 1) {
        fprintf(stderr, "USAGE: rng <number>\n");
        return 2;
    }

    FILE *f = fopen(RANDOM_SOURCE, "r");
    if (!f) {
        perror(RANDOM_SOURCE);
        return 1;
    }
    for (unsigned i = 0; i < n; ++i) {
        int v;
        if (fread(&v, sizeof(v), 1, f) != 1) {
            fprintf(stderr, "I/O error or truncated read from %s.\n", RANDOM_SOURCE);
            return 1;
        }
        printf("%d\n", v);
    }
}
