module Isekai

class BitWidthsIncompatible < Exception
end

# Assumes either (0 < width <= 64), or (width == UNDEFINED).
struct BitWidth
    include Comparable(BitWidth)

    private UNDEFINED = -1

    @[AlwaysInline]
    def self.all_ones (n)
        n == 64 ? UInt64::MAX : ((1_u64 << n) - 1)
    end

    @[AlwaysInline]
    def initialize (@width : Int32)
    end

    @[AlwaysInline]
    def self.new_for_undefined
        self.new(UNDEFINED)
    end

    @[AlwaysInline]
    def undefined?
        @width == UNDEFINED
    end

    @[AlwaysInline]
    def mask : UInt64
        BitWidth.all_ones(@width)
    end

    @[AlwaysInline]
    def sign_bit : UInt64
        1_u64 << (@width - 1)
    end

    @[AlwaysInline]
    def truncate (value : UInt64) : UInt64
        value & mask
    end

    def common! (other : BitWidth)
        return self if @width == other.@width
        raise BitWidthsIncompatible.new
    end

    def <=> (other : BitWidth)
        @width <=> other.@width
    end

    def sign_extend_to (value : UInt64, to : BitWidth) : UInt64
        hi = value & sign_bit
        ones = BitWidth.all_ones(to.@width - @width + 1)

        # if 'hi == 0', this produces 'value'; otherwise, 'hi' is '1 << (@width - 1)', and
        # multiplication by 'hi' means left shift by '@width - 1'.

        value | (hi * ones)
    end
end

end
