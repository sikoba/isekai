struct Input {
    int a;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    (void) input;
    signed short c = -2;
    output->x = c;
}
