enum { N = 1000 };

struct Input {
    unsigned a[N];
};

struct Output {
    unsigned x;
};

void outsource(struct Input *input, struct Output *output)
{
    output->x = input->a[0];
    for (int i = 1; i < N; ++i) {
        output->x -= input->a[i];
    }
}
