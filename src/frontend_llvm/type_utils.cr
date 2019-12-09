require "../common/dfg"
require "../common/bitwidth"
require "./pointers"
require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend::TypeUtils

alias FuzzyType = LibLLVM::Type | ::Symbol

def self.fuzzy_match (actual : LibLLVM::Type, fuzzy : FuzzyType) : Bool
    case fuzzy
    when LibLLVM::Type
        actual == fuzzy
    when :pointer
        actual.pointer?
    when :integral
        actual.integer?
    else
        raise "Unknown fuzzy type: #{fuzzy}"
    end
end

# Assuming 'type' is an integer type, returns its bit width as a 'BitWidth' object.
def self.get_type_bitwidth_unchecked (type) : BitWidth
    width = type.integer_width
    if width > 64
        raise "Bit widths greater than 64 are not supported"
    end
    return BitWidth.new(width.to_i32)
end

# If 'type' is an integer type, returns its bit width as a 'BitWidth' object; raises otherwise.
def self.get_type_bitwidth (type) : BitWidth
    raise "Not an integer type" unless type.integer?
    return get_type_bitwidth_unchecked(type)
end

# Makes an expression of type 'type', creating 'Structure' objects for struct and array types, and
# invoking 'block' to make an expression of scalar type (integer or pointer).
def self.make_expr_of_type (type, &block : LibLLVM::Type -> DFGExpr) : DFGExpr
    case type.kind
    when .integer_type_kind?, .pointer_type_kind?
        return block.call type

    when .array_type_kind?
        length = type.array_length
        elem_type = type.element_type
        elems = Array.new(length) { make_expr_of_type(elem_type, &block) }
        return Structure.new(elems: elems, type: type)

    when .struct_type_kind?
        elems = type.struct_elems.map { |elem_type| make_expr_of_type(elem_type, &block) }
        return Structure.new(elems: elems, type: type)

    else
        raise "Unsupported type kind: #{type.kind}"
    end
end

# Makes an "undefined" expression of type 'type': initializes all integer values to zero, and
# pointer values to 'UndefPointer' objects.
def self.make_undef_expr_of_type (type) : DFGExpr
    return make_expr_of_type(type) do |scalar_type|
        case scalar_type.kind
        when .integer_type_kind?
            Constant.new(0, bitwidth: get_type_bitwidth_unchecked(scalar_type))
        when .pointer_type_kind?
            UndefPointer.new(target_type: scalar_type.element_type)
        else
            raise "unreachable"
        end
    end
end

def self.byte_seq_to_expr (bytes : Array(UInt8)) : DFGExpr
    arr = Structure.new(
        elems: bytes.map do |byte|
            Constant.new(byte.to_i64!, bitwidth: BitWidth.new(8)).as DFGExpr
        end,
        type: LibLLVM::Type.new_array(
            elem_type: LibLLVM::Type.new_integral(nbits: 8),
            length: bytes.size
        )
    )
    StaticFieldPointer.new(base: arr, field: 0)
end

def self.expr_to_byte_seq (expr : DFGExpr) : Array(UInt8)?
    return nil unless expr.is_a? StaticFieldPointer
    base = expr.@base
    return nil unless base.@type.array?
    return nil unless base.@type.element_type == LibLLVM::Type.new_integral(nbits: 8)
    base.@elems.map do |byte_expr|
        return nil unless byte_expr.is_a? Constant
        byte_expr.@value.to_u8!
    end
end

end
