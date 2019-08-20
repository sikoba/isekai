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
    if (input->a) {
        output->x = input->b;
    } else {
        output->x = input->c;
    }
}
