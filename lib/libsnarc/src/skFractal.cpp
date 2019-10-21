
#include "skFractal.hpp"
#include "r1cs_libiop.hpp"

#include "libiop/snark/fractal_snark.hpp"

#include <libiop/relations/examples/r1cs_examples.hpp>
#include <libff/algebra/curves/alt_bn128/alt_bn128_pp.hpp>

#include <iostream>
#include <sstream>
#include <fstream>

using json = nlohmann::json;

using namespace libiop;


 //Generate the proof from a (trusted) setup
nlohmann::json skFractal::Proof(const std::string &r1cs_filename,  const std::string &trustedSetup)
{
    json proof;     //TODO serialize the proof...
    typedef libff::alt_bn128_Fr FieldT;
    alt_bn128_pp::init_public_params();

	R1CSLibiop<FieldT> r1cs;
    
    const size_t security_parameter = 128;
    const size_t RS_extra_dimensions = 2;
    const size_t FRI_localization_parameter = 3;
    const LDT_reducer_soundness_type ldt_reducer_soundness_type = LDT_reducer_soundness_type::optimistic_heuristic;
    const FRI_soundness_type fri_soundness_type = FRI_soundness_type::heuristic;
    const field_subset_type domain_type = multiplicative_coset_type;
	const bool make_zk = true;

	std::string inputsFile = r1cs_filename + ".in";


	r1cs_constraint_system<FieldT> cs;
     printf("loading constraints...\n");
	r1cs.FromJsonl(r1cs_filename, cs);
    r1cs.Pad(cs);       
	//load the inputs
   	r1cs_primary_input<FieldT> primary_input;
	r1cs_auxiliary_input<FieldT> auxiliary_input;
	if (r1cs.LoadInputs(inputsFile, primary_input, auxiliary_input))
		printf("inputs are loaded\n");
	else
		printf("error with inputs file\n");
    r1cs.PadInputs(primary_input);
	if(!cs.is_satisfied(primary_input, auxiliary_input))
		printf("NOT SATISFIED!!!\n");

    std::shared_ptr<r1cs_constraint_system<FieldT>> cs_ =
        std::make_shared<r1cs_constraint_system<FieldT>>(cs);

    /* Actual SNARK test */
    fractal_snark_parameters<FieldT> params(security_parameter,
                                               ldt_reducer_soundness_type,
                                               fri_soundness_type,
                                               FRI_localization_parameter,
                                               RS_extra_dimensions,
                                               make_zk,
                                               domain_type,
                                               cs_);

    std::pair<bcs_prover_index<FieldT>, bcs_verifier_index<FieldT>> index = fractal_snark_indexer(params);
    const fractal_snark_argument<FieldT> argument = fractal_snark_prover<FieldT>(
            index.first,
            primary_input,
            auxiliary_input,
            params);

        printf("iop size in bytes %lu\n", argument.IOP_size_in_bytes());
        printf("bcs size in bytes %lu\n", argument.BCS_size_in_bytes());
        printf("argument size in bytes %lu\n", argument.size_in_bytes());

    const bool bit = fractal_snark_verifier<FieldT>(
            index.second,
            primary_input,
            argument,
            params);

	if (bit == true)
		printf("PASS\n");
	else
		printf("verification FAILED\n");
        
    return proof;
}


void skFractal::test()
{
    typedef libff::alt_bn128_Fr FieldT;
    alt_bn128_pp::init_public_params();
      const size_t num_constraints = 1 << 10;
    const size_t num_inputs = (1 << 5) - 1;
    const size_t num_variables = (1 << 10) - 1;
    const size_t security_parameter = 128;
    const size_t RS_extra_dimensions = 2;
    const size_t FRI_localization_parameter = 3;
    const LDT_reducer_soundness_type ldt_reducer_soundness_type = LDT_reducer_soundness_type::optimistic_heuristic;
    const FRI_soundness_type fri_soundness_type = FRI_soundness_type::heuristic;
    const field_subset_type domain_type = multiplicative_coset_type;

    r1cs_example<FieldT> r1cs_params = generate_r1cs_example<FieldT>(
        num_constraints, num_inputs, num_variables);

    std::shared_ptr<r1cs_constraint_system<FieldT>> cs =
        std::make_shared<r1cs_constraint_system<FieldT>>(r1cs_params.constraint_system_);

    /* Actual SNARK test */
    for (std::size_t i = 0; i < 2; i++) {
        const bool make_zk = (i == 0) ? false : true;
        fractal_snark_parameters<FieldT> params(
            security_parameter,
            ldt_reducer_soundness_type,
            fri_soundness_type,
            FRI_localization_parameter,
            RS_extra_dimensions,
            make_zk,
            domain_type,
            cs);
        std::pair<bcs_prover_index<FieldT>, bcs_verifier_index<FieldT>> index =
            fractal_snark_indexer(params);
        const fractal_snark_argument<FieldT> argument =
            fractal_snark_prover<FieldT>(
            index.first,
            r1cs_params.primary_input_,
            r1cs_params.auxiliary_input_,
            params);

        printf("iop size in bytes %lu\n", argument.IOP_size_in_bytes());
        printf("bcs size in bytes %lu\n", argument.BCS_size_in_bytes());
        printf("argument size in bytes %lu\n", argument.size_in_bytes());

        const bool bit = fractal_snark_verifier<FieldT>(
            index.second,
            r1cs_params.primary_input_,
            argument,
            params);

if (bit == true)
		printf("PASS\n");
	else
		printf("verification FAILED\n");
        
    }
}