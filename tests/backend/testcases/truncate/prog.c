struct Input {
    unsigned a;
};

struct Output {
    unsigned short x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a;
}
