struct Input {
    int a;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    int a = input->a;
#if ISEKAI_C_PARSER

#   include "loop.h"

#   define BEGIN    a = a + 1; if (a != 48) {
#   define END      }

    REP_99(BEGIN)
    REP_99(END)

#else
    extern void _unroll_hint(unsigned);
    _unroll_hint(98);

    do {
        ++a;
    } while (a != 48);
#endif
    output->x = a + 5;
}
