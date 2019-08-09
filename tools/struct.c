struct Input {
    int a;
    int b;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
#if ISEKAI_C_PARSER
    output->x = 15 + input->a + input->b;
#else
    struct {
        struct {
            int p;
        } q[10];
        int r;
    } tmp;
    tmp.q[0].p = 15;
    tmp.q[4].p = input->a;
    tmp.r = input->b;
    output->x = tmp.q[0].p + tmp.q[4].p + tmp.r;
#endif
}
