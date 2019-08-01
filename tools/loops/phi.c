struct Input { int a; int b; };
struct Output { int x; };

void outsource(struct Input *input, struct Output *output)
{
    int a = input->a;
    int b = input->b;
#if ISEKAI_C_PARSER

#   include "repeat.h"

#   define BEGIN   int tmp_ = 0; \
                   if (a != 77) { \
                       tmp_ = (b != 128); \
                       b = b + 1; \
                   } \
                   if (tmp_) { \
                       a = a + 1;

#   define END     }

    REP_10(BEGIN)
    REP_10(END)

#else
    extern void _unroll_hint(unsigned);
    _unroll_hint(10);

    while (a != 77 && b++ != 128) {
        a++;
    }
#endif
    output->x = a;
}
