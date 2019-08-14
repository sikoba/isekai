struct Input {
    int a;
    int b;
    int c;
};

struct Output {
    int x;
    int y;
    int z;
};

void outsource(struct Input *input, struct Output *output)
{
    output->z = 97;
    int x = input->a;
    if (input->b == 4) {
        if (input->a == 6) {
            if (input->c == 8) {
                x = x - 2;
                output->z = x == 88;
            }
        }
    }
    int y = input->b;
    if (x == 12) {
        if (y == 128) {
            x = x + 5;
        } else {
            y = y * 5;
        }
    } else {
        if (y == 128) {
            x = x | 5;
        } else {
            y = y - 5;
        }
    }
    output->x = x & y;
    output->y = output->x | 23;
    output->y = output->y + 3;
}
