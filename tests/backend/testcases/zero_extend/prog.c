struct Input {
    unsigned short a;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = 2 * input->a + 1;
}
