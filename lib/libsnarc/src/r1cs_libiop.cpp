
#include "r1cs_libiop.hpp"

#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_ppzksnark/examples/run_r1cs_ppzksnark.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_gg_ppzksnark/r1cs_gg_ppzksnark.hpp>

//#include "Util.hpp"

#include <iostream>
#include <sstream>
#include <fstream>

#include <gmpxx.h>
#include <libff/algebra/curves/edwards/edwards_pp.hpp>
#include <libff/algebra/curves/alt_bn128/alt_bn128_pp.hpp>

using json = nlohmann::json;

using namespace libiop;


template <class F>
std::string FieldToString(F cc)
{
	mpz_t t;
    mpz_init(t);
   	cc.as_bigint().to_mpz(t);
	mpz_class big_coeff(t);		//As recommended by GMP library; cf. https://gmplib.org/manual/Converting-Integers.html
	return big_coeff.get_str();
//gf64
//	char buffer [50];
//	sprintf(buffer,"%016", cc.value());
//	return std::string(buffer);
}





bool WriteJson2File(const std::string &fname, const json & jsonContent)
{
	//write to file
	std::ofstream o(fname);
    if (!o.good())
		return false;
	o << jsonContent;
	o.close();
	return true;
}




//Initialize the parameters
template <class F>
void R1CSLibiop<F>::InitR1CS()
{
	gadgetlib2::initPublicParamsFromDefaultPp();
	gadgetlib2::GadgetLibAdapter::resetVariableIndex();
}

template <class F>
json R1CSLibiop<F>::LinearCombination2Json(linear_combination<F> vec)
{
	json jc;
	json jlt;

	for (linear_term<F> const & lt:vec)
	{
		//TODO: Check the coefficient is not null
		json jlt;
		jlt.push_back(lt.index_);				//TODO handle neg.idx: if lt.index>primary.len, idx=primary.len-lt.index (or so)
		//Convert the coefficient to string
		jlt.push_back(FieldToString(lt.coeff_));

		jc.push_back(jlt);
	}
	return jc;
}



template <class F>
linear_combination<F> R1CSLibiop<F>::parseLinearCombJson(json &jlc)
{
	linear_combination<F> lc;
	for (auto const& term : jlc)
	{
		variable<F> var(term[0]);
		std::string str_coeff = term[1];
		F cc(str_coeff.c_str());
		
		lc.add_term(var, cc);//TODO handle negative idx; something like this: if var<0; idx = primary.len - var
		
	}
	return lc;	
}

//Convert R1CS assignment into a '.j1cs.in' json input file
template <class F>
json R1CSLibiop<F>::Inputs2Json(const r1cs_primary_input<F> &primary_input,const r1cs_auxiliary_input<F> &auxiliary_input)
{
	json j_inputs, j_wit;


	for (F const & iter:primary_input)
	{
		//TODO; there should be no coef null!!	
		j_inputs.push_back(FieldToString(iter));
	}
	for (F const & iter:auxiliary_input)
	{
		//TODO; there should be no coef null!!???
		j_wit.push_back(FieldToString(iter));
	}
	json jValue;
	jValue["inputs"] = j_inputs;
	jValue["witnesses"] = j_wit;

	return jValue;
}

template <class F>
bool R1CSLibiop<F>::SaveInputs(const std::string jsonFile, const r1cs_primary_input<F> &primary_input,const r1cs_auxiliary_input<F> &auxiliary_input)
{
	json jValue = Inputs2Json(primary_input, auxiliary_input);
	return WriteJson2File(jsonFile, jValue);
}




