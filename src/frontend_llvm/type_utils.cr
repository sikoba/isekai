require "../common/dfg"
require "../common/bitwidth"
require "./pointers"
require "llvm-crystal/lib_llvm_c"

module Isekai::LLVMFrontend::TypeUtils

# Assuming 'ty' is an integer type, returns its bit width as a 'BitWidth' object.
def self.get_int_ty_bitwidth_unchecked (ty)
    return BitWidth.new(LibLLVM_C.get_int_type_width(ty).to_i32)
end

# If 'ty' is an integer type, returns its bit width as a 'BitWidth' object; raises otherwise.
def self.get_int_ty_bitwidth (ty)
    raise "Not an integer type" unless LibLLVM_C.get_type_kind(ty).integer_type_kind?
    return get_int_ty_bitwidth_unchecked(ty)
end

enum ScalarTypeKind
    Integer
    Pointer
end

def self.make_expr_of_ty (
        ty : LibLLVM_C::TypeRef,
        &block : ScalarTypeKind, LibLLVM_C::TypeRef -> DFGExpr) : DFGExpr

    kind = LibLLVM_C.get_type_kind(ty)
    case kind

    when .integer_type_kind?
        return block.call ScalarTypeKind::Integer, ty

    when .pointer_type_kind?
        return block.call ScalarTypeKind::Pointer, ty

    when .array_type_kind?
        nelems = LibLLVM_C.get_array_length(ty)
        elem_ty = LibLLVM_C.get_element_type(ty)
        elems = Array(DFGExpr).new(nelems) do
            make_expr_of_ty(elem_ty, &block)
        end
        return Structure.new(elems: elems, elem_ty: elem_ty)

    when .struct_type_kind?
        nelems = LibLLVM_C.count_struct_element_types(ty)
        elems = Array(DFGExpr).new(nelems) do |i|
            elem_ty = LibLLVM_C.struct_get_type_at_index(ty, i)
            make_expr_of_ty(elem_ty, &block)
        end
        return Structure.new(elems: elems, elem_ty: LibLLVM_C.void_type())

    else
        raise "Unsupported type kind: #{kind}"
    end
end

def self.make_undef_expr_of_ty (ty)
    return make_expr_of_ty(ty) do |kind, scalar_ty|
        case kind
        when ScalarTypeKind::Integer
            Constant.new(0, bitwidth: get_int_ty_bitwidth_unchecked(scalar_ty))
        when ScalarTypeKind::Pointer
            target_ty = LibLLVM_C.get_element_type(scalar_ty)
            UndefPointer.new(target_ty: target_ty)
        else
            raise "Unexpected ScalarTypeKind value"
        end
    end
end

end
