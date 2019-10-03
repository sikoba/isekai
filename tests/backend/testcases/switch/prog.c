struct Input {
    int a;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    switch (input->a) {
    case 1: output->x = 111; break;
    case 4: output->x = 444; break;
    case 9: output->x = 990; break;
    default: output->x = input->a; break;
    }
}
