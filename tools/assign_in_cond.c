struct Input {
    int a;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    output->x = input->a;
    if (output->x == 0) {
        output->x = 58;
    }
#else
    if ((output->x = input->a) == 0) {
        output->x = 58;
    }
#endif
}
