
#include "r1cs_libiop.hpp"

#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_ppzksnark/examples/run_r1cs_ppzksnark.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_gg_ppzksnark/r1cs_gg_ppzksnark.hpp>

#include "Util.hpp"

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

template <class F>
linear_combination<F> R1CSLibiop<F>::parseLinearCombJson(json &jlc, int input_nb, int input_padding)
{
	linear_combination<F> lc;
	for (auto const& term : jlc)
	{
		int idx = term[0];
		if (idx > input_nb)
			idx = idx + input_padding-input_nb;
		variable<F> var(idx);
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
bool R1CSLibiop<F>::FromJsonl(const std::string jsonFile, r1cs_constraint_system<F> &out_cs, bool pad_inputs)
{
	//read from file
	std::ifstream r1cs_file(jsonFile);
	if (!r1cs_file.good())
		return false;

	std::string line;
	json header;
	int input_nb =0;
	int input_padding = 0;

	//todo: clear out_cs
	while (std::getline(r1cs_file, line))
	{
		json jc = json::parse(line);
		
		if (jc.count("r1cs") > 0) 
		{
  			// header 
			header = jc["r1cs"];
			input_nb = header["instance_nb"];
			input_padding = input_nb;
			if (pad_inputs)
	  			input_padding = libiop::round_to_next_power_of_2(input_padding+1)-1;
			printf("input nb:%d, padding:%d\n",input_nb,input_padding);
		}
		else
		{
			//constraint
			linear_combination<F> A = parseLinearCombJson(jc["A"], input_nb, input_padding);
			linear_combination<F> B = parseLinearCombJson(jc["B"], input_nb, input_padding);
			linear_combination<F> C = parseLinearCombJson(jc["C"], input_nb, input_padding);
			r1cs_constraint<F> constraint(A,B,C);
			out_cs.add_constraint(constraint);
		}
  	}
	out_cs.primary_input_size_ = input_padding;// header["instance_nb"];
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
		variable<F> var(0);
		F cc(0);
		dummy.add_term(var, cc);
		r1cs_constraint<F> constraint(dummy, dummy, dummy);
		out_cs.add_constraint(constraint);
		++cur_cs_nb;
	}
}

template <class F>
void R1CSLibiop<F>::PadInputs(r1cs_primary_input<F> &primary_inputs, r1cs_auxiliary_input<F> &auxiliary_input, int target)
{
	size_t cur_size = primary_inputs.size();
	size_t target_size  = libiop::round_to_next_power_of_2(cur_size+1)-1;
	size_t witness_target = target-target_size;
	assert (cur_size <= target_size);
	
	while (cur_size < target_size)
	{
		F cc(0);	
		primary_inputs.push_back(cc); 
		++cur_size;
	}
	/*Commented for now, it is not clear whether it is needed or not.
	if (target == 0)
		target =  libiop::round_to_next_power_of_2(target_size + auxiliary_input.size()+1) - 1
	cur_size =  auxiliary_input.size();
	printf("padding witness from %d to %d\n", cur_size, witness_target);
	while (cur_size < witness_target)
	{
		F cc(0);	
		auxiliary_input.push_back(cc); 
		++cur_size;
	}*/
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


/*
template <class FieldT>
std::string FieldToString(FieldT cc)
{
	mpz_t t;
    mpz_init(t);
   	cc.as_bigint().to_mpz(t);
	mpz_class big_coeff(t);		//As recommended by GMP library; cf. https://gmplib.org/manual/Converting-Integers.html
	return big_coeff.get_str();
}
*/

template <class T>
json SerializeFieldVector(std::vector<T> &vec)
{
	json jlt;

	for (auto it = begin(vec); it != end(vec); ++it)
	{
		std::string ss = FieldToString<T>(*it);
		jlt.push_back(ss);
	}
	return jlt;
}

template <class T>
json SerializeBasicVector(const std::vector<T> &vec)
{
	json jlt;

	for (auto it = begin(vec); it != end(vec); ++it)
	{
		std::stringstream ss;

		ss << (*it);
		//   printf("bbs:%s",ss.str());

		jlt.push_back(ss.str());
	}
	return jlt;
}

template <class T>
json SerializeSafeVector(const std::vector<T> &vec)
{
	json jlt;
	for (auto it = begin(vec); it != end(vec); ++it)
	{
		std::stringstream ss;
		ss << (*it);
		jlt.push_back(skUtils::base64_encode(ss.str()));
	}
	return jlt;
}

template <class T>
void DeserializeSafeVector(std::vector<T> &vec, const json &jin)
{
	for (auto const &term : jin)
	{

		std::string str = term;
		vec.push_back(skUtils::base64_decode(str));
	}
}

template <class T>
void DeserializeBasicVector(std::vector<T> &vec, const json &jin)
{

	for (auto const &term : jin)
	{
		T value;
		std::stringstream ss;
		std::string str = term;
		ss << str;
		ss >> value;
		vec.push_back(value);
	}
}


template <class T>
void  DeserializeFieldVector( std::vector<T> & vec, const json & jin)
{
  for (auto const& term : jin)
  {
    std::string js = term;
    T cc(js.c_str());
    vec.push_back(cc);
  }
 
}


template <class F>
void R1CSLibiop<F>::SerializeProof(const bcs_transformation_transcript<F> proof, json &js)
{

    json p_msg;
    for (auto it = begin( proof.prover_messages_); it != end(proof.prover_messages_); ++it)
    {
      std::vector<F> toto = *it;
      std::vector<std::string> tata;
      for(auto t =begin(toto);t != end(toto);++t)
      {
        tata.push_back( FieldToString<F>(*t));
      }
      json jlt(tata);/*
    //  jlt=SerializeFieldVector<FieldT>(*it);
    for (auto jt = begin(*it); jt != end(*it); ++jt)
      {
        	jlt.push_back(FieldToString<FieldT>(*jt));
      }*/
      p_msg.push_back(jlt);
    //  printf("prove msg vec: %d\n", jlt.size());
    }
    js["prover_messages"] = p_msg;


    
  js["MT_roots"] = SerializeSafeVector<std::string>(proof.MT_roots_);
    json jquerypos;
    for (auto it = begin ( proof.query_positions_); it != end (proof.query_positions_); ++it)
    {
      jquerypos.push_back(SerializeBasicVector<std::size_t>(*it));
    }
    js["query_positions"] = jquerypos;

json jqueyresp;
    for (auto it = begin ( proof.query_responses_); it != end (proof.query_responses_); ++it)
    {
      json jqr;
      for (auto jt = begin (*it); jt != end (*it); ++jt)
      {
		std::vector<F> vec = *jt;
        json jj= SerializeFieldVector<F>(vec);;
        jqr.push_back(jj);
      }
      jqueyresp.push_back(jqr);
    }
    js["query_responses"] = jqueyresp;
    jqueyresp.clear();
    json jlpos;
    for (auto it = begin ( proof.MT_leaf_positions_); it != end (proof.MT_leaf_positions_); ++it)
    {
      jlpos.push_back(SerializeBasicVector<std::size_t>(*it));
    }
    js["MT_leaf_positions"] = jlpos;
    json jvec;
    for (auto it = begin ( proof.MT_set_membership_proofs_); it != end ( proof.MT_set_membership_proofs_); ++it)
    {
      json jit;
      jit["auxiliary_hashes"] = SerializeSafeVector<std::string>(it->auxiliary_hashes);
      jit["randomness_hashes"] = SerializeSafeVector<std::string>(it->randomness_hashes);
      jvec.push_back(jit);
    }
    js["MT_set_membership_proofs"] = jvec;
  js["total_depth_without_pruning"]  =  proof.total_depth_without_pruning;
}

template <class F>
void R1CSLibiop<F>::DeserializeProof(bcs_transformation_transcript<F> &proof, const json &js)
{

	int s = js["prover_messages"].size();

	for (auto &term : js["prover_messages"])
	{

		std::vector<F> vec;
		DeserializeFieldVector(vec, term);
		proof.prover_messages_.push_back(vec);
	}

	DeserializeSafeVector<std::string>(proof.MT_roots_, js["MT_roots"]);

	for (auto &term : js["query_positions"])
	{
		std::vector<std::size_t> vv;
		DeserializeBasicVector<std::size_t>(vv, term);
		proof.query_positions_.push_back(vv);
	}

	for (auto &term : js["query_responses"])
	{
		std::vector<std::vector<F>> qr;
		for (auto &term2 : term)
		{
			std::vector<F> vv;
			DeserializeFieldVector<F>(vv, term2);
			qr.push_back(vv);
		}
		proof.query_responses_.push_back(qr);
	}
	for (auto const &term : js["MT_leaf_positions"])
	{
		std::vector<size_t> vv;
		DeserializeBasicVector<size_t>(vv, term);
		proof.MT_leaf_positions_.push_back(vv);
	}

	for (auto const &term : js["MT_set_membership_proofs"])
	{
		merkle_tree_set_membership_proof mts;
		DeserializeSafeVector<std::string>(mts.auxiliary_hashes, term["auxiliary_hashes"]);
		DeserializeSafeVector<std::string>(mts.randomness_hashes, term["randomness_hashes"]);
		proof.MT_set_membership_proofs_.push_back(mts);
	}
	proof.total_depth_without_pruning = js["total_depth_without_pruning"];
}

template class  R1CSLibiop<libff::edwards_Fr>;
template class  R1CSLibiop<libff::alt_bn128_Fr>;