class Thing {
    unsigned val_;
public:
    __attribute__((always_inline)) Thing() : val_{123} {}
    __attribute__((always_inline)) unsigned value() const { return val_; }
};

struct Input {
    unsigned a;
};

struct Output {
    unsigned x;
};

extern "C" {
    void outsource(struct Input *in, struct Output *out);
};

void outsource(struct Input *in, struct Output *out)
{
    Thing arr[100];
    out->x = arr[99].value() + in->a;
}
