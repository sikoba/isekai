struct Input {
    short a;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a;
}
