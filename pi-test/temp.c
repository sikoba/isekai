enum { NINPUT = 3 };

#define IMAGE_W (NINPUT+2)
#define IMAGE_H (NINPUT+2)
#define KERNEL_W NINPUT
#define KERNEL_H NINPUT

struct Point { unsigned x; unsigned y; };

#define IMAGE_PIXEL(im,p0,p1)	(im[((p0)->y+(p1)->y)*IMAGE_H+((p0)->x+(p1)->x)])
#define KERNEL_PIXEL(ke,p)		(ke[(p)->y*KERNEL_H+(p)->x])

struct Input {
    unsigned kernel[KERNEL_H*KERNEL_W];
};

struct Output {
    unsigned min_loc_x, min_loc_y;
    unsigned min_delta;
};

__attribute__((always_inline)) static unsigned diff(unsigned *image, unsigned* kernel, struct Point* ip)
{
	struct Point kp;
	unsigned total_diff = 0;
	for (kp.y = 0; kp.y < KERNEL_H; kp.y+=1)
	{
		for (kp.x = 0; kp.x < KERNEL_W; kp.x+=1)
		{
			unsigned image_pixel = IMAGE_PIXEL(image, ip, &kp);
			unsigned kernel_pixel = KERNEL_PIXEL(kernel, &kp);
            unsigned local_diff = (image_pixel - kernel_pixel) & 1;
            total_diff += local_diff;
//			printf("  kp %d,%d: ld %d total=>%d\n",
//				kp.x, kp.y, local_diff, total_diff);
		}
	}
	return total_diff;
}

void outsource(struct Input *in, struct Output *out)
{
#include "random_data.c"
    unsigned *image = (unsigned *) data;

    struct Point min_loc;
    min_loc.x = 0;
    min_loc.y = 0;
    unsigned min_delta = diff(image, in->kernel, &min_loc);

	struct Point ip;
	for (ip.y=0; ip.y < IMAGE_H - KERNEL_H + 1; ip.y+=1)
	{
		for (ip.x=0; ip.x < IMAGE_W - KERNEL_W + 1; ip.x+=1)
		{
			unsigned delta;
			delta = diff(image, in->kernel, &ip);
#ifdef QSP_TEST
//			printf("At %d,%d: %d\n", ip.x, ip.y, delta);
#endif
			if (delta < min_delta)
			{
				min_loc.x = ip.x;
				min_loc.y = ip.y;
				min_delta = delta;
			}
		}
	}

    out->min_loc_x = min_loc.x;
    out->min_loc_y = min_loc.y;
    out->min_delta = min_delta;
}
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

static uint64_t test_read(void)
{
    static unsigned next_index = 0;
    unsigned i;
    unsigned long v;
    if (scanf("%u %lx", &i, &v) != 2) {
        fprintf(stderr, "Cannot read next index-value pair.");
        abort();
    }
    if (i != next_index) {
        fprintf(stderr, "Expected next index %u, got %u.", next_index, i);
        abort();
    }
    ++next_index;
    return v;
}

// This is required since signed values get sign-extended to uint64_t, but we
// want zero-extend.
#define test_write(X) test_write_impl(X, sizeof(X) * 8)

static void test_write_impl(uint64_t v, int nbits)
{
    static char buf[64 + 1];
    for (int i = 0; i < 64; ++i) {
        const int bit = (i < nbits) ? ((v >> i) & 1) : 0;
        buf[64 - 1 - i] = '0' + bit;
    }
    puts(buf);
}

int main()
{
struct Input V1;
struct Output V2 = {0};
for (int V3 = 0; V3 < 9; ++V3) {
V1.kernel[V3] = test_read();
}
outsource(&V1, &V2);
test_write(V2.min_loc_x);
test_write(V2.min_loc_y);
test_write(V2.min_delta);
    return 0; // tcc miscompiles the program without this
}
