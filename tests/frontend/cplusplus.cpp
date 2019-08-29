#if ISEKAI_C_PARSER
struct Input { int a; int b; int c; };
struct Output { int x; };
void outsource(struct Input *input, struct Output *output)
{ output->x = input->a + input->b + input->c + 9999; }
#else

#define INLINE __attribute__((always_inline))

class Input
{
private:
    int a;
    int b;
    int c;
public:
    INLINE int calc_sum() const
    {
        return a + b + c;
    }
};

class Output
{
private:
    int x;
public:
    INLINE void set_x(int value)
    {
        x = value;
    }
};

extern "C" {
    void outsource(Input *, Output *);
    extern void _unroll_hint(unsigned);
};

void outsource(Input *input, Output *output)
{
    _unroll_hint(1'000'000'000); // C++14 digit separators
    for (int i = 0; i < 10'000; ++i) {
        output->set_x(input->calc_sum() + i);
    }
}

#endif // ISEKAI_C_PARSER
