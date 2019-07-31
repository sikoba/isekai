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
        output->x = input->b;
    } else {
        output->x = input->c;
    }
#else
    output->x = input->a ? input->b : input->c;
#endif
}
