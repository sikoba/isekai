#include "field.hpp"

struct Input {
    uint64_t a;
    uint64_t b;
};

struct Output {
    uint64_t x;
};

extern "C" {
    void outsource(struct Input *, struct Output *);
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = static_cast<uint64_t>(
        Field(input->b).raise_to(input->a, /*limit=*/ 7)
    );
}
