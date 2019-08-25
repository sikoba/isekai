require "../common/dfg"
require "../common/bitwidth"
require "./pointers"
require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend::TypeUtils

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

def self.make_undef_expr_of_type (type)
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

end
