
extern crate rand;
extern crate curve25519_dalek;
extern crate merlin;
extern crate bulletproofs;
extern crate serde;
extern crate serde_json;
extern crate serde_derive;
extern crate num_bigint;

pub mod bp;
pub mod utils;

use std::os::raw::c_char;     //use libc::c_char;??
use std::ffi::CStr;

#[no_mangle]
pub extern "C" fn hello_world() {
    println!("Hello World!");
    utils::test();
}

#[no_mangle]
pub unsafe extern  "C" fn ping(inputs: *const c_char) {
    let raw = CStr::from_ptr(inputs);

    let inputs_str = match raw.to_str() {
        Ok(s) => s,
        Err(_) => return,
    };
    println!("{:?}",inputs_str);
}


#[no_mangle]
pub unsafe extern  "C" fn bpProve(inputs: *const c_char, proofFile: *const c_char) {
    let inputs_str : String = utils::char_to_string(inputs);
    let proof_file : String = utils::char_to_string(proofFile);
    bp::Prove(inputs_str, proof_file);

    //println!("{:?}", stt);

}

#[no_mangle]
pub unsafe extern  "C" fn bpVerify(inputs: *const c_char, proofFile: *const c_char) -> bool
 {
    let inputs_str : String = utils::char_to_string(inputs);
    let proof_file : String = utils::char_to_string(proofFile);
    return bp::Verify(inputs_str, proof_file);
    //println!("{:?}", stt);

}


#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(2 + 2, 4);
    }
}