template <class F>
bool R1CSLibiop<F>::ToJsonl(r1cs_constraint_system<F>  &in_cs, const std::string &out_fname)
{
	//convert r1cs to jsonl file
	json r1cs_header;
	r1cs_header["version"] = "1.0";
	r1cs_header["extension_degree"] = 1;
	r1cs_header["instance_nb"] = in_cs.primary_input_size_;
	r1cs_header["witness_nb"] = in_cs.auxiliary_input_size_;
	r1cs_header["constraint_nb"] = in_cs.num_constraints();
	r1cs_header["field_characteristic"] = 1;	//TODO - should be a parameter
	//write to file
	std::ofstream o(out_fname);
	if (!o.good())
		return false;
	json j; 
	j["r1cs"] = r1cs_header; 
	o << j << std::endl;
	//write constraints
	for (r1cs_constraint<F>& constraint : in_cs.constraints_)
	{
		json jc;
		jc["A"] = LinearCombination2Json(constraint.a_);
		jc["B"] = LinearCombination2Json(constraint.b_);
		jc["C"] = LinearCombination2Json(constraint.c_);
		o << jc << std::endl;
	}
	o.close();
    return true;
}

template <class F>
bool R1CSLibiop<F>::FromJsonl(const std::string jsonFile, r1cs_constraint_system<F> &out_cs)
{
	//read from file
	std::ifstream r1cs_file(jsonFile);
	if (!r1cs_file.good())
		return false;

	std::string line;
	json header;
	//todo: clear out_cs
	while (std::getline(r1cs_file, line))
	{
		json jc = json::parse(line);
		
		if (jc.count("r1cs") > 0) 
		{
  			// header 
			header = jc["r1cs"];
		}
		else
		{
			//constraint
			linear_combination<F> A = parseLinearCombJson(jc["A"]);
			linear_combination<F> B = parseLinearCombJson(jc["B"]);
			linear_combination<F> C = parseLinearCombJson(jc["C"]);
			r1cs_constraint<F> constraint(A,B,C);
			out_cs.add_constraint(constraint);
		}
  	}
	out_cs.primary_input_size_ = header["instance_nb"];
	out_cs.auxiliary_input_size_ = header["witness_nb"];

	return true;
}

template <class F>
void R1CSLibiop<F>::Pad(r1cs_constraint_system<F> &out_cs)
{

	size_t cur_cs_nb = out_cs.num_constraints();
	size_t cs_nb = libiop::round_to_next_power_of_2(cur_cs_nb);
	while (cur_cs_nb < cs_nb)
	{
		linear_combination<F> dummy;
		r1cs_constraint<F> constraint(dummy, dummy, dummy);
		out_cs.add_constraint(constraint);
		++cur_cs_nb;
	}
}

template <class F>
void R1CSLibiop<F>::PadInputs(r1cs_primary_input<F> &primary_inputs)
{

	size_t cur_size = primary_inputs.size();
	size_t target_size = libiop::round_to_next_power_of_2(cur_size)-1;
	if (target_size < cur_size)
		target_size = libiop::round_to_next_power_of_2(cur_size+1)-1;
	while (cur_size < target_size)
	{
		F cc(0);	
		primary_inputs.push_back(cc); 
		++cur_size;
	}
}


//Load the inputs from a json file .j1cs.in
template <class F>
bool R1CSLibiop<F>::LoadInputs(const std::string jsonFile, r1cs_primary_input<F> &primary_input, r1cs_auxiliary_input<F> &auxiliary_input)
{
	//load the inputs
	std::ifstream jfile(jsonFile);
	if (!jfile.good())
		return false;
	json j_in;
	jfile >> j_in;
	json j_inputs = j_in["inputs"];
	for (json::iterator it = j_inputs.begin(); it != j_inputs.end(); ++it) 
	{
		std::string str_coeff = (*it);
		F cc(str_coeff.c_str());	
		primary_input.push_back(cc); 
		//TODO handle one constant at idx 0
	}
	json j_wit = j_in["witnesses"];
	for (json::iterator it = j_wit.begin(); it != j_wit.end(); ++it) 
	{
		std::string str_coeff = (*it);
		F cc(str_coeff.c_str());
		auxiliary_input.push_back(cc);
  	}
	return true;
}


template class  R1CSLibiop<libff::edwards_Fr>;
template class  R1CSLibiop<libff::alt_bn128_Fr>;