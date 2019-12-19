require "../../lib/libsnarc/libsnarc.cr"


class LibSnark

  def generateR1cs(arith_file : String, input_file : String, r1cs_outfile : String)
    LibSnarc.generateR1cs(arith_file, input_file, r1cs_outfile)
  end

  def vcSetup(r1cs_file : String, setup_outfile : String, scheme : UInt8)
    LibSnarc.vcSetup(r1cs_file, setup_outfile, scheme)
  end

  def proof(setup_file : String, inputs_file : String, proof_outfile : String, scheme : UInt8)
    LibSnarc.Prove(setup_file, inputs_file, proof_outfile, scheme)
  end

  def verify(setup_file : String, inputs_file : String, proof_outfile : String) : Bool
    return LibSnarc.Verify(setup_file, inputs_file, proof_outfile)
  end
end
