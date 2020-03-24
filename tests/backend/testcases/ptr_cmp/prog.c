struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
};

static inline __attribute__((always_inline))
void f(unsigned *p, unsigned x)
{
    *p = x + 123;
}

void outsource(struct Input *in, struct Output *out)
{
    enum { N = 100 };
    unsigned arr[N];
    unsigned *ptr = arr;
    unsigned *end = arr + N;
    unsigned x = 1;
    do {
        f(ptr, x);
        ++ptr;
        x *= in->a;
    } while (ptr != end);
    out->x = arr[N - 1];
}
