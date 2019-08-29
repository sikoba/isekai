enum { NINPUT = 6 };

#define SIZE NINPUT

#define MAT(m, r, c)	(m)[(r)*SIZE+(c)]

struct Input {
	int v[SIZE];
};

struct Output {
	int r[SIZE];
};

void outsource(struct Input *input, struct Output *output)
{
#include "random_data.c"
	int i, j, k;
	int t;
	for (i=0; i<SIZE; i+=1)
	{
		t = 0;
		for (k=0; k<SIZE; k+=1)
		{
			t = t + MAT(data, i, k) * input->v[k];
		}
		output->r[i] = t;
	}
}
