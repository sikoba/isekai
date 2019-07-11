#include "Util.hpp"
#include <gmpxx.h>
#include <fstream>

typedef unsigned char uchar;

void skUtils::readIds(char* str, std::vector<unsigned int>& vec)
{
	istringstream iss_i(str, istringstream::in);
	unsigned int id;
	while (iss_i >> id) 
    {
		vec.push_back(id);
	}
}

FieldT skUtils::HexStringToField(char* inputStr)
{
	char constStrDecimal[150];
	mpz_t integ;
	mpz_init_set_str(integ, inputStr, 16);
	mpz_get_str(constStrDecimal, 10, integ);
	mpz_clear(integ);
	FieldT f = FieldT(constStrDecimal);
	return f;

}


///////////////////////////////////////
//Helper to convert coefficient to string
std::string skUtils::FieldToString(FieldT cc)
{
	mpz_t t;
    mpz_init(t);
   	cc.as_bigint().to_mpz(t);
	mpz_class big_coeff(t);		//As recommended by GMP library; cf. https://gmplib.org/manual/Converting-Integers.html
	return big_coeff.get_str();
}


bool skUtils::endsWith(const std::string& str, const std::string& suffix)
{
    return str.size() >= suffix.size() && 0 == str.compare(str.size()-suffix.size(), suffix.size(), suffix);
}

std::string skUtils::base64_encode(const std::string &in) 
{

    std::string out;

    int val=0, valb=-6;
    for (uchar c : in) {
        val = (val<<8) + c;
        valb += 8;
        while (valb>=0) {
            out.push_back("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[(val>>valb)&0x3F]);
            valb-=6;
        }
    }
    if (valb>-6) out.push_back("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[((val<<8)>>(valb+8))&0x3F]);
    while (out.size()%4) out.push_back('=');
    return out;
}

std::string skUtils::base64_decode(const std::string &in) 
{
    std::string out;

    std::vector<int> T(256,-1);
    for (int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i; 

    int val=0, valb=-8;
    for (uchar c : in) {
        if (T[c] == -1) break;
        val = (val<<6) + T[c];
        valb += 6;	
        if (valb>=0) {
            out.push_back(char((val>>valb)&0xFF));
            valb-=8;
        }
    }
    return out;
}



bool skUtils::WriteJson2File(const std::string &fname, const json & jsonContent)
{
	//write to file
	std::ofstream o(fname);
    if (!o.good())
		return false;
	o << jsonContent;
	o.close();
	return true;
}

//Load a json from a file
json skUtils::LoadJsonFromFile(const std::string& fname)
{
	json result;
	std::ifstream filehandle(fname);
	if (!filehandle.good())
		return result;

	std::string file_str,line;
	while ( getline (filehandle,line) )
    {
      file_str += line;
    }
	filehandle.close();

	result = json::parse(file_str);
	printf("file :%s is loaded into json\n", fname.c_str());
	return result;
}