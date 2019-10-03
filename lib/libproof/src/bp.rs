

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


pub struct R1csInputs
{
	input: Vec<Scalar>,
	witnesses: Vec<Variable>,
	commitments: Vec<CompressedRistretto>
}


impl R1csInputs {
    fn get_linear_term(&self, idx: usize, c: Scalar) -> LinearCombination
    {
    	if (idx == 0)
    	{
    		return c*Variable::One();
    	}
        if (idx <= self.input.len())
        {
        	return c*self.input[idx-1]*Variable::One();
        }	
        return c*self.witnesses[idx-1-self.input.len()];
    }
}


fn copy_a_fucking_string(input: &str) -> String {
   let mut buf = String::with_capacity(input.len());

   for c in input.chars() { 
    	buf.push(c);
   }

   buf
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
	let gen_nb = 1 << utils::bits(constraint_nb);
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

	//5. Load inputs from .r1cs1.in file:
	let r1 = load_inputs(inputfile, Some(&mut prover));
	println!("...loading input file");
    //6. Read the file line by line using the lines() iterator from std::io::BufRead.
	while (len != 0)
    {
		line.clear();
		len = reader.read_line(&mut line).unwrap();
        // Convert the JSON string.
		if (len > 0)
		{
			let json: serde_json::Value =
				serde_json::from_str(&line).expect("JSON was not well-formatted");

			let aslc: serde_json::Value = json["A"].clone();	//TODO should not have to clone...
			let a: Vec<serde_json::Value> = serde_json::from_value(aslc).unwrap();
			let A_lc = parseLinearCombJson(a, &r1);
			let bslc: serde_json::Value = json["B"].clone();	//TODO should not have to clone...
			let b: Vec<serde_json::Value> = serde_json::from_value(bslc).unwrap();
			let B_lc = parseLinearCombJson(b, &r1);
			let cslc: serde_json::Value = json["C"].clone();	//TODO should not have to clone...
			let c: Vec<serde_json::Value> = serde_json::from_value(cslc).unwrap();
			let C_lc = parseLinearCombJson(c, &r1);
			
			//TODO callback call so we can use one code for proving and verifying
			let (_, _, o) =  prover.multiply(A_lc, B_lc);
			prover.constrain(o-C_lc);
		}
 
    }
	

    //7. Prover creates the proof
	let proof = prover.prove(&bp_gens).unwrap();

	//8. Serialize into json
	//TODO somebody tells me how to copy a f**/*/* string??
	let mut jproof : JsonProof = JsonProof { proof: Vec::new(), raw_commitments: Vec::new(), name: "no comment".to_string(), scheme: "dalek-bulletproof".to_string()};//TODO constructor

	jproof.proof = proof.to_bytes();
	for (commitment) in r1.commitments
	{
		jproof.raw_commitments.push( commitment.to_bytes());
	}
	let serialized = serde_json::to_string(&jproof).unwrap();
	//8. Saave to file
	fs::write(proof_file, serialized);
}

//TODO;
//1. Proove()
//fait le 'loadr1cs', et genere la preuve + commitments
//sauve le tout dans le json de preuve  (CompressedRistretto.to_bytes(&self) -> [u8; 32]))  et R1CSProof.to_bytes
//2. verify()
//parser le json de preuve et recuperer la preuve +commitments (fn from_slice(bytes: &[u8]) -> CompressedRistretto)  et R1CSProof.from_bytes
//parser les inputs, puis le r1cs pour generer les combinaisons lineaires
//verifier la preuve
//REM: a faire valider par Dmitry +  comparer avec la version de qed-it
//REM: les combinaison linearies pour preuve+verif devraient se faire avec la MEME fonction qui utilise le trait ConstraintSytem...mais rust est trop chiant.


#[derive(Serialize, Deserialize, Debug)]
struct JsonProof {
    proof: Vec<u8>,
    raw_commitments: Vec<[u8; 32]>,
    name: String,
	scheme: String
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
	let gen_nb = 1 << utils::bits(constraint_nb);
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
	let mut r1: R1csInputs = load_inputs(inputfile,  None);
	//7. Verifier using the commitments.	
  	for (commitment) in my_proof.raw_commitments
	{
		let crs : CompressedRistretto = CompressedRistretto::from_slice(&commitment);
		
		let var_x = verifier.commit(crs);
		r1.witnesses.push(var_x);
	}



