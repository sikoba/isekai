#include <stdlib.h>
#include <fstream> 
#include "cwrapper.h"
#include "r1cs_utils.hpp"

using namespace std; 

struct wrap {
	void *obj;
};


void test2(wrap_t *m, int /*val */)
{
	if (m == NULL)
		return;
	
}

void test(char *m)
{
	std::ofstream o("test--me2.txt");
	o << "hello world"<< std::endl;
	o << m << std::endl;
    o.close();

}

bool MyFunction(char **toto)
{
	//*toto="bla";
	strncpy(*toto, "bla", 3);
	return true;
}

//Generate R1CS from an artihmetic circuit and his inputs
// arithFile: file path of the arithmetic circuit in Pinnochio format (.arith)
// inputsFile: file path of the circuit inputs in Pinnochio format (.in)
// r1csFile: file path of the r1cs result in json format
// returns: true is the R1CS could be generated
// if r1csFile is not specified, it create a file by replacing the .arith extension with .r1cs
bool generateR1cs(char* arithFile, char* inputsFile, char * r1csFile)
{
	std::string afname(arithFile);
	std::string ifname(inputsFile);
	std::string jfname = std::string();
	if (r1csFile != NULL)
		jfname = std::string(r1csFile);
	else
	{
		size_t ppos = afname.rfind('.');
		if (ppos != string::npos)
			jfname = afname.substr(0, ppos) + ".r1cs";
		else
			jfname = afname + ".r1cs";
	}

	R1CSUtils r1cs;
	return r1cs.Arith2Jsonl(afname, ifname, jfname);
}

// Generate the trusted setup
//r1csFile: j-r1cs input file 
//setupFile: name of the out file that will contain the trusted setup in json
//TEMP ts:output verifiable computing setup, to return the data in the out argument, but we need to properly allocate the strings; should be allocated byt the called first
//For debuggin purpose, if r1csFile ends with .arith, it will consider the file as a circuit and convert it first to r1cs
void vcSetup(char* r1csFile, char * setupFile /*, char** ts*/)
{
	std::string afname(r1csFile);
	std::string setupfName(setupFile);
	std::string trustedSetup;
	R1CSUtils r1cs;
	r1cs.VCSetup(afname, trustedSetup);
	//*ts = (char *)trustedSetup.c_str();
	std::ofstream o(setupfName);
	o << trustedSetup;
    o.close();
}

//Generate a proof
//setup: file name of the trusted setup in json format
//inputs: file name of the inputs in json format. We need the full assignments.
//proofFile: file name of the out file that will contain the proof in json format. Optional, no file created if not defined
// returns: the proof in json format
char * Prove(char * setup, char * inputs, char * proofFile)
{
	R1CSUtils r1cs;
	std::string ts(setup);
	std::string ins(inputs);
	std::string pfile = "";
	if (proofFile != NULL)
		pfile = std::string(proofFile);
	nlohmann::json jkey = r1cs.Proof(ins, ts);
	
	if (pfile.length() > 0)
	{
		//save to file
		std::ofstream o(pfile);
		o << jkey.dump();
    	o.close();
	}

	return NULL;//TEMP (char*)jkey.dump().c_str();
}

//Verify a proof:
//setup: file name of the trusted setup in json format
//inputs: file name of the inputs in json format.
//proof: file name of the proof in json format.
bool Verify(char * setup, char * inputs, char * proof)
{
	R1CSUtils r1cs;
	std::string ts(setup);
	std::string ins(inputs);
	std::string p(proof);
	return r1cs.Verify(ts, ins, p);
}
