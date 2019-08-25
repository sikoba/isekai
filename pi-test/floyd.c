enum { NINPUT = 5 };

#define NUM_V NINPUT

#define EDGE_WEIGHT(weight_table, i, j)	weight_table[i*NUM_V+j]

struct Input {
	unsigned edge_table[NUM_V*NUM_V];
};

struct Output {
	unsigned path_table[NUM_V*NUM_V];
};

void outsource(struct Input *in, struct Output *out)
{
	int i, j, k;
	for (i=0; i<NUM_V; i+=1)
	{
		for (j=0; j<NUM_V; j+=1)
		{
			EDGE_WEIGHT(out->path_table, i, j) = EDGE_WEIGHT(in->edge_table, i, j);
		}
	}
	for (k=0; k<NUM_V; k+=1)
	{
		for (i=0; i<NUM_V; i+=1)
		{
			for (j=0; j<NUM_V; j+=1)
			{
				unsigned existing = EDGE_WEIGHT(out->path_table, i, j);
				unsigned detoured = EDGE_WEIGHT(out->path_table, i, k) + EDGE_WEIGHT(out->path_table, k, j);
				unsigned best_path = existing;
				if (detoured < existing)
					best_path = detoured;
				EDGE_WEIGHT(out->path_table, i, j) = best_path;
			}
		}
	}
}