    //8. Read the file line by line using the lines() iterator from std::io::BufRead.
	while (len != 0)
    {
		line.clear();
		len = reader.read_line(&mut line).unwrap();
        // Convert the JSON string.
		if (len > 0)
		{
			let json: serde_json::Value =
				serde_json::from_str(&line).expect("JSON was not well-formatted");

			let aslc: serde_json::Value = json["A"].clone();	//TODO should not have to clone...
			let a: Vec<serde_json::Value> = serde_json::from_value(aslc).unwrap();
			let A_lc = parseLinearCombJson(a, &r1);
			let bslc: serde_json::Value = json["B"].clone();	//TODO should not have to clone...
			let b: Vec<serde_json::Value> = serde_json::from_value(bslc).unwrap();
			let B_lc = parseLinearCombJson(b, &r1);
			let cslc: serde_json::Value = json["C"].clone();	//TODO should not have to clone...
			let c: Vec<serde_json::Value> = serde_json::from_value(cslc).unwrap();
			let C_lc = parseLinearCombJson(c, &r1);
			
			//TODO callback call so we can use one code for proving and verifying
			let (_, _, ov) =  verifier.multiply(A_lc, B_lc);
 			verifier.constrain(ov-C_lc);
		}
 
    }

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

//Load inputs from j1cs.in file. If a prover is provided, it also commit to them
fn load_inputs(filename: String, prover: Option<&mut bulletproofs::r1cs::Prover>) ->R1csInputs
{
	let mut r1: R1csInputs = R1csInputs {input: Vec::new(), witnesses: Vec::new(), commitments: Vec::new()}; //TODO constructor

	let mut rng = OsRng::new().unwrap();

    // Open the file in read-only mode (ignoring errors).
    let file = File::open(filename).unwrap();
    let mut reader = BufReader::new(file);
	let mut file_data = String::new();
	reader.read_line(&mut file_data).unwrap();
	

	let json: serde_json::Value =
    	serde_json::from_str(&file_data).expect("JSON was not well-formatted");

	  let j_inputs: serde_json::Value = json["inputs"].clone();	//TODO should not have to clone...
    let v_inputs: Vec<serde_json::Value> = serde_json::from_value(j_inputs).unwrap();
    let j_witness: serde_json::Value = json["witnesses"].clone();	//TODO should not have to clone...
    let v_witness: Vec<serde_json::Value> = serde_json::from_value(j_witness).unwrap();
    for term in v_inputs.iter()
    {
      let c_str: String = serde_json::from_value(term.clone()).unwrap();
      println!("value = {:?}", c_str);
    	let c: u64 = c_str.parse::<u64>().unwrap();
    	let coef = Scalar::from(c);		//Normally in the inputs we have only 32 bits integer (may be 64 bits),.. BUT not if we use p-complement!! TODO

    	r1.input.push(coef);
    }
    match prover {
    	None => return r1,
    	Some(p) => {

    for term in v_witness.iter()
    {
    	//let c: u64 = serde_json::from_value(term.clone()).unwrap();
    	//let coef = Scalar::from(c); 
      let c_str: String = serde_json::from_value(term.clone()).unwrap();
      let coef = utils::string_to_scalar(c_str); 	

		//Prover commits to variables
		let x = Scalar::random(&mut rng);
		
    let (com_x, var_x) = p.commit(coef.into(), x);
		r1.witnesses.push(var_x);
		r1.commitments.push(com_x); 	
    }

    }
    }


    return r1;
}

//Parse a json array (A, B or C), into the bulletproof type
fn parseLinearCombJson(jlc: Vec<serde_json::Value>, r1: &R1csInputs) -> LinearCombination
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
    //let c: u64 = serde_json::from_value(term[1].clone()).unwrap();
    let c_str: String = serde_json::from_value(term[1].clone()).unwrap();
    let coef = utils::string_to_scalar(c_str);//Handle big integers. TODO check this is correct
    if (first == true)
    {
    		lc = r1.get_linear_term(idx,coef);
     		first = false;
    }
    else 
    {
    		lc =  lc + r1.get_linear_term(idx,coef);
    }
  }
  return lc;
}
