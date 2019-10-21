
#[Link("snarc")]
@[Link(ldflags: "#{__DIR__}/libsnarc.a -lstdc++ -L#{__DIR__}/ -lsnark -liop -lsodium -lff -lgmp -lm -lzm -lprocps")]
lib LibSnarc
  # test..
  fun test(name : UInt8*) : Void
    fun MyFunction(res : UInt8**) : Bool

  fun generateR1cs(arithFile : UInt8*, inputsFile : UInt8*, r1csFile : UInt8*) : Void
  fun vcSetup(r1csFile : UInt8*, setupFile : UInt8*, scheme : UInt8) : Void   #ts : UInt8**
  fun Prove(setup: UInt8*, inputs : UInt8*, proof : UInt8*, scheme : UInt8): UInt8*
  fun Verify(setup: UInt8*, inputs : UInt8*, proof : UInt8*): Bool
  #fun ProofTest() : Void
end
