require "../common/dfg"
require "../common/bitwidth"
require "./pointers"
require "llvm-crystal/lib_llvm_c"

module Isekai::LLVMFrontend::TypeUtils

# Assuming 'ty' is an integer type, returns its bit width as a 'BitWidth' object.
def self.get_int_ty_bitwidth_unchecked (ty) : BitWidth
    width = LibLLVM_C.get_int_type_width(ty)
    if width > 64
        raise "Bit widths greater than 64 are not supported"
    end
    return BitWidth.new(width.to_i32)
end

# If 'ty' is an integer type, returns its bit width as a 'BitWidth' object; raises otherwise.
def self.get_int_ty_bitwidth (ty) : BitWidth
    raise "Not an integer type" unless LibLLVM_C.get_type_kind(ty).integer_type_kind?
    return get_int_ty_bitwidth_unchecked(ty)
end

def self.get_complex_type_signature (ty) : {LibLLVM_C::TypeRef, Int32} | Array(LibLLVM_C::TypeRef)
    kind = LibLLVM_C.get_type_kind(ty)
    case kind
    when .array_type_kind?
        elem_ty = LibLLVM_C.get_element_type(ty)
        nelems = LibLLVM_C.get_array_length(ty)
        return {elem_ty, nelems.to_i32}
    when .struct_type_kind?
        raise "Cannot get signature of an opaque struct" if LibLLVM_C.is_opaque_struct(ty) != 0
        nelems = LibLLVM_C.count_struct_element_types(ty)
        return Array(LibLLVM_C::TypeRef).build(nelems) do |buffer|
            LibLLVM_C.get_struct_element_types(ty, buffer)
            nelems
        end
    else
        raise "Unsupported type kind: #{kind}"
    end
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
        elems = Array.new(nelems) do
            make_expr_of_ty(elem_ty, &block)
        end
        return Structure.new(elems: elems, ty: ty)

    when .struct_type_kind?
        raise "Cannot make an opaque struct" if LibLLVM_C.is_opaque_struct(ty) != 0
        nelems = LibLLVM_C.count_struct_element_types(ty)
        elems = Array.new(nelems) do |i|
            elem_ty = LibLLVM_C.struct_get_type_at_index(ty, i)
            make_expr_of_ty(elem_ty, &block)
        end
        return Structure.new(elems: elems, ty: ty)

    else
        raise "Unsupported type kind: #{kind}"
    end
end

def self.make_undef_expr_of_ty (ty)
    return make_expr_of_ty(ty) do |kind, scalar_ty|
        case kind
        when .integer?
            Constant.new(0, bitwidth: get_int_ty_bitwidth_unchecked(scalar_ty))
        when .pointer?
            target_ty = LibLLVM_C.get_element_type(scalar_ty)
            UndefPointer.new(target_ty: target_ty)
        else
            raise "unreachable"
        end
    end
end

end
