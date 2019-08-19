struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    if (25) {
        output->x = input->a + 8;
    } else {
        output->x = input->a * 9;
    }
}
