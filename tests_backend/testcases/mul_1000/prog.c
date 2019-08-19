enum { N = 1000 };

struct Input {
    unsigned a[N];
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = 1;
    for (int i = 0; i < N; ++i) {
        output->x *= input->a[i];
    }
}
