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
    int _unroll = 22;
#else
    extern void _unroll_hint(unsigned);
    _unroll_hint(22);
#endif

    for (int i = 0; i != 22; i = i + 1) {
        a = a | (a + 1);
    }

    output->x = a + 5;
}
