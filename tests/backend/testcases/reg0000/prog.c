struct Input {
    unsigned a;
    unsigned b;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *in, struct Output *out)
{
    out->x = in->a + in->b / in->b;
}
