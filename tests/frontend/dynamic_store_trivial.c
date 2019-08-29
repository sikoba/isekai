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

#define NELEMS(arr) (sizeof(arr) / sizeof((arr)[0]))

void
outsource(struct Input *input, struct Output *output)
{
    for (int i = 0; i < NELEMS(output->a); ++i) {
        output->a[i] = i;
    }
    output->a[input->i] = 999;
}
#endif
