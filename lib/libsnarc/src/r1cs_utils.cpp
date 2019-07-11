
#include "r1cs_utils.hpp"
#include "CircuitReader.hpp"
#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_ppzksnark/examples/run_r1cs_ppzksnark.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_gg_ppzksnark/r1cs_gg_ppzksnark.hpp>


using json = nlohmann::json;

//Initialize the parameters
void InitR1CS()
{
	gadgetlib2::initPublicParamsFromDefaultPp();
	gadgetlib2::GadgetLibAdapter::resetVariableIndex();
}

json LinearCombination2Json(linear_combination<FieldT> vec)
{
	json jc;
	json jlt;

	for (linear_term<FieldT> const & lt:vec)
	{
		//TODO: Check the coefficient is not null
		json jlt;
		jlt.push_back(lt.index);				//TODO handle neg.idx: if lt.index>primary.len, idx=primary.len-lt.index (or so)
		//Convert the coefficient to string
		jlt.push_back(skUtils::FieldToString(lt.coeff));

		jc.push_back(jlt);
	}
	return jc;
}




linear_combination<FieldT> parseLinearCombJson(json &jlc)
{
	linear_combination<FieldT> lc;
	for (auto const& term : jlc)
	{
		variable<FieldT> var(term[0]);
		std::string str_coeff = term[1];
		FieldT cc(str_coeff.c_str());
		
		lc.add_term(var, cc);//TODO handle negative idx; something like this: if var<0; idx = primary.len - var
		
	}
	return lc;	
}

//Convert R1CS assignment into a '.j1cs.in' json input file
json Inputs2Json(const r1cs_primary_input<FieldT> &primary_input,const r1cs_auxiliary_input<FieldT> &auxiliary_input)
{
	json j_inputs, j_wit;


	for (FieldT const & iter:primary_input)
	{
		//TODO; there should be no coef null!!	
		j_inputs.push_back(skUtils::FieldToString(iter));
	}
	for (FieldT const & iter:auxiliary_input)
	{
		//TODO; there should be no coef null!!???
		j_wit.push_back(skUtils::FieldToString(iter));
	}
	json jValue;
	jValue["inputs"] = j_inputs;
	jValue["witnesses"] = j_wit;

	return jValue;
}

bool SaveInputs(const std::string jsonFile, const r1cs_primary_input<FieldT> &primary_input,const r1cs_auxiliary_input<FieldT> &auxiliary_input)
{
	json jValue = Inputs2Json(primary_input, auxiliary_input);
	return skUtils::WriteJson2File(jsonFile, jValue);
}

r1cs_constraint_system<FieldT> GenerateFromArithFile(const std::string &fname, const std::string &inputValues, json & assignments)
{
    InitR1CS();
	gadgetlib2::ProtoboardPtr pb = gadgetlib2::Protoboard::create(gadgetlib2::R1P);

    // Read the circuit, evaluate, and translate constraints
	CircuitReader reader(fname.c_str(), inputValues.c_str(), pb);
	r1cs_constraint_system<FieldT> constraints = get_constraint_system_from_gadgetlib2(*pb);
	const r1cs_variable_assignment<FieldT> full_assignment = get_variable_assignment_from_gadgetlib2(*pb);
	constraints.primary_input_size = reader.getNumInputs() + reader.getNumOutputs();
	constraints.auxiliary_input_size = full_assignment.size() - constraints.num_inputs();

	// extract primary and auxiliary input
	const r1cs_primary_input<FieldT> primary_input(full_assignment.begin(),
			full_assignment.begin() + constraints.num_inputs());
	const r1cs_auxiliary_input<FieldT> auxiliary_input(
			full_assignment.begin() + constraints.num_inputs(), full_assignment.end());
	assignments = Inputs2Json(primary_input, auxiliary_input);

    return constraints;
}





bool ToJsonl(r1cs_constraint_system<FieldT>  &in_cs, const std::string &out_fname)
{
	//convert r1cs to jsonl file
	json r1cs_header;
	r1cs_header["version"] = "1.0";
	r1cs_header["extension_degree"] = 1;
	r1cs_header["instance_nb"] = in_cs.primary_input_size;
	r1cs_header["witness_nb"] = in_cs.auxiliary_input_size;
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
	for (r1cs_constraint<FieldT>& constraint : in_cs.constraints)
	{
		json jc;
		jc["A"] = LinearCombination2Json(constraint.a);
		jc["B"] = LinearCombination2Json(constraint.b);
		jc["C"] = LinearCombination2Json(constraint.c);
		o << jc << std::endl;
	}
	o.close();
    return true;
}

