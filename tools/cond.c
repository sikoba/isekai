struct Input {
    int a;
    int b;
    int c;
};

struct Output {
    int x;
};

void outsource(struct Input *input, struct Output *output)
{
    int x = input->a;
    if (input->b == 4) {
        if (input->a == 6) {
            if (input->c == 8) {
                x = x - 2;
            }
        }
    }
    int y = input->b;
    if (x == 12) {
        if (y == 128) {
            x = x - 5;
        } else {
            y = y - 5;
        }
    } else {
        if (y == 128) {
            x = x - 50;
        } else {
            y = y - 50;
        }
    }
    output->x = x * y;
}
