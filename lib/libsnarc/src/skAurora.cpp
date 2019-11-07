
#include "skAurora.hpp"
#include "r1cs_libiop.hpp"

#include "libiop/snark/aurora_snark.hpp"

#include "libiop/relations/examples/r1cs_examples.hpp"
#include <libff/algebra/curves/edwards/edwards_pp.hpp>
//#include <libff/algebra/curves/edwards/edwards_pp.hpp>
#include <libff/algebra/curves/alt_bn128/alt_bn128_pp.hpp>

#include <iostream>
#include <sstream>
#include <fstream>

using json = nlohmann::json;

using namespace libiop;

template<class F>
aurora_snark_parameters<F> GenerateParameters(int cs_num, int var_num)
{
  const size_t security_parameter = 128;
    const size_t RS_extra_dimensions = 2;
    const size_t FRI_localization_parameter = 3;
    const LDT_reducer_soundness_type ldt_reducer_soundness_type = LDT_reducer_soundness_type::optimistic_heuristic;
    const FRI_soundness_type fri_soundness_type = FRI_soundness_type::heuristic;
    const field_subset_type domain_type = multiplicative_coset_type;
	const bool make_zk = true;
      aurora_snark_parameters<F> params(security_parameter,
                                               ldt_reducer_soundness_type,
                                               fri_soundness_type,
                                               FRI_localization_parameter,
                                               RS_extra_dimensions,
                                               make_zk,
                                               domain_type,
                                               cs_num,
                                               var_num);
    return params;
}

//Generate the proof from a (trusted) setup
nlohmann::json skAurora::Proof(const std::string &r1cs_filename, const std::string &trustedSetup)
{
  json proof;
  typedef libff::alt_bn128_Fr FieldT;
  alt_bn128_pp::init_public_params();

  R1CSLibiop<FieldT> r1cs;

  std::string inputsFile = r1cs_filename + ".in";

  r1cs_constraint_system<FieldT> cs;
  printf("loading constraints....\n");

  r1cs.FromJsonl(r1cs_filename, cs, true);
  printf("padding...\n");
  r1cs.Pad(cs);

  //load the inputs
  r1cs_primary_input<FieldT> primary_input;
  r1cs_auxiliary_input<FieldT> auxiliary_input;
  if (r1cs.LoadInputs(inputsFile, primary_input, auxiliary_input))
    printf("inputs are loaded\n");
  else
    printf("error with inputs file\n");
  r1cs.PadInputs(primary_input, auxiliary_input, cs.num_constraints());

  if (!cs.is_satisfied(primary_input, auxiliary_input))
    printf("NOT SATISFIED!!!\n");

  /* Actual SNARK test */
  aurora_snark_parameters<FieldT> params = GenerateParameters<FieldT>(cs.num_constraints(), cs.primary_input_size_ + cs.auxiliary_input_size_);

  const aurora_snark_argument<FieldT> argument = aurora_snark_prover<FieldT>(
      cs,
      primary_input,
      auxiliary_input,
      params);

  printf("iop size in bytes %lu\n", argument.IOP_size_in_bytes());
  printf("bcs size in bytes %lu\n", argument.BCS_size_in_bytes());
  printf("argument size in bytes %lu\n", argument.size_in_bytes());

  r1cs.SerializeProof(argument, proof);
  proof["type"] = "aurora";
  return proof;
}

bool skAurora::Verify(const std::string &r1cs_filename, const json &jProof)
{
  //load r1cs
    typedef libff::alt_bn128_Fr FieldT;
    alt_bn128_pp::init_public_params();
    /* Set up R1CS */
    R1CSLibiop<FieldT> r1cs;
  
  std::string inputsFile = r1cs_filename + ".in";
	r1cs_constraint_system<FieldT> cs;
	r1cs.FromJsonl(r1cs_filename, cs, true);
    r1cs.Pad(cs);  
	//load the inputs
  r1cs_primary_input<FieldT> primary_input;
	r1cs_auxiliary_input<FieldT> auxiliary_input;
	if (r1cs.LoadInputs(inputsFile, primary_input, auxiliary_input))
		printf("inputs are loaded\n");
	else
		printf("error with inputs file\n");
r1cs.PadInputs(primary_input, auxiliary_input, cs.num_constraints());
	
  	//load proof

     aurora_snark_argument<FieldT> argument;
     r1cs.DeserializeProof(argument, jProof);

        aurora_snark_parameters<FieldT> params = GenerateParameters<FieldT>( cs.num_constraints(), cs.primary_input_size_+cs.auxiliary_input_size_);


                                                printf("iop size in bytes %lu\n", argument.IOP_size_in_bytes());
        printf("bcs size in bytes %lu\n", argument.BCS_size_in_bytes());
        printf("argument size in bytes %lu\n", argument.size_in_bytes());     
printf("parameters are loaded\n");
 const bool bit = aurora_snark_verifier<FieldT>(
            cs,
            primary_input,
            argument,
            params);

    if (bit == true)
		printf("PASS PASS\n");
	else
		printf("serialization FAILED\n");

     return bit;
}

void skAurora::test()
 {
    
    //edwards_pp::init_public_params();
   // typedef edwards_Fr FieldT;
   
     typedef libff::alt_bn128_Fr FieldT;
    alt_bn128_pp::init_public_params();

    const size_t num_constraints = 1 << 7;
    const size_t num_inputs = (1 << 5) - 1;
    const size_t num_variables = (1 << 7) - 1;
    const size_t security_parameter = 128;
    const size_t RS_extra_dimensions = 2;
    const size_t FRI_localization_parameter = 3;
    const LDT_reducer_soundness_type ldt_reducer_soundness_type = LDT_reducer_soundness_type::optimistic_heuristic;
    const FRI_soundness_type fri_soundness_type = FRI_soundness_type::heuristic;
    const field_subset_type domain_type = multiplicative_coset_type;

    r1cs_example<FieldT> r1cs_params = generate_r1cs_example<FieldT>(
        num_constraints, num_inputs, num_variables);
//	R1CSLibiop<FieldT> rutils;
//   std::string f = "aurora_ex.r1";
//rutils.ToJsonl(r1cs_params.constraint_system_, f);
//rutils.SaveInputs(f+".in",r1cs_params.primary_input_,r1cs_params.auxiliary_input_);

    for (std::size_t i = 0; i < 2; i++) {
        const bool make_zk = (i == 0) ? false : true;
        aurora_snark_parameters<FieldT> params(security_parameter,
                                               ldt_reducer_soundness_type,
                                               fri_soundness_type,
                                               FRI_localization_parameter,
                                               RS_extra_dimensions,
                                               make_zk,
                                               domain_type,
                                               num_constraints,
                                               num_variables);
        const aurora_snark_argument<FieldT> argument = aurora_snark_prover<FieldT>(
            r1cs_params.constraint_system_,
            r1cs_params.primary_input_,
            r1cs_params.auxiliary_input_,
            params);

        printf("iop size in bytes %lu\n", argument.IOP_size_in_bytes());
        printf("bcs size in bytes %lu\n", argument.BCS_size_in_bytes());
        printf("argument size in bytes %lu\n", argument.size_in_bytes());
        const bool bit = aurora_snark_verifier<FieldT>(
            r1cs_params.constraint_system_,
            r1cs_params.primary_input_,
            argument,
            params);
	if (bit == true)
			printf("PASS\n");
		else
			printf("verification FAILED\n");
    }
}