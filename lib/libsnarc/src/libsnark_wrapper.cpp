
#include "libsnark_wrapper.hpp"
#include "r1cs_utils.hpp"
#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_ppzksnark/examples/run_r1cs_ppzksnark.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_gg_ppzksnark/r1cs_gg_ppzksnark.hpp>


using json = nlohmann::json;




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

// (1) The "generator", which runs the ppzkSNARK generator on input a given
//     constraint system CS to create a proving and a verification key for CS.
template<typename ppT>
json TrustedSetup_gg(const r1cs_constraint_system<FieldT>  &cs)
{

	r1cs_gg_ppzksnark_keypair<ppT> keypair = r1cs_gg_ppzksnark_generator<ppT>(cs);

    libff::print_header("Preprocess verification key");
    r1cs_gg_ppzksnark_processed_verification_key<ppT> pvk = r1cs_gg_ppzksnark_verifier_process_vk<ppT>(keypair.vk);

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



bool Snarks::Arith2Jsonl(const std::string &arithFile, const std::string &inputsFile, const std::string &outFile)
{
	json assignments;
	R1CSUtils r1cs;
	r1cs_constraint_system<FieldT> constraints = r1cs.GenerateFromArithFile(arithFile, inputsFile, assignments);
    return r1cs.ToJsonl(constraints, outFile) && skUtils::WriteJson2File(outFile + ".in", assignments);
}


bool TS(const std::string &jr1cs, std::string &ts, Snarks::zkp_scheme scheme)
{
	R1CSUtils r1cs;
	r1cs_constraint_system<FieldT> cs;
	if (skUtils::endsWith(jr1cs, ".arith"))
	{
		json dummy;
		cs = r1cs.GenerateFromArithFile(jr1cs, jr1cs.substr(0, jr1cs.size()-5) + "in", dummy);

	}
	else
		r1cs.FromJsonl(jr1cs, cs);
		
	if (scheme == Snarks::zkp_scheme::groth16)
	{
		json j_ts = TrustedSetup_gg<libff::default_ec_pp>(cs);
		ts = j_ts.dump();
	}
	else
	{
		json j_ts = TrustedSetup<libff::default_ec_pp>(cs);
		ts = j_ts.dump();
	}	
    return true;
}


bool Snarks::VCSetup(const std::string &jr1cs , std::string &ts, zkp_scheme scheme)
{
	R1CSUtils r1cs;
	r1cs.InitR1CS();
	ts = "an error occured";
	return TS(jr1cs, ts, scheme);
}


template<typename ppT>
json Proover_pp(const	r1cs_primary_input<FieldT>& primary_i,	const r1cs_auxiliary_input<FieldT>& aux_i, const json &j_ts)
{
	//load the proving key
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
	
	//generate the proof
    r1cs_ppzksnark_proof<ppT> proof = r1cs_ppzksnark_prover<ppT>(pk, primary_i, aux_i);
	ss = std::stringstream();
	ss << proof;
	printf("proof is serialised\n");
	json pkey;
	pkey["type"] = "bctv14a";	//TODO version..
	pkey["proof"] = skUtils::base64_encode(ss.str());
	return pkey;
}


template<typename ppT>
json Proover_gg(const	r1cs_primary_input<FieldT>& primary_i,	const r1cs_auxiliary_input<FieldT>& aux_i, const json &j_ts)
{
	//load the proving key
	r1cs_gg_ppzksnark_proving_key<ppT> pk;
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
	
	//generate the proof
    r1cs_gg_ppzksnark_proof<ppT> proof = r1cs_gg_ppzksnark_prover<ppT>(pk, primary_i, aux_i);
	ss = std::stringstream();
	ss << proof;
	printf("proof is serialised\n");
	json pkey;
	pkey["type"] = "groth16";	//TODO version..
	pkey["proof"] = skUtils::base64_encode(ss.str());
	return pkey;
}



// (2) The "prover", which runs the ppzkSNARK prover on input the proving key,
//     a primary input for CS, and an auxiliary input for CS.
//trustedSetup: json string of the base64 encoded trusted setup
json Snarks::Proof(const std::string &inputsFile, const std::string &trustedSetup, zkp_scheme scheme)
{
	//init
	R1CSUtils r1cs;
	r1cs.InitR1CS();

	//load the inputs
   	r1cs_primary_input<FieldT> primary_input;
	r1cs_auxiliary_input<FieldT> auxiliary_input;
	if (r1cs.LoadInputs(inputsFile, primary_input, auxiliary_input))
		printf("inputs are loaded\n");
	else
		printf("error with inputs file\n");

	//load trusted setup from file
	json jSetup = skUtils::LoadJsonFromFile(trustedSetup);

	switch (scheme)
	{
	case groth16:
		return Proover_gg<libff::default_ec_pp>(primary_input, auxiliary_input, jSetup);
		break;
	case bctv14a:
		return Proover_pp<libff::default_ec_pp>(primary_input, auxiliary_input, jSetup);
		break;
	default:
		printf("ERROR - Non supported scheme!!\n");
		break;
	}
	return jSetup.empty();
	
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

// (3) The "verifier", which runs the ppzkSNARK verifier on input the verification key,
//    a primary input for CS, and a proof.
//
template<typename ppT>
bool Verifier_gg(const r1cs_primary_input<FieldT>  &primary_input, json & jsetup, json jProof)
{
	//load the verification keys
	r1cs_gg_ppzksnark_verification_key<ppT> vk;
	r1cs_gg_ppzksnark_processed_verification_key<ppT> pvk;
	std::stringstream ss;
	ss << skUtils::base64_decode(jsetup["preprocess_verification_key"]);
	ss >> pvk;
	ss.clear();

	ss << skUtils::base64_decode(jsetup["verification_key"]);
	ss >> vk;
	printf("keys are loaded\n");
	//load the proof
	r1cs_gg_ppzksnark_proof<ppT> proof;

	ss.clear();
	ss << skUtils::base64_decode(jProof["proof"]);
	ss >> proof;
	printf("verifying...\n");
 	const bool ans = r1cs_gg_ppzksnark_verifier_strong_IC<ppT>(vk, primary_input, proof);
    printf("* The verification result is: %s\n", (ans ? "PASS" : "FAIL"));

	r1cs_gg_ppzksnark_processed_verification_key<ppT> pvk2 = r1cs_gg_ppzksnark_verifier_process_vk<ppT>(vk);
	const bool ans2 = r1cs_gg_ppzksnark_online_verifier_strong_IC<ppT>(pvk2, primary_input, proof);
    assert(ans == ans2);
 	printf("* The verification result2 is: %s\n", (ans ? "PASS" : "FAIL"));
//TODO  test_affine_verifier<ppT>(vk, primary_input, proof, ans);

    return ans;
}

bool Snarks::Verify(const std::string& tsetup, std::string inputs, std::string proofFile)
{
	R1CSUtils r1cs;
	//init
	r1cs.InitR1CS();

	//load keys and inputs
	printf("load inputs\n");
	r1cs_primary_input<FieldT> primary_input, auxiliary_input;
	r1cs.LoadInputs(inputs, primary_input, auxiliary_input);

	//load trusted setup from file
	json jSetup = skUtils::LoadJsonFromFile(tsetup);

	//load proof from file
	json jProof = skUtils::LoadJsonFromFile(proofFile);
	if (jProof["type"] == "groth16")
	{
		return Verifier_gg<libff::default_ec_pp>(primary_input, jSetup, jProof);
	}
	else if (jProof["type"] == "bctv14a")
	{
		return Verifier<libff::default_ec_pp>(primary_input, jSetup, jProof);
	}
	else
	{
		printf("invalid type %s", jProof["type"]);
	}
	return false;
	
}

