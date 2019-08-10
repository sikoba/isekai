#if ISEKAI_C_PARSER
struct Input {
    int arr_0, arr_1, arr_2;
};

struct Output {
    int arr_0;
};

void
outsource(struct Input *input, struct Output *output)
{
    output->arr_0 = input->arr_1 + input->arr_0 + input->arr_2;
}

#else
struct Input {
    int arr[3];
};

struct Output {
    int arr[1];
};

void
outsource(struct Input *input, struct Output *output)
{
    struct {
        struct {
            int p;
        } q[10];
        int r;
    } tmp;
    tmp.q[0].p = input->arr[1];
    tmp.q[4].p = input->arr[0];
    tmp.r = input->arr[2];
    output->arr[0] = tmp.q[0].p + tmp.q[4].p + tmp.r;
}
#endif
