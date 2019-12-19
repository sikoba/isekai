use std::os::raw::c_char;     //use libc::c_char;??
use std::ffi::CStr;
use num_bigint::BigUint;
use std::str::FromStr;



pub unsafe fn char_to_string(input: *const c_char) -> String
{
	let res : String = "".to_string();
	 if input.is_null()
	 {
        return res;
    }

	let raw = CStr::from_ptr(input);

    let res = match raw.to_str() {
        Ok(s) => s,
       	Err(_) => return res.to_string(),
    };
    return res.to_string();
}


pub fn string_to_scalar(input: String) -> curve25519_dalek::scalar::Scalar
{
    let c_big : BigUint = BigUint::from_str(&input).unwrap();
    let mut c_bytes : [u8; 32] = [  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,];
    let c_vec = c_big.to_bytes_le();
    let mut i = 0;
    for cb in c_vec
    {
    	c_bytes[i] = cb;
       	i+=1;
    }
    return curve25519_dalek::scalar::Scalar::from_bits(c_bytes);//puis tester avec println!("{:?}", s.to_bytes()); igint: string->bigint->bytes->scalar (et a retransformer en string pour tester):
}

//Returns the bit size of the input
pub fn bits(a: u32) -> u32
{
    let mut i = a;
    let mut bits = 0;
    while (i !=0)
    {
        i=i>>1;
        bits = bits + 1;
    }
    return bits
}

pub fn test()
{
	    let t1 : String= "4975441334397345751130612518500927154628011511324180036903450236863266160640".to_string();
	    let s1 = string_to_scalar(t1);
	  //  let s2 = curve25519_dalek::scalar::Scalar::from(2144653_u64);
	    println!("{:?}",s1.to_bytes());
	   // println!("{:?}",s2.to_bytes());
}