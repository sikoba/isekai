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
    if ((input->a + 1) == (input->b + 2))
        output->x = input->c;
    else
        output->x = input->d;
}
