module Isekai::AltBackend::Arith::BitManip

@[AlwaysInline]
def self.nbits (c : UInt128) : Int32
    128 - c.leading_zeros_count
end

end
