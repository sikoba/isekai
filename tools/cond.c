struct Input {
    int a;
    int b;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    int x = input->a;
    if (input->b == 4) {
        if (input->a == 6) {
            x = x - 2;
        } else {
            x = x + 18;
        }
    } else {
        if (input->a == 6) {
            x = x * 148;
        } else {
            x = x | 256;
        }
    }
    output->x = x * input->b;
}
