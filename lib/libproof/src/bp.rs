

 //use rand::thread_rng;
 use rand::rngs::OsRng;

 
 use curve25519_dalek::scalar::Scalar;


 use merlin::Transcript;


 use bulletproofs::{BulletproofGens, PedersenGens};

 use bulletproofs::r1cs::*;
 use curve25519_dalek::ristretto::CompressedRistretto;


use std::fs::File;
use std::io::{BufRead, BufReader};
use std::io::Read;
//use std::io::Write;
use std::fs;
use utils;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;


pub struct R1csInputs
{
	input: Vec<Scalar>,
	witness: Vec<Scalar>,
	var: HashMap::<usize, Variable>,
	dbg_allocations: u64
}


impl R1csInputs {
    
	fn as_linear_term(&mut self,  cs: &mut ConstraintSystem, idx: usize, is_prover: bool) -> LinearCombination
	{    	
		if (idx == 0)
    	{
    		return Scalar::from(1_u64) * Variable::One();
    	}
        if (idx <= self.input.len())
        {
        	return self.input[idx-1]*Variable::One();
        }	
		if (is_prover)
		{
			return Scalar::from(1_u64) * self.get_or_allocate(cs, idx, true);
		}
		  return Scalar::one() *  self.get_or_allocate(cs, idx, false);
	}

	fn as_scalar(&mut self, idx: usize) -> Scalar
	{    	
		if (idx == 0)
    	{
    		return Scalar::from(1_u64);
    	}
        if (idx <= self.input.len())
        {
        	return self.input[idx-1];
        }	
		return  self.witness[idx-1-self.input.len()];
		
	}


	fn get_or_allocate(&mut self,  cs: &mut ConstraintSystem, idx: usize, is_prover: bool) -> Variable
    {
    	if (idx == 0)
    	{
    		return Variable::One();
    	}
        std::assert!(idx > self.input.len());			//TODO debug_assert!
		if (self.var.contains_key(&idx))
		{
			return self.var.get(&idx).unwrap().clone();		//TODO to clone or not to clone??
		}
		if (is_prover)
		{
			return self.allocate(cs, idx, self.witness[idx-1-self.input.len()]);
		}
        return self.allocate(cs, idx, Scalar::zero());
    }

	fn allocate(&mut self, cs: &mut ConstraintSystem, idx: usize, c: Scalar) -> Variable
	{	
		self.dbg_allocations += 1;		//DBG - 
		let my_var = cs.allocate(Some(c));
		let var_l = my_var.unwrap().into();
		self.var.insert(idx, var_l);
		return var_l;
	}

	fn set_var(&mut self, idx: usize, var_x : Variable)
	{
		self.var.insert(idx, var_x);
	}
}




//Load inputs from j1cs.in file. If a prover is provided, it also commit to them
pub fn load_inputs<CS: ConstraintSystem>(filename: String, cs: &mut CS, is_prover: bool) ->R1csInputs
{
	let mut r1: R1csInputs = R1csInputs {input: Vec::new(), witness: Vec::new(), var: HashMap::new(), dbg_allocations: 0}; //TODO constructor

	let mut rng = OsRng::new().unwrap();

    // Open the file in read-only mode (ignoring errors).
    let file = File::open(filename).unwrap();
    let mut reader = BufReader::new(file);
	let mut file_data = String::new();
	reader.read_line(&mut file_data).unwrap();
	

	let json: serde_json::Value = serde_json::from_str(&file_data).expect("JSON was not well-formatted");

	let j_inputs: serde_json::Value = json["inputs"].clone();	//TODO should not have to clone...
    let v_inputs: Vec<serde_json::Value> = serde_json::from_value(j_inputs).unwrap();
    let j_witness: serde_json::Value = json["witnesses"].clone();	//TODO should not have to clone...
    let v_witness: Vec<serde_json::Value> = serde_json::from_value(j_witness).unwrap();
    for term in v_inputs.iter()
    {
      	let c_str: String = serde_json::from_value(term.clone()).unwrap();
    	let c: u64 = c_str.parse::<u64>().unwrap();
    	let coef = Scalar::from(c);		//Normally in the inputs we have only 32 bits integer (may be 64 bits),.. BUT not if we use p-complement!! TODO: handle the two cases
    	r1.input.push(coef);
    }
 	if (is_prover)
  	{
		for term in v_witness.iter()
		{
			let c_str: String = serde_json::from_value(term.clone()).unwrap();
			let coef = utils::string_to_scalar(c_str); 	
			r1.witness.push(coef);
			//n.b. We could allocate here, which means we should do the same for the verifier, i.e allocate dummy variables corresponding to the number of witnesses
			//however it is better to have process for prover and verifier in only generate_constraints function
		}

	}

    return r1;
}


