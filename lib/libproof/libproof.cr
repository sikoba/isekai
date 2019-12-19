
@[Link(ldflags: "#{__DIR__}/libbulletproof.so")]
lib LibProof
  # test..
  fun hello_world() : Void
  fun ping(res : UInt8*)   : Void
  fun bpProve(inputs : UInt8*, proof : UInt8*): Void
  fun bpVerify(inputs : UInt8*, proof : UInt8*): Bool
    
end
