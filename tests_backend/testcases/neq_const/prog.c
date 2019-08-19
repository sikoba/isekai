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
    if (input->a != 25)
        output->x = input->b;
    else
        output->x = input->c;
}