bool FromJsonl(const std::string jsonFile, r1cs_constraint_system<FieldT> &out_cs)
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
			linear_combination<FieldT> A = parseLinearCombJson(jc["A"]);
			linear_combination<FieldT> B = parseLinearCombJson(jc["B"]);
			linear_combination<FieldT> C = parseLinearCombJson(jc["C"]);
			r1cs_constraint<FieldT> constraint(A,B,C);
			out_cs.add_constraint(constraint);
		}
  	}
	out_cs.primary_input_size = header["instance_nb"];
	out_cs.auxiliary_input_size = header["witness_nb"];

	return true;
}

//Load the inputs from a json file .j1cs.in
bool LoadInputs(const std::string jsonFile, r1cs_primary_input<FieldT> &primary_input, r1cs_auxiliary_input<FieldT> &auxiliary_input)
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
		FieldT cc(str_coeff.c_str());
		primary_input.push_back(cc); 
		//TODO handle one constant at idx 0
	}
	json j_wit = j_in["witnesses"];
	for (json::iterator it = j_wit.begin(); it != j_wit.end(); ++it) 
	{
		std::string str_coeff = (*it);
		FieldT cc(str_coeff.c_str());
		auxiliary_input.push_back(cc);
  	}
	return true;
}




// (1) The "generator", which runs the ppzkSNARK generator on input a given
//     constraint system CS to create a proving and a verification key for CS.
template<typename ppT>
json TrustedSetup(const r1cs_constraint_system<FieldT>  &cs)
{

	r1cs_ppzksnark_keypair<ppT> keypair = r1cs_ppzksnark_generator<ppT>(cs);
    //tODO debug log printf("\n"); libff::print_indent(); libff::print_mem("after generator");

    libff::print_header("Preprocess verification key");
    r1cs_ppzksnark_processed_verification_key<ppT> pvk = r1cs_ppzksnark_verifier_process_vk<ppT>(keypair.vk);

	/////////////////////
 //   r1cs_gg_ppzksnark_keypair<ppT> keypair = r1cs_gg_ppzksnark_generator<ppT>(cs2);

	printf("\tkey pair is generatede\n");
 //   r1cs_gg_ppzksnark_processed_verification_key<ppT> pvk = r1cs_gg_ppzksnark_verifier_process_vk<ppT>(keypair.vk);


	json trusted_setup;
	trusted_setup["type"] = "libsnark";	//TODO version..
	std::stringstream ss;
	ss << keypair.vk;
	trusted_setup["verification_key"] = skUtils::base64_encode(ss.str());

	ss = std::stringstream();
	ss << keypair.pk;
	trusted_setup["proving_key"] = skUtils::base64_encode(ss.str());

	ss = std::stringstream();
	ss << pvk;
	trusted_setup["preprocess_verification_key"] = skUtils::base64_encode(ss.str());

    return trusted_setup;
}




bool R1CSUtils::Arith2Jsonl(const std::string &arithFile, const std::string &inputsFile, const std::string &outFile)
{
	json assignments;
	r1cs_constraint_system<FieldT> constraints = GenerateFromArithFile(arithFile, inputsFile, assignments);
    return ToJsonl(constraints, outFile) && skUtils::WriteJson2File(outFile + ".in", assignments);
}


bool TS(const std::string &jr1cs, std::string &ts)
{
	r1cs_constraint_system<FieldT> cs;
	if (skUtils::endsWith(jr1cs, ".arith"))
	{
		json dummy;
		cs = GenerateFromArithFile(jr1cs, jr1cs.substr(0, jr1cs.size()-5) + "in", dummy);

	}
	else
		FromJsonl(jr1cs, cs);
		
	json j_ts = TrustedSetup<libff::default_ec_pp>(cs);
	ts = j_ts.dump();
	
    return true;
}


bool R1CSUtils::VCSetup(const std::string &jr1cs , std::string &ts)
{
	InitR1CS();
	ts = "an error occured";
	return TS(jr1cs, ts);
}


