struct Input {
    int a;
    int b;
    int c;
    int d;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct Output *output)
{
    output->x = input->a ^ (input->b | (input->c & input->d));
    output->x = output->x << 2;
}
