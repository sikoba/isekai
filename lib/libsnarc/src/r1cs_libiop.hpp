#pragma once
#ifndef R1CS_LIBIOP_H
#define R1CS_LIBIOP_H

#include <string>
#include <libsnark/common/default_types/r1cs_gg_ppzksnark_pp.hpp>
//#include <libsnark/gadgetlib2/variable.hpp>
//#include <libsnark/gadgetlib2/protoboard.hpp>
#include "json.hpp"
#include "libiop/relations/variable.hpp"
#include "libiop/relations/r1cs.hpp"
#include "libiop/snark/common/bcs_common.hpp"



//typedef libff::Fr<libff::default_ec_pp> FieldT;
//typedef libiop::gf64 FieldT;
//typedef libff::alt_bn128_Fr FieldT;
//typedef libff::edwards_Fr FieldT;
//template<class F>
//struct bcs_transformation_transcript;

template<class F>
class R1CSLibiop
{

public:
    void InitR1CS();
    nlohmann::json LinearCombination2Json(libiop::linear_combination<F> vec);
    libiop::linear_combination<F> parseLinearCombJson(nlohmann::json &jlc, int input_nb, int input_padding);
    libiop::linear_combination<F> parseLinearCombJson(nlohmann::json &jlc);
    nlohmann::json Inputs2Json(const libiop::r1cs_primary_input<F> &primary_input,const libiop::r1cs_auxiliary_input<F> &auxiliary_input);

    bool SaveInputs(const std::string jsonFile, const libiop::r1cs_primary_input<F> &primary_input,const libiop::r1cs_auxiliary_input<F> &auxiliary_input);

    bool ToJsonl(libiop::r1cs_constraint_system<F>  &in_cs, const std::string &out_fname);
    bool FromJsonl(const std::string jsonFile, libiop::r1cs_constraint_system<F> &out_cs, bool pad_inputs = false);
    bool LoadInputs(const std::string jsonFile, libiop::r1cs_primary_input<F> &primary_input, libiop::r1cs_auxiliary_input<F> &auxiliary_input);
    void Pad(libiop::r1cs_constraint_system<F> &out_cs);
    void PadInputs(libiop::r1cs_primary_input<F> &primary_inputs, libiop::r1cs_auxiliary_input<F> &auxiliary_input, int target);


    void SerializeProof(const libiop::bcs_transformation_transcript<F> proof, nlohmann::json &js);
    void DeserializeProof( libiop::bcs_transformation_transcript<F> &proof, const nlohmann::json &js);
    
};

#endif