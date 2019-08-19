struct Input {
    int a;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    if (input->a > 10) {
        output->x = input->a;
    } else {
        output->x = 0;
    }
#else
    // If input->a <= 10, the C standard says the behavior is undefined.
    int *p;
    if (input->a > 10) {
        p = &input->a;
    }
    output->x = *p;
#endif
}
