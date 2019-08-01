struct Input {
    int a;
    int i;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    int a = input->a;

#if ISEKAI_C_PARSER
    int i = input->i;
#   include "repeat.h"

#   define BEGIN    if (i != 128) { a = a + a; i = i + 1;
#   define END      }

    REP_10(BEGIN)
    REP_10(END)

#else
     extern void _unroll_hint(unsigned);
    _unroll_hint(10);

    for (int i = input->i; i != 128; ++i) {
        a += a;
    }
#endif
    output->x = a + 5;
}
