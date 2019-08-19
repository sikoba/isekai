struct Input {
    int a;
    int b;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    output->x = input->a * 28 + 28;
#else
    int *pa = &input->a;
    int *px = &output->x;
    int i;
    int *pi = &i;
    *pi = 28;
    *px = *pa * i + *pi;
#endif
}
