struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
};

void
outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    int a = 33;
    int b = 44;
    if (input->a > 10) {
        a = 22;
    } else {
        b = 22;
    }
    output->x = a + b;
#else
    int a = 33;
    int b = 44;
    int *p;
    if (input->a > 10) {
        p = &a;
    } else {
        p = &b;
    }
    *p = 22;
    output->x = a + b;
#endif
}
