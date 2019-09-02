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
