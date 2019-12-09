#include "nagai.h"

struct Input {
    uint64_t a;
};

struct Output {
    uint64_t x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = nagai_lowbits(
        nagai_exp(
            nagai_init_pos(input->a),
            nagai_init_from_str("41"),
            /*limit=*/ 7
        )
    );
}
