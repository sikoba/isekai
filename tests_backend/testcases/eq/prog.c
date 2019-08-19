struct Input {
    unsigned a;
    unsigned b;
    unsigned c;
    unsigned d;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = ((input->a + 1) == (input->b + 2)) ? input->c : input->d;
}
