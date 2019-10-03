#if ISEKAI_C_PARSER
struct Input {
    int i;
};

struct Output {
    int a_0;
};

void
outsource(struct Input *input, struct Output *output)
{
    output->a_0 = 999;
}

#else
struct Input {
    long i;
};

struct Output {
    int a[1];
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
