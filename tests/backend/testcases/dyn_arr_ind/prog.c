struct Input {
    int i1;
    int i2;
    int arr[100];
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    int *p = input->arr + input->i1;
    output->x = p[input->i2];
}
