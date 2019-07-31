struct Input {
    int a;
    int b;
    int c;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    if (input->a != 0) {
        output->x = 2;
    } else {
        output->x = 3;
    }
#else
    output->x = input->a ? 2 : 3;
#endif
}
