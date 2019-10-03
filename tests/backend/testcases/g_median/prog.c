
struct Input {
    int a[11];

	
};

struct Output {
    int x;
};

static inline __attribute__((always_inline)) void swap(int *p,int *q) {
   int t;
   
   t=*p; 
   *p=*q; 
   *q=t;
}

static inline __attribute__((always_inline)) void sort(int a[],int n) { 
   int i,j;

   for(i = 0;i < n-1;i++) {
      for(j = 0;j < n-i-1;j++) {
         if(a[j] > a[j+1])
		 {
			 swap(&a[j],&a[j+1]);
		 }
      }
   }
}

void outsource(struct Input *input, struct Output *output)
{
    int n=sizeof(input->a) / sizeof(input->a[0]);

	sort(input->a,n);
		
    output->x = input->a[n/2];
}
