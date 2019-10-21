#pragma once
#ifndef LIBSNARK_WRAPPER_H
#define LIBSNARK_WRAPPER_H

#include <string>
#include <libsnark/common/default_types/r1cs_gg_ppzksnark_pp.hpp>
#include <libsnark/gadgetlib2/variable.hpp>
#include <libsnark/gadgetlib2/protoboard.hpp>
#include "json.hpp"
#include "cwrapper.h"

class Snarks
{
public:
    enum zkp_scheme
    {
        snark,
        groth16,
        bctv14a ,   
        libsnark,         
        libsnark_legacy,  
        dalek  ,
        aurora,
        ligero,
        fractal
    };


    //Convert .arith file (Pinnocchio format) into a j-r1cs file
    bool Arith2Jsonl(const std::string &arithFile, const std::string &inputsFile, const std::string &outFile);

    //Generate the setup for Verifiable Compution. TODO should specify which scheme to use. For now we support only libsnark (trusted setup)
    bool VCSetup(const std::string &jr1cs , std::string &ts, zkp_scheme zcheme);

    //Generate the proof from a (trusted) setup
    nlohmann::json  Proof(const std::string &inputsFile,  const std::string &trustedSetup, zkp_scheme zcheme);

    //Verify a proof
    bool Verify(const std::string& setup, std::string inputsFile, std::string proof);

};

#endif