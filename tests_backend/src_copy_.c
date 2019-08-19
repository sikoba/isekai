struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    (void) input;
    unsigned char c = 255;
    output->x = c;
}
