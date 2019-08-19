require "intrinsics"

module Isekai::AltBackend::BitManip

@[AlwaysInline]
def self.nbits (c : UInt128) : Int32
    128 - Intrinsics.countleading128(c, zero_is_undef: false)
end

@[AlwaysInline]
def self.min (a, b)
    a < b ? a : b
end

@[AlwaysInline]
def self.max (a, b)
    a > b ? a : b
end

end
