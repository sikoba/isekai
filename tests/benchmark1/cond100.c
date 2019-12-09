
struct Input {
    int a[100];
	int b[100];
	
};

struct Output {
    int x;
};

static inline __attribute__((always_inline)) int compute(int a[],int b[], int n) {
    int result = 0;
	for(int i = 0;i < n-1;i++) 
	{
		if (b[i] < n/2)
			result *= a[b[i]];
		else
			result += a[b[i]];
	}
	return result;
   
}


void outsource(struct Input *input, struct Output *output)
{
    int n=sizeof(input->a) / sizeof(input->a[0]);

    output->x = compute(input->a, input->b, n);
}
