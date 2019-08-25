struct Input { int a; int b; };
struct Output { int x; };
void outsource(struct Input *in, struct Output *out)
{ out->x = (in->a - in->b) == 1; }
