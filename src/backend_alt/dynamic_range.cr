require "./bit_manip"

module Isekai::AltBackend

private struct DynamicRange
    include Comparable(DynamicRange)

    private UNDEFINED = -1

    @[AlwaysInline]
    def initialize (@width : Int32)
    end

    @[AlwaysInline]
    def self.new_for_const (value)
        return self.new(width: BitManip.nbits(value))
    end

    @[AlwaysInline]
    def self.new_for_undefined
        return self.new(width: UNDEFINED)
    end

    @[AlwaysInline]
    def self.new_for_bitwidth (bitwidth : BitWidth)
        return self.new(width: bitwidth.@width)
    end

    @[AlwaysInline]
    def self.new_for_bool
        return self.new(width: 1)
    end

    @[AlwaysInline]
    def undefined?
        @width == UNDEFINED
    end

    def + (other : DynamicRange)
        return DynamicRange.new_for_undefined if undefined? || other.undefined?
        # TODO (consider 0)
        return DynamicRange.new(width: BitManip.max(@width, other.@width) + 1)
    end

    def + (c : UInt128)
        return self if undefined?
        # TODO
        return self + DynamicRange.new_for_const c
    end

    def + (c : UInt64)
        return self if undefined?
        # TODO
        return self + DynamicRange.new_for_const c
    end

    def * (other : DynamicRange)
        return DynamicRange.new_for_undefined if undefined? || other.undefined?
        # TODO (consider 0 and 1)
        return DynamicRange.new(width: @width + other.@width)
    end

    def * (c : UInt128)
        return self if undefined?
        # TODO
        return self * DynamicRange.new_for_const c
    end

    def * (c : UInt64)
        return self if undefined?
        # TODO
        return self * DynamicRange.new_for_const c
    end

    def <=> (other : DynamicRange)
        return nil if undefined? || other.undefined?
        @width <=> other.@width
    end

    @[AlwaysInline]
    def fits_into_1bit?
        0 <= @width <= 1
    end

    @[AlwaysInline]
    def max_nbits : Int32?
        @width unless undefined?
    end
end

end
