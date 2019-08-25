#if ISEKAI_C_PARSER
struct Input {
    int a_0, a_1, a_2;
    int i;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    int i = input->i;
    int x = 0;

    if (i == 0) {
        x = input->a_0;
    } else if (i == 1) {
        x = input->a_1;
    } else {
        x = input->a_2;
    }
    output->x = x;
}

#else
struct Input {
    int a[3];
    long i;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    output->x = input->a[input->i];
}
#endif
