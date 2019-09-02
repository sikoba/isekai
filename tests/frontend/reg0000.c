// Regression test

struct Input {
#if ISEKAI_C_PARSER
    int a_0, a_1, a_2, a_3, a_4, a_5, a_6, a_7, a_8, a_9, a_10;
#else
    int a[11];
#endif
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    output->x = input->a_0;
#else
    int *n = (&(input->a))[1];
    output->x = *n;
#endif
}
