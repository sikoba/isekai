struct Input {
    int a;
    int b;
    int c;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a != 25 ? input->b : input->c;
}