pub fn generate_constraints<CS: ConstraintSystem, R: Read>(
    cs: &mut CS,
    reader: &mut BufReader<R>,
	r1: &mut R1csInputs,
    is_prover: bool
)
{
	let mut len = 1;
	let mut line = String::new();
	//Read the file line by line using the lines() iterator from std::io::BufRead.
	while (len != 0)
    {
		line.clear();
		len = reader.read_line(&mut line).unwrap();
      
		if (len > 0)
		{
			// Convert the JSON string
			let json: serde_json::Value =
				serde_json::from_str(&line).expect("JSON was not well-formatted");
			let aslc: serde_json::Value = json["A"].clone();	//TODO should not have to clone...
			let a: Vec<serde_json::Value> = serde_json::from_value(aslc).unwrap();
			let bslc: serde_json::Value = json["B"].clone();	//TODO should not have to clone...
			let b: Vec<serde_json::Value> = serde_json::from_value(bslc).unwrap();
			let cslc: serde_json::Value = json["C"].clone();	//TODO should not have to clone...
			let c: Vec<serde_json::Value> = serde_json::from_value(cslc).unwrap();

			let A_lc = parseLinearCombJson(a, r1, cs, is_prover);
			let B_lc = parseLinearCombJson(b, r1, cs, is_prover);
			let c_idx: usize =  serde_json::from_value(c[0][0].clone()).unwrap();
			let c_str: String = serde_json::from_value(c[0][1].clone()).unwrap();
			if (c.len() == 1 && c_idx > 0 &&  c[0][1] == "1" && !r1.var.contains_key(&c_idx)) //TODO A TESTER!!
			{
				let (_, _, var_c) =  cs.multiply(A_lc, B_lc);
				r1.set_var(c_idx, var_c.into());
			}
			else
			{
				let C_lc = parseLinearCombJson(c, r1, cs, is_prover);
				let (_, _, o) =  cs.multiply(A_lc, B_lc);
				cs.constrain(o-C_lc);
	
			}

		}
 
    }
	
}


//Generate a proof
//inputs: file name of the r1cs in json format. We need the full assignments as .in file
//proof_file: file name of the out file that will contain the proof in json format.
pub fn Prove(inputs: String, proof_file: String)
{
	let inputfile = format!("{}{}",inputs,".in");
    //1. Open the j1cs file in read-only mode (ignoring errors).
    let file = File::open(inputs).unwrap();
    let mut reader = BufReader::new(file);
	let mut line = String::new();
	let mut len = reader.read_line(&mut line).unwrap();
	if (len == 0)
	{
		println!("ERRROR, file is empty");
		return;
	}
	//2. parse header
	let json: serde_json::Value = serde_json::from_str(&line).expect("JSON was not well-formatted");
	let header: serde_json::Value = json["r1cs"].clone();
	let constraint_nb : u32 =	serde_json::from_value(header["constraint_nb"].clone()).unwrap();
	let instance_nb : u32 =	serde_json::from_value(header["instance_nb"].clone()).unwrap();
	let witness_nb : u32 =	serde_json::from_value(header["witness_nb"].clone()).unwrap();
	let gen_nb = 1 << (utils::bits(constraint_nb+witness_nb));					//TODO count the nb of allocations
	println!("generator length =  {:?}", gen_nb);
	let prime_str: String = serde_json::from_value(header["field_characteristic"].clone()).unwrap();
    let prime = utils::string_to_scalar(prime_str);
	if (curve25519_dalek::constants::BASEPOINT_ORDER != prime)
	{
		println!("Invalid field characteristic");
		println!("Please make sure constraints where generated with the correct scheme");
		return;
	}
	//3. Create some generators that will be used by both the prover and verifier
	let pc_gens = PedersenGens::default();
	let bp_gens = BulletproofGens::new(gen_nb, 1);
		
	//4. Instantiate a prover
	let mut prover_transcript = Transcript::new(b"r1cs");
	let mut prover = Prover::new(&pc_gens, &mut prover_transcript);

	//5. Load inputs from .r1cs.in file:
	let mut r1 = load_inputs(inputfile, &mut prover, true);
	println!("...loading input file");
	
    //6. Read the file line by line using the lines() iterator from std::io::BufRead.
	generate_constraints(&mut prover, &mut reader, &mut r1, true);
	println!("constraints are generated - {:?} allocations", r1.dbg_allocations);
    //7. Prover creates the proof
	let proof = prover.prove(&bp_gens).unwrap();

	//8. Serialize into json
	let mut jproof : JsonProof = JsonProof { proof: Vec::new(), name: "no comment".to_string(), scheme: "dalek-bulletproof".to_string()};//TODO constructor

	jproof.proof = proof.to_bytes();
	let serialized = serde_json::to_string(&jproof).unwrap();
	//8. Saave to file
	fs::write(proof_file, serialized);
}


