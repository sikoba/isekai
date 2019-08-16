require "../common/bitwidth"
require "intrinsics"

# https://gist.github.com/endSly/3226a22f91689e7eae338fd647d6c785
private lib IntIntrinsics
    {% for oper in %i(sadd ssub smul) %}
        {% for name, type in {i16: Int16, i32: Int32, i64: Int64} %}
            fun {{oper.id}}_with_overflow_{{name}} = "llvm.{{oper.id}}.with.overflow.{{name}}"(a : {{type}}, b : {{type}}) : { {{type}}, Bool }
        {% end %}
    {% end %}
    {% for oper in %i(uadd usub umul) %}
        {% for name, type in {i16: UInt16, i32: UInt32, i64: UInt64} %}
            fun {{oper.id}}_with_overflow_{{name}} = "llvm.{{oper.id}}.with.overflow.{{name}}"(a : {{type}}, b : {{type}}) : { {{type}}, Bool }
        {% end %}
    {% end %}
end

module Isekai::AltBackend::BitManip

@[AlwaysInline]
def self.nbits (c : UInt64) : Int32
    64 - Intrinsics.countleading64(c, zero_is_undef: false)
end

@[AlwaysInline]
def self.nbits (c : UInt128) : Int32
    128 - Intrinsics.countleading128(c, zero_is_undef: false)
end

@[AlwaysInline]
def self.add_in_bitwidth (a : UInt64, b : UInt64, bitwidth : BitWidth) : {UInt64, Bool}
    if bitwidth.@width == 64
        # In some reason, this does not link with 'build --release':
        #return IntIntrinsics.uadd_with_overflow_i64(a, b)
        result = a + b
        return {result, result < a}
    else
        exact_result = a + b
        result = bitwidth.truncate(exact_result)
        return {result, result != exact_result}
    end
end

@[AlwaysInline]
def self.mul_in_bitwidth (a : UInt64, b : UInt64, bitwidth : BitWidth) : {UInt64, Bool}
    if bitwidth.@width > 32
        result_64, overflow = IntIntrinsics.umul_with_overflow_i64(a, b)
        result = bitwidth.truncate(result_64)
        return {result, overflow || result != result_64}
    else
        exact_result = a * b
        result = bitwidth.truncate(exact_result)
        return {result, result != exact_result}
    end
end

@[AlwaysInline]
def self.min(a, b)
    a < b ? a : b
end

@[AlwaysInline]
def self.max(a, b)
    a > b ? a : b
end

end
