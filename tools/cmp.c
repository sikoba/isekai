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
    output->x = (input->a < 3)
              + (input->b <= 3)
              + (input->c > 3)
              + (input->d >= 3);
}
