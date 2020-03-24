#include <stdint.h>

struct Input {
    uint64_t x;
    uint64_t y;
};

struct Output {
    uint64_t a;
    uint64_t b;
    uint64_t c;
    uint64_t d;
};

void outsource(struct Input *in, struct Output *out)
{
    out->a = in->x / in->y;
    out->b = in->x % in->y;
    out->c = ((int64_t) in->x) / ((int64_t) in->y);
    out->d = ((int64_t) in->x) % ((int64_t) in->y);
}
