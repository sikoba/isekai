#ifndef UTIL_HPP_
#define UTIL_HPP_

#include <libff/common/default_types/ec_pp.hpp>
#include <iostream>
#include <sstream>
#include <vector>
#include "json.hpp"


using namespace std;
using json = nlohmann::json;

typedef libff::Fr<libff::default_ec_pp> FieldT;




//Utils class from Sikoba
class skUtils
{
    public:
    //Parse a list of ids
    static void readIds(char* str, std::vector<unsigned int>& vec);

    //Convert an hexadecimal as string into a field element
    static FieldT HexStringToField(char* inputStr);

    //Convert a field element into a string (in decimal form)
    static std::string FieldToString(FieldT cc);

    //Returns true if the 'str' string ends like 'suffix'
    static bool endsWith(const std::string& str, const std::string& suffix);

    //Encode the string 'in' into a base64 string
    static std::string base64_encode(const std::string &in);
    
    //Decode a base64 string
    static std::string base64_decode(const std::string &in) ;

    //Write a json object into a file
    static bool WriteJson2File(const std::string &fname, const json & jsonContent);

    //Load a json objecfrom a file
    static json LoadJsonFromFile(const std::string& fname);
};
#endif