//Verify a proof, from a proof file (proof_file) and j1cs file (filename)
//inputs: file name of the r1cs in json format. The public inputs must also be present as .in
//proof_file: file name of the proof in json format.
pub fn Verify(inputs: String, proof_file: String) -> bool
{
	let inputfile = format!("{}{}",inputs,".in");
    //1. Open the j1cs file in read-only mode (ignoring errors).
    let file = File::open(inputs).unwrap();
    let mut reader = BufReader::new(file);
	let mut line = String::new();
	let mut len = reader.read_line(&mut line).unwrap();
	if (len == 0)
	{
		println!("ERRROR, file is empty");
		return false;
	}
	//2. parse header
	let json: serde_json::Value = serde_json::from_str(&line).expect("JSON was not well-formatted");
	let header: serde_json::Value = json["r1cs"].clone();
	let constraint_nb : u32 =	serde_json::from_value(header["constraint_nb"].clone()).unwrap();
	let instance_nb : u32 =	serde_json::from_value(header["instance_nb"].clone()).unwrap();
	let witness_nb : u32 =	serde_json::from_value(header["witness_nb"].clone()).unwrap();
	let gen_nb = 1 << (utils::bits(constraint_nb+witness_nb));
	println!("generator length =  {:?}", gen_nb);
	//3. Create some generators that will be used by both the prover and verifier
	let pc_gens = PedersenGens::default();
	let bp_gens = BulletproofGens::new(gen_nb, 1);

	//4. Instantiate a the verifier
	let mut verifier_transcript = Transcript::new(b"r1cs");
	let mut verifier = Verifier::new(&mut verifier_transcript);

		
	//5. Load the proof
   	let data = fs::read_to_string(proof_file).expect("Unable to read proof file");
   	let my_proof : JsonProof = serde_json::from_str(&data).unwrap();
   	let proof : R1CSProof = R1CSProof::from_bytes(&my_proof.proof).unwrap();
	println!("proof  is loaded");
	//6. Load inputs from .r1cs1.in file:
	let mut r1: R1csInputs = load_inputs(inputfile,  &mut verifier, false);
    //8. Read the file line by line using the lines() iterator from std::io::BufRead.
	generate_constraints(&mut verifier, &mut reader, &mut r1, false);
   	println!("commit is done");

	//9. Finally the verifier verifies the proof.
	if (verifier.verify(&proof, &pc_gens, &bp_gens).is_ok())
	{
		println!("verification SUCCESS");
    	return true;
	}
	else
	{
		println!("verification FAIL");
	}
	//Ok(verifier.verify(&proof, &pc_gens, &bp_gens)?);
  	return false;
}


#[derive(Serialize, Deserialize, Debug)]
struct JsonProof {
    proof: Vec<u8>,
    name: String,
	scheme: String
}





//Parse a json array (A, B or C), into the bulletproof type
fn parseLinearCombJson(jlc: Vec<serde_json::Value>, r1: &mut R1csInputs, cs: &mut ConstraintSystem, is_prover: bool) -> LinearCombination
{
	let mut lc: LinearCombination = LinearCombination::default();
	
	if (jlc.len() == 0 )
	{
		return lc;
	}
	let mut first: bool = true;
	for term in jlc.iter()
	{
      	//TODO handle negative index
 		let idx: usize =  serde_json::from_value(term[0].clone()).unwrap();
    	let c_str: String = serde_json::from_value(term[1].clone()).unwrap();
    	let coef = utils::string_to_scalar(c_str);//Handle big integers. TODO check this is correct
   		if (first == true)
    	{
    		lc = coef * r1.as_linear_term(cs, idx, is_prover);
     		first = false;
    	}
    	else 
    	{
    		lc = lc + (coef * r1.as_linear_term(cs, idx, is_prover));
    	}
  	}
  	return lc;
}


