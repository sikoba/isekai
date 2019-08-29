struct Input {
    unsigned a;
    unsigned b;
    unsigned c;
    unsigned d;
};

struct Output {
    unsigned x;
};

void
outsource(struct Input *input, struct Output *output)
{
    output->x = (input->a < 3)
              + (input->b <= 3)
              + (input->c > 3)
              + (input->d >= 3);
}
