struct Input {
    int a;
};

struct Output {
    int x;
    int y;
};

void outsource(struct Input *input, struct Output *output)
{
    int p = -1 + 1;
    int q = 1234 + 5678;
    output->x = p ? 22 : 33;
    output->y = q ? 44 : 55;
    output->x += input->a;
}
