#if ISEKAI_C_PARSER
struct Input {
    int a_0, a_1, a_2, a_3, a_4;
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
    if (i < 2) {
        if (i == 0) {
            x = input->a_0;
        } else {
            x = input->a_1;
        }
    } else {
        if (i == 2) {
            x = input->a_2;
        } else if (i == 3) {
            x = input->a_3;
        } else {
            x = input->a_4;
        }
    }
    output->x = x;
}

#else
struct Input {
    int a[5];
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
