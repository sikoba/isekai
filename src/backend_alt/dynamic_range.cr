require "./bit_manip"

module Isekai::AltBackend

private struct DynamicRange
    @min_value : UInt64
    @max_value : UInt64

    def initialize (@min_value : UInt64, @max_value : UInt64)
    end

    def self.new_for (constant value : UInt64)
        return self.new(min_value: value, max_value: value)
    end

    def self.new_for (bitwidth : BitWidth)
        return self.new(min_value: 0, max_value: bitwidth.mask)
    end

    def self.new_bool
        return self.new(min_value: 0, max_value: 1)
    end

    def add (other : DynamicRange, bitwidth : BitWidth) : {DynamicRange, Bool}
        new_max, overflow = BitManip.add_in_bitwidth(@max_value, other.@max_value, bitwidth)
        if overflow
            return {DynamicRange.new_for(bitwidth), true}
        else
            new_min = bitwidth.truncate(@min_value + other.@min_value)
            return {DynamicRange.new(new_min, new_max), false}
        end
    end

    def mul (other : DynamicRange, bitwidth : BitWidth) : {DynamicRange, Bool}
        new_max, overflow = BitManip.mul_in_bitwidth(@max_value, other.@max_value, bitwidth)
        if overflow
            return {DynamicRange.new_for(bitwidth), true}
        else
            new_min = bitwidth.truncate(@min_value * other.@min_value)
            return {DynamicRange.new(new_min, new_max), false}
        end
    end

    def fits_into_1bit?
        @max_value <= 1
    end

    def max_nbits
        BitManip.nbits(@max_value)
    end
end

end
