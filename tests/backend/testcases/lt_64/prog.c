#include <stdint.h>

struct Input {
    uint64_t a;
    uint64_t b;
    uint64_t c;
    uint64_t d;
};

struct Output {
    uint64_t x;
};

void outsource(struct Input *input, struct Output *output)
{
    if (input->a < input->b)
        output->x = input->c;
    else
        output->x = input->d;
}
