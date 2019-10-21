#ifndef __CWRAPPER_H__
#define __CWRAPPER_H__


#ifdef __cplusplus
extern "C" {
#endif

struct wrap;
typedef struct wrap wrap_t;



void test(char *fname);

void test2(wrap_t *m, int val);

bool MyFunction(char **toto);

//Generate R1CS from an artihmetic circuit and iis inputs
// arithFile: file path of the arithmetic circuit in Pinnochio format (.arith)
// inputsFile: file path of the circuit inputs in Pinnochio format (.in)
// r1csFile: file path of the r1cs result in json format
// returns: true is the R1CS could be generated
// if r1csFile is not specified, it create a file by replacing the .arith extension with .r1cs
bool generateR1cs(char* arithFile, char* inputsFile, char * r1csFile);

// Generate the trusted setup
//r1csFile: j-r1cs input file 
//setupFile: name of the out file that will contain the trusted setup in json
//TEMP ts:output verifiable computing setup, to return the data in the out argument, but we need to properly allocate the strings; should be allocated byt the called first
void vcSetup(char* r1csFile, char * setupFile /*, char** ts*/, int scheme);

//Generate a proof
//setup: file name of the trusted setup in json format
//inputs: file name of the inputs in json format. We need the full assignments.
//proofFile: file name of the out file that will contain the proof in json format. Optional, no file created if not defined
//scheme: 1 for libsnark, 2 for bulletproof, 3 for aurora
// returns: the proof in json format
char * Prove(char * setup, char * inputs, char * proofFile, int scheme);

//Verify a proof:
//setup: file name of the trusted setup in json format
//inputs: file name of the inputs in json format.
//proof: file name of the proof in json format.
bool Verify(char * setup, char * inputsFile, char * proof);


#ifdef __cplusplus
}
#endif

#endif /* __CWRAPPER_H__ */
