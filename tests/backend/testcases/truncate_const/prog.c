struct Input {
    unsigned a;
};

struct Output {
    unsigned short x;
};

void outsource(struct Input *input, struct Output *output)
{
    (void) input;
    unsigned u = 4294967291u;
    output->x = u;
}
