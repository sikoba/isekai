#include "common.hpp"
#include <random>
#include <stdio.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "USAGE: rng <number>\n");
        return 2;
    }
    unsigned n;
    parse_uint_until_nul(argv[1], n, /*base=*/10);

    std::random_device rd;
    for (unsigned i = 0; i < n; ++i) {
        printf("%d\n", (int) rd());
    }
}
