#pragma once

#include <string>
//#include <libsnark/common/default_types/r1cs_gg_ppzksnark_pp.hpp>
//#include <libsnark/gadgetlib2/variable.hpp>
//#include <libsnark/gadgetlib2/protoboard.hpp>
#include "json.hpp"

#include <libff/algebra/curves/alt_bn128/alt_bn128_pp.hpp>



class skLigero
{

public:
   /* //Convert .arith file (Pinnocchio format) into a j-r1cs file
    bool Arith2Jsonl(const std::string &arithFile, const std::string &inputsFile, const std::string &outFile);

    //Generate the setup for Verifiable Compution. TODO should specify which scheme to use. For now we support only libsnark (trusted setup)
    bool VCSetup(const std::string &jr1cs , std::string &ts);

   

    //Verify a proof
    bool Verify(const std::string& setup, std::string inputsFile, std::string proof);
*/
     //Generate the proof from a (trusted) setup
    nlohmann::json  Proof(const std::string &r1cs_filename,  const std::string &trustedSetup);
};