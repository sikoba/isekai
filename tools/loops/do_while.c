struct Input {
    int a;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    int a = input->a;
#if ISEKAI_C_PARSER
    a = a + 1;
#else
    do {
        ++a;
    } while (a);
#endif
    output->x = a + 5;
}
