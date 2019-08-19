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
    output->x = 25 != (input->a + 1) ? input->b : input->c;
}
