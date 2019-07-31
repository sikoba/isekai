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
    // do nothing
#else
    for (int i = 0; i != 4; ++i) {
        a += a;
    }
#endif
    output->x = a + 5;
}
