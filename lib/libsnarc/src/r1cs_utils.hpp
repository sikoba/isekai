#pragma once
#ifndef R1CS_UTILS_H
#define R1CS_UTILS_H

#include <string>
#include <libsnark/common/default_types/r1cs_gg_ppzksnark_pp.hpp>
#include <libsnark/gadgetlib2/variable.hpp>
#include <libsnark/gadgetlib2/protoboard.hpp>
#include "json.hpp"
#include "CircuitReader.hpp"


//typedef libff::Fr<libff::default_ec_pp> FieldT;

class R1CSUtils
{

public:
    void InitR1CS();
    nlohmann::json LinearCombination2Json(linear_combination<FieldT> vec);
    linear_combination<FieldT> parseLinearCombJson(nlohmann::json &jlc);
    nlohmann::json Inputs2Json(const r1cs_primary_input<FieldT> &primary_input,const r1cs_auxiliary_input<FieldT> &auxiliary_input);

    bool SaveInputs(const std::string jsonFile, const r1cs_primary_input<FieldT> &primary_input,const r1cs_auxiliary_input<FieldT> &auxiliary_input);
    r1cs_constraint_system<FieldT> GenerateFromArithFile(const std::string &fname, const std::string &inputValues, nlohmann::json & assignments);
    bool ToJsonl(r1cs_constraint_system<FieldT>  &in_cs, const std::string &out_fname);
    bool FromJsonl(const std::string jsonFile, r1cs_constraint_system<FieldT> &out_cs);
    bool LoadInputs(const std::string jsonFile, r1cs_primary_input<FieldT> &primary_input, r1cs_auxiliary_input<FieldT> &auxiliary_input);

};

#endif