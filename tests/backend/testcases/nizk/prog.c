struct Input {
    unsigned a;
    unsigned b;
    unsigned c;
};

struct NzikInput {
    unsigned d;
    unsigned e;
};

struct Output {
    unsigned x;
};

void
outsource(struct Input *input, struct NzikInput *nizk_input, struct Output *output)
{
    output->x = 4 + input->a + input->b + input->c + nizk_input->d + nizk_input->e;
}
