struct Input {
    int a;
    int b;
    int c;
};

struct NizkInput {
    int d;
    int e;
};

struct Output {
    int x;
};

void
outsource(struct Input *input, struct NizkInput *nizk, struct Output *output)
{
    output->x = input->a + input->b + input->c + nizk->d + nizk->e;
}
