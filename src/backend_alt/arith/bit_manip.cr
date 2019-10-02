require "intrinsics"

module Isekai::AltBackend::Arith::BitManip

@[AlwaysInline]
def self.nbits (c : UInt128) : Int32
    128 - Intrinsics.countleading128(c, zero_is_undef: false)
end

end
