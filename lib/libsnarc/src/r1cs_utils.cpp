
#include "r1cs_utils.hpp"

#include <libsnark/gadgetlib2/integration.hpp>
#include <libsnark/gadgetlib2/adapters.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_ppzksnark/examples/run_r1cs_ppzksnark.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_gg_ppzksnark/r1cs_gg_ppzksnark.hpp>


using json = nlohmann::json;

//Initialize the parameters
void R1CSUtils::InitR1CS()
{
	gadgetlib2::initPublicParamsFromDefaultPp();
	gadgetlib2::GadgetLibAdapter::resetVariableIndex();
}

json R1CSUtils::LinearCombination2Json(linear_combination<FieldT> vec)
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




linear_combination<FieldT> R1CSUtils::parseLinearCombJson(json &jlc)
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
json R1CSUtils::Inputs2Json(const r1cs_primary_input<FieldT> &primary_input,const r1cs_auxiliary_input<FieldT> &auxiliary_input)
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

bool R1CSUtils::SaveInputs(const std::string jsonFile, const r1cs_primary_input<FieldT> &primary_input,const r1cs_auxiliary_input<FieldT> &auxiliary_input)
{
	json jValue = Inputs2Json(primary_input, auxiliary_input);
	return skUtils::WriteJson2File(jsonFile, jValue);
}

r1cs_constraint_system<FieldT> R1CSUtils::GenerateFromArithFile(const std::string &fname, const std::string &inputValues, json & assignments)
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





bool R1CSUtils::ToJsonl(r1cs_constraint_system<FieldT>  &in_cs, const std::string &out_fname)
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

bool R1CSUtils::FromJsonl(const std::string jsonFile, r1cs_constraint_system<FieldT> &out_cs)
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
bool R1CSUtils::LoadInputs(const std::string jsonFile, r1cs_primary_input<FieldT> &primary_input, r1cs_auxiliary_input<FieldT> &auxiliary_input)
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


