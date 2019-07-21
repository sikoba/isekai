require "./dfg"
require "./frontend/symbol_table_key"
require "./frontend/storage"
require "llvm-crystal/lib_llvm"
require "llvm-crystal/lib_llvm_c"

module Isekai

    class FieldTransformer
        def initialize (@input_storage : Storage, @inputs : Array(DFGExpr))
            super()
        end

        def get_ith_field (i)
            @inputs[i].as(Input)
        end

        def transform (expr)
            case expr
            when .is_a?(Field)
                field = expr.as(Field)
                if field.@key.@storage == @input_storage
                    get_ith_field(field.@key.@idx)
                else
                    expr
                end

            when .is_a?(Add)
                add = expr.as(Add)
                left = transform(add.@left)
                right = transform(add.@right)
                Add.new(left, right)

            else
                expr
            end
        end
    end

    class BitcodeParser

        @inputs = Array(DFGExpr).new
        @nizk_inputs : Array(DFGExpr)?
        @outputs = Array(Tuple(StorageKey, DFGExpr)).new

        @arguments = {} of LibLLVM_C::ValueRef => DFGExpr
        @locals = {} of LibLLVM_C::ValueRef => DFGExpr
        @allocas = [] of DFGExpr

        @inout_storages = [] of Storage

        def output_storage!
            @inout_storages[-1]
        end

        def input_storage!
            @inout_storages[0]
        end

        def nizk_input_storage!
            return @inout_storages[1] if @inout_storages.size == 3
        end

        def initialize (@input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
        end

        def inspect_param! (name, ptr, ty)
            raise "Function parameter is not a pointer" unless
                LibLLVM_C.get_type_kind(ty).pointer_type_kind?

            s_ty = LibLLVM_C.get_element_type(ty)

            raise "Function parameter is a pointer to non-struct" unless
                LibLLVM_C.get_type_kind(s_ty).struct_type_kind?

            raise "Function parameter is a pointer to an incomplete struct" unless
                LibLLVM_C.is_opaque_struct(s_ty) == 0

            nelems = LibLLVM_C.count_struct_element_types(s_ty)

            st = Storage.new(name, nelems.to_i32)
            @inout_storages << st
            @arguments[ptr] = GetPointerOp.new(Structure.new(st))
        end

        def load_expr_preliminary (src)
            kind = LibLLVM_C.get_value_kind(src)
            case kind
            when .argument_value_kind?
                 @arguments[src]
            when .instruction_value_kind?
                # this is a reference to a local value created by 'src' instruction
                @locals[src]
            when .constant_int_value_kind?
                Constant.new(LibLLVM_C.const_int_get_s_ext_value(src).to_i32)
            else
                raise "NYI: unsupported value kind: #{kind}"
            end
        end

        def load_expr (src)
            expr = load_expr_preliminary(src)
            # TODO: collapse it properly
            if expr.is_a?(AllocaOp)
                idx = expr.as(AllocaOp).@idx
                expr = GetPointerOp.new(@allocas[idx])
            end
            expr
        end

        def store! (dst, expr)
            # TODO: collapse it properly

            dst_kind = LibLLVM_C.get_value_kind(dst)
            raise "NYI: unsupported dst kind: #{dst_kind}" unless dst_kind.instruction_value_kind?

            dst_expr = @locals[dst]
            case dst_expr
            when .is_a?(AllocaOp)
                @allocas[dst_expr.as(AllocaOp).@idx] = expr
            when .is_a?(GetPointerOp)
                target = dst_expr.as(GetPointerOp).@target
                raise "NYI: cannot store at pointer to #{target}" unless target.is_a?(Field)
                field = target.as(Field)
                raise "NYI" unless field.@key.@storage == output_storage!
                # TODO fix this atrocity
                @outputs << {
                    field.@key,
                    FieldTransformer.new(input_storage!, @inputs).transform(expr)
                }
            else
                raise "NYI: cannot store at #{dst_expr}"
            end
        end

        # TODO factor it out to a DereferenceOp < DFGExpr?
        def deref (expr)
            if expr.is_a?(GetPointerOp)
                return expr.as(GetPointerOp).@target
            end
            raise "NYI: cannot dereference #{expr}"
        end

        def get_element_ptr (base, offset, field)
            raise "NYI: GEP base is not a pointer" unless base.is_a?(GetPointerOp)
            raise "NYI: non-constant GEP offset" unless offset.is_a?(Constant)
            raise "NYI: non-constant GEP field" unless field.is_a?(Constant)

            raise "NYI: GEP with non-zero offset" unless offset.as(Constant).@value == 0

            target = base.as(GetPointerOp).@target
            raise "NYI: GEP target is not a struct" unless target.is_a?(Structure)

            key = StorageKey.new(
                target.as(Structure).@storage,
                field.as(Constant).@value)
            return GetPointerOp.new(Field.new(key))
        end

        def inspect_basic_block! (bb)
            bb.instructions do |ins|
                case LibLLVM_C.get_instruction_opcode(ins)

                when .alloca?
                    #ty = LibLLVM_C.get_allocated_type(ins)
                    @locals[ins] = AllocaOp.new(@allocas.size)
                    @allocas << Undefined.new()

                when .store?
                    src = LibLLVM_C.get_operand(ins, 0)
                    dst = LibLLVM_C.get_operand(ins, 1)
                    store!(dst, load_expr(src))

                when .load?
                    src = LibLLVM_C.get_operand(ins, 0)
                    @locals[ins] = deref(load_expr(src))

                when .get_element_ptr?
                    nops = LibLLVM_C.get_num_operands(ins)
                    raise "Not supported yet: #{nops}-arg GEP" unless nops == 3

                    base = LibLLVM_C.get_operand(ins, 0)
                    offset = LibLLVM_C.get_operand(ins, 1)
                    field = LibLLVM_C.get_operand(ins, 2)

                    @locals[ins] = get_element_ptr(
                        load_expr(base), load_expr(offset), load_expr(field))

                when .add?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Add.new(load_expr(left), load_expr(right))

                when .ret?
                    # We assume this is "ret void" as the function returns void.
                    break

                else
                    repr = LibLLVM.slurp_string(LibLLVM_C.print_value_to_string(ins))
                    raise "Unsupported instruction: #{repr}"
                end
            end
        end

        def gen_input_array (storage : Storage, x : T.class) forall T
            arr = Array(DFGExpr).new
            (0...storage.@size).each do |i|
                arr << T.new(StorageKey.new(storage, i))
            end
            arr
        end

        def inspect_root_func! (func)
            func_ty = LibLLVM_C.type_of(func)
            if LibLLVM_C.get_type_kind(func_ty).pointer_type_kind?
                func_ty = LibLLVM_C.get_element_type(func_ty)
            end

            raise "Function return type is not void" unless
                LibLLVM_C.get_type_kind(LibLLVM_C.get_return_type(func_ty)).void_type_kind?

            func_nparams = LibLLVM_C.count_params(func)
            raise "Number of types != number of params" unless
                LibLLVM_C.count_param_types(func_ty) == func_nparams

            param_tys = Array(LibLLVM_C::TypeRef).build(func_nparams) do |buffer|
                LibLLVM_C.get_param_types(func_ty, buffer)
                func_nparams
            end

            params = Array(LibLLVM_C::ValueRef).build(func_nparams) do |buffer|
                LibLLVM_C.get_params(func, buffer)
                func_nparams
            end

            case func_nparams
            when 2
                inspect_param!("Input",  params[0], param_tys[0])
                inspect_param!("Output", params[1], param_tys[1])
            when 3
                inspect_param!("Input",     params[0], param_tys[0])
                inspect_param!("NizkInput", params[1], param_tys[1])
                inspect_param!("Output",    params[2], param_tys[2])
            else
                raise "Function takes #{func_nparams} parameter(s), expected 2 or 3"
            end

            @inputs = gen_input_array(input_storage!, Input).as(Array(DFGExpr))

            nizk_input_storage = nizk_input_storage!
            if nizk_input_storage
                @nizk_inputs = gen_input_array(nizk_input_storage, NIZKInput)
            end

            inspect_basic_block!(func.entry_basic_block)
        end

        def parse ()
            module_ = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(@input_file))
            module_.functions do |func|
                next if func.declaration?
                raise "Unexpected function defined: #{func.name}" unless
                    func.name == "outsource"
                inspect_root_func!(func)
                return {@inputs, @nizk_inputs, @outputs}
            end

            raise "No 'outsource' function found"
        end
    end
end
