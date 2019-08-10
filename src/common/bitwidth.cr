module Isekai

class BitWidthsIncompatible < Exception
end

struct BitWidth

    @[AlwaysInline]
    def self.all_ones (n)
        (1_i64 << n) - 1
    end

    UNSPECIFIED = -1
    POINTER = 0

    @[AlwaysInline]
    def initialize (@width : Int32)
    end

    @[AlwaysInline]
    def unspecified?
        @width == UNSPECIFIED
    end

    @[AlwaysInline]
    def pointer?
        @width == POINTER
    end

    @[AlwaysInline]
    def integer?
        @width > 0
    end

    @[AlwaysInline]
    def mask : Int64
        BitWidth.all_ones(@width)
    end

    @[AlwaysInline]
    def sign_bit : Int64
        1_i64 << (@width - 1)
    end

    @[AlwaysInline]
    def truncate (value : Int64) : Int64
        value & mask
    end

    def & (other : BitWidth)
        return other if unspecified?
        return self if other.unspecified? || @width == other.@width
        raise BitWidthsIncompatible.new
    end

    def <=> (other : BitWidth)
        @width <=> other.@width
    end

    def sign_extend_to (value : Int64, to : BitWidth) : Int64
        hi = value & sign_bit
        ones = BitWidth.all_ones(to.@width - @width + 1)

        # if 'hi == 0', this produces 'value'; otherwise, 'hi' is '1 << (@width - 1)', and
        # multiplication by 'hi' means left shift by '@width - 1'.

        value | (hi * ones)
    end
end

end
