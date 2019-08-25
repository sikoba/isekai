struct Input { unsigned a; };
struct Output { unsigned x; };
void outsource(struct Input *input, struct Output *output)
{ output->x = 25 < input->a; }
