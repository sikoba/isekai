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
    output->x = input->a < 25 ? input->b : input->c;
}
