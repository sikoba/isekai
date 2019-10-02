#if ISEKAI_C_PARSER
struct Input {
    int i;
};

struct Output {
    int a_0, a_1, a_2, a_3, a_4;
};

void
outsource(struct Input *input, struct Output *output)
{
    output->a_0 = 0;
    output->a_1 = 1;
    output->a_2 = 2;
    output->a_3 = 3;
    output->a_4 = 4;

    if (input->i == 0) output->a_0 = 999;
    if (input->i == 1) output->a_1 = 999;
    if (input->i == 2) output->a_2 = 999;
    if (input->i == 3) output->a_3 = 999;
    if (input->i == 4) output->a_4 = 999;
}

#else
struct Input {
    long i;
};

struct Output {
    int a[5];
};

void
outsource(struct Input *input, struct Output *output)
{
    for (int i = 0; i < 5; ++i) {
        output->a[i] = i;
    }
    output->a[input->i] = 999;
}
#endif
