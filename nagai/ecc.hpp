#include "field.hpp"

class ECCPoint;


//Elliptic Curve: y^2 = x^3+ax+b
class ECC
{
	public:
	Field a; 
	Field b;

__attribute__((always_inline))
	ECC(Field fa, Field fb)
	{
		a = fa;
		b = fb;
	}
	
__attribute__((always_inline))
	~ECC(){}
	
	ECCPoint  NewPoint(Field x, Field y);
};


//Curve Point
class ECCPoint
{
	
	public:
	Field x = Field((uint64_t)0);
	Field y = Field((uint64_t)0);

	private:
	//Curve the point belongs to
	ECC * ec;

	public:
	//Construct a new point 
	ECCPoint(Field px, Field py, ECC * ecc);
	
	__attribute__((always_inline)) ~ECCPoint() {}
	
	//Double the point.	*WARNING* this does not work for point at infinity
	void Double();
	
	//Add the point with another point Q. *WARNING* q and this must not be 0 (point at infinity) nor equal
	void Add(ECCPoint* q);

	//Multiply by d. *WARNING* does not work when d is 0
	ECCPoint Multiply(Field d);
};



////////////////////////////////////Implementation//////////////////////////
__attribute__((always_inline))
ECCPoint ECC::NewPoint(Field x, Field y)
{
	return ECCPoint(x,y,this);
}


__attribute__((always_inline))
void ECCPoint::Double()
{
	Field x2 = x*x;
	Field f3 = Field((uint64_t)3);
	Field f2 = Field((uint64_t)2);
	Field lambda = (f3*x2+ec->a)/(f2*y);
	Field xr = lambda*lambda-f2*x;
	y = lambda*(x-xr)-y;
	x = xr;
}

__attribute__((always_inline))
inline ECCPoint::ECCPoint(Field px, Field py, ECC * ecc)
{
	x=px;
	y=py;
	ec = ecc;
}


__attribute__((always_inline))
void ECCPoint::Add(ECCPoint* q)
{
	Field x2 = x*x;
	Field lambda = (q->y-y)/(q->x-x);
	Field xr = lambda*lambda-x-q->x;
	y = lambda*(x-xr)-y;
	x = xr;
}

	
__attribute__((always_inline))
ECCPoint ECCPoint::Multiply(Field d)
{
	ECCPoint result(Field((uint64_t)0),Field((uint64_t)0), ec);
	ECCPoint N(x,y, ec);
	int limit = 256; //TODO
    bool first = true;
	
	for (unsigned i = 0; i < limit; ++i) 
	{
	Field bit = d.bit_at(i);
		if (bit) 
		{
			// r += b;
			if (first)
			{
				result.x = N.x;
				result.y = N.y;
				first = false;
			}
			else
				result.Add(&N);		
		}
		// b *= 2;
		N.Double();
	}
	return result;
}