template<typename ppT>
json Proover(const	r1cs_primary_input<FieldT>& primary_i,	const r1cs_auxiliary_input<FieldT>& aux_i, const json &j_ts)
{
	//load the proving key
//	r1cs_gg_ppzksnark_proving_key<ppT> pk; //TODO check gg vs pp
	r1cs_ppzksnark_proving_key<ppT> pk;
	std::string pk64 = j_ts["proving_key"];
	std::stringstream ss;
	ss << skUtils::base64_decode(pk64);
	ss >> pk;

	if (pk.constraint_system.is_satisfied(primary_i, aux_i))
		printf("R1CS is satisfied.\n");
	else
	{
		printf("NOT SATISFIED!!\n");
	}
	
	//generate the proof   - TODO:  r1cs_gg_ppzksnark_proof 
    r1cs_ppzksnark_proof<ppT> proof = r1cs_ppzksnark_prover<ppT>(pk, primary_i, aux_i);
	ss = std::stringstream();
	ss << proof;
	printf("proof is serialised\n");
	json pkey;
	pkey["type"] = "libsnark";	//TODO version..
	pkey["proof"] = skUtils::base64_encode(ss.str());
	return pkey;
}



// (2) The "prover", which runs the ppzkSNARK prover on input the proving key,
//     a primary input for CS, and an auxiliary input for CS.
//trustedSetup: json string of the base64 encoded trusted setup
json R1CSUtils::Proof(const std::string &inputsFile, const std::string &trustedSetup)
{
	//init
	InitR1CS();

	//load the inputs
   	r1cs_primary_input<FieldT> primary_input;
	r1cs_auxiliary_input<FieldT> auxiliary_input;
	if (LoadInputs(inputsFile, primary_input, auxiliary_input))
		printf("inputs are loaded\n");
	else
		printf("error with inputs file\n");

	//load trusted setup from file
	json jSetup = skUtils::LoadJsonFromFile(trustedSetup);
	
	return Proover<libff::default_ec_pp>(primary_input, auxiliary_input, jSetup);
}


// (3) The "verifier", which runs the ppzkSNARK verifier on input the verification key,
//    a primary input for CS, and a proof.
//
template<typename ppT>
bool Verifier(const r1cs_primary_input<FieldT>  &primary_input, json & jsetup, json jProof)
{
	//load the verification keys
	r1cs_ppzksnark_verification_key<ppT> vk;
	r1cs_ppzksnark_processed_verification_key<ppT> pvk;
	std::stringstream ss;
	ss << skUtils::base64_decode(jsetup["preprocess_verification_key"]);
	ss >> pvk;
	ss.clear();

	ss << skUtils::base64_decode(jsetup["verification_key"]);
	ss >> vk;
	printf("keys are loaded\n");
	//load the proof
	r1cs_ppzksnark_proof<ppT> proof;

	ss.clear();
	ss << skUtils::base64_decode(jProof["proof"]);
	ss >> proof;
	printf("verifying...\n");
 const bool ans = r1cs_ppzksnark_verifier_strong_IC<ppT>(vk, primary_input, proof);
  //  const bool ans = r1cs_gg_ppzksnark_verifier_strong_IC<ppT>(vk, primary_input, proof);
    printf("* The verification result is: %s\n", (ans ? "PASS" : "FAIL"));

	 r1cs_ppzksnark_processed_verification_key<ppT> pvk2 = r1cs_ppzksnark_verifier_process_vk<ppT>(vk);
	 const bool ans2 = r1cs_ppzksnark_online_verifier_strong_IC<ppT>(pvk2, primary_input, proof);
 //   const bool ans2 = r1cs_gg_ppzksnark_online_verifier_strong_IC<ppT>(pvk, primary_input, proof);
    assert(ans == ans2);
 printf("* The verification result2 is: %s\n", (ans ? "PASS" : "FAIL"));

//TODO  test_affine_verifier<ppT>(vk, primary_input, proof, ans);

    return ans;
}

bool R1CSUtils::Verify(const std::string& tsetup, std::string inputs, std::string proofFile)
{
	//init
	InitR1CS();

	//load keys and inputs
	printf("load inputs\n");
	r1cs_primary_input<FieldT> primary_input, auxiliary_input;
	LoadInputs(inputs, primary_input, auxiliary_input);

	//load trusted setup from file
	json jSetup = skUtils::LoadJsonFromFile(tsetup);

	//load proof from file
	json jProof = skUtils::LoadJsonFromFile(proofFile);

	return Verifier<libff::default_ec_pp>(primary_input, jSetup, jProof);
}
