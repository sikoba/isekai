struct Input {
    int a;
    int b;
    int c;
};

struct NzikInput {
    int d;
    int e;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct NzikInput *nizk, struct Output *output)
{
    output->x = 4 + input->a + input->b + input->c + nizk->d + nizk->e;
}
