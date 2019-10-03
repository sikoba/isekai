struct Input {
    int a;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    int v = 25;
    switch (v) {
    case 1: output->x = 22; break;
    case 4: output->x = 77; break;
    case 9: output->x = 99; break;
    default: output->x = input->a; break;
    }
}
