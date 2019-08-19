struct Input {
    unsigned short a;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a;
}
