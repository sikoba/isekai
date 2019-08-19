struct Input {
    unsigned a;
    unsigned b;
    unsigned c;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a - input->b - input->c;
}
