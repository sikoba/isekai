struct Input {
    int a;
    int b;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a > input->b;
}
