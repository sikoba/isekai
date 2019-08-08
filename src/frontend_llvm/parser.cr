require "../common/dfg"
require "../common/bitwidth"
require "../common/symbol_table_key"
require "../common/storage"
require "./preproc"
require "llvm-crystal/lib_llvm"
require "llvm-crystal/lib_llvm_c"

# Assuming 'ty' is an integer type, returns its bit width as a 'BitWidth' object.
private def get_int_ty_bitwidth_unchecked (ty)
    return Isekai::BitWidth.new(LibLLVM_C.get_int_type_width(ty).to_i32)
end

# If 'ty' is an integer type, returns its bit width as a 'BitWidth' object; raises otherwise.
private def get_int_ty_bitwidth (ty)
    raise "Not an integer type" unless
        LibLLVM_C.get_type_kind(ty).integer_type_kind?
    return get_int_ty_bitwidth_unchecked(ty)
end

# Constructs an expression aprropriate for an undefined value of the given type 'ty'.
private def make_undef_for_ty (ty) : Isekai::DFGExpr
    kind = LibLLVM_C.get_type_kind(ty)
    case kind
    when .integer_type_kind?
        return Isekai::Constant.new(0, bitwidth: get_int_ty_bitwidth_unchecked(ty))
    when .pointer_type_kind?
        return Isekai::DynamicPointer.new
    else
        raise "Unsupported type kind: #{kind}"
    end
end

# Assuming 'value' is a constant integer value, returns its value as a 'Constant' with the
# appropriate bitwidth.
private def make_constant_unchecked (value) : Isekai::Constant
    ty = LibLLVM_C.type_of(value)
    return Isekai::Constant.new(
        LibLLVM_C.const_int_get_z_ext_value(value).to_i64,
        bitwidth: get_int_ty_bitwidth_unchecked(ty))
end

# Assuming 'ins' is a switch instruction, returns the value of the case with number 'i'.
# 'i' is 1-based if we only consider 'case' statements without 'default', and 0-based if we consider
# all the successors, of which the zeroth is the default (thus 'i == 0' is not allowed).
private def get_case_value_unchecked(ins, i) : Isekai::Constant
    value = LibLLVM_C.get_operand(ins, i * 2)
    raise "Case value is not an integer constant" unless
        LibLLVM_C.get_value_kind(value).constant_int_value_kind?
    return make_constant_unchecked(value)
end

private BW_32 = Isekai::BitWidth.new(32)

module Isekai::LLVMFrontend

class Parser

    private struct UnrollCtl
        @counter : Int32
        @n_dynamic_iters : Int32

        def initialize (@junction : LibLLVM::BasicBlock, @limit : Int32, is_dynamic : Bool)
            @counter = 1
            @n_dynamic_iters = is_dynamic ? 1 : 0
        end

        def n_dynamic_iters
            return @n_dynamic_iters
        end

        def done?
            return @counter == @limit
        end

        def iteration (is_dynamic : Bool)
            @counter += 1
            @n_dynamic_iters += is_dynamic ? 1 : 0
            return self
        end
    end

    private struct World
        @hash = {} of LibLLVM_C::ValueRef => DFGExpr

        def [] (k : LibLLVM_C::ValueRef)
            @hash[k]
        end

        def [] (k : LibLLVM::Instruction, v)
            @hash[k.to_unsafe]
        end

        def []= (k : LibLLVM_C::ValueRef, v)
            @hash[k] = v
        end

        def []= (k : LibLLVM::Instruction, v)
            @hash[k.to_unsafe] = v
        end

        def fetch (k : LibLLVM_C::ValueRef, &block : -> DFGExpr)
            @hash.fetch(k, &block)
        end

        def fetch (k : LibLLVM::Instruction, &block : -> DFGExpr)
            @hash.fetch(k.to_unsafe, &block)
        end
    end

    private class BadOutsourceParam < Exception
    end

    private class BadOutsourceParamPosition < Exception
    end

    @inputs : Array(DFGExpr)?
    @nizk_inputs : Array(DFGExpr)?
    @outputs = [] of Tuple(StorageKey, DFGExpr)

    @arguments = World.new
    @locals = World.new
    @allocas = [] of DFGExpr

    @input_storage : Storage?
    @nizk_input_storage : Storage?
    @output_storage : Storage?

    # junction => {sink, is_loop}
    @preproc_data = {} of LibLLVM::BasicBlock => Tuple(LibLLVM::BasicBlock, Bool)

    @chain = [] of Tuple(DFGExpr, Bool)
    @unroll_ctls = [] of UnrollCtl
    @unroll_hint_func : LibLLVM_C::ValueRef? = nil

    @ir_module : LibLLVM::IrModule

    def initialize (input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
        @ir_module = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(input_file))
    end

    private def with_chain_add_condition (
            old_expr : DFGExpr,
            new_expr : DFGExpr,
            chain_index : Int32 = 0) : DFGExpr

        if old_expr.is_a? Conditional && chain_index != @chain.size
            cond, flag = @chain[chain_index][0], @chain[chain_index][1]
            if cond.same?(old_expr.@cond)
                valtrue, valfalse = old_expr.@valtrue, old_expr.@valfalse
                if flag
                    valtrue = with_chain_add_condition(valtrue, new_expr, chain_index + 1)
                else
                    valfalse = with_chain_add_condition(valfalse, new_expr, chain_index + 1)
                end
                return Conditional.new(cond, valtrue, valfalse)
            end
        end

        result = new_expr
        (chain_index...@chain.size).reverse_each do |i|
            cond, flag = @chain[i][0], @chain[i][1]
            if flag
                result = Conditional.new(cond, result, old_expr)
            else
                result = Conditional.new(cond, old_expr, result)
            end
        end
        return result
    end

    private def with_chain_reduce (expr : DFGExpr) : DFGExpr
        @chain.each do |(cond, flag)|
            break unless expr.is_a? Conditional
            break unless cond.same?(expr.@cond)
            expr = flag ? expr.@valtrue : expr.@valfalse
        end
        return expr
    end

    private def dereference (expr : DFGExpr) : DFGExpr
        case expr
        when GetPointer
            expr.@target
        when Alloca
            @allocas[expr.@idx]
        else
            # not supported; might as well raise here
            Deref.new(expr, bitwidth: BitWidth.new(BitWidth::UNSPECIFIED))
        end
    end

    private def make_input_array (storage : Storage?)
        return nil unless storage
        return Array(DFGExpr).new(storage.@size) do |i|
            Field.new(StorageKey.new(storage, i), bitwidth: BW_32) # FIXME
        end
    end

    private def inspect_outsource_param (value, accept)
        ty = LibLLVM_C.type_of(value)
        raise BadOutsourceParam.new("is not a pointer") unless
            LibLLVM_C.get_type_kind(ty).pointer_type_kind?

        s_ty = LibLLVM_C.get_element_type(ty)

        raise BadOutsourceParam.new("is a pointer to non-struct") unless
            LibLLVM_C.get_type_kind(s_ty).struct_type_kind?

        raise BadOutsourceParam.new("is a pointer to an incomplete struct") unless
            LibLLVM_C.is_opaque_struct(s_ty) == 0

        s_name = String.new(LibLLVM_C.get_struct_name(s_ty))
        nelems = LibLLVM_C.count_struct_element_types(s_ty).to_i32

        case s_name
        when .ends_with? ".Input"
            raise BadOutsourceParamPosition.new(s_name) unless accept.includes? :input
            st = Storage.new("Input", nelems)
            @input_storage = st

        when .ends_with? ".NzikInput" # sic
            raise BadOutsourceParamPosition.new(s_name) unless accept.includes? :nizk_input
            st = Storage.new("NzikInput", nelems)
            @nizk_input_storage = st

        when .ends_with? ".Output"
            raise BadOutsourceParamPosition.new(s_name) unless accept.includes? :output
            st = Storage.new("Output", nelems)
            @output_storage = st

        else
            raise BadOutsourceParam.new("unexpected struct name: #{s_name}")
        end

        @arguments[value] = GetPointer.new(Structure.new(st, bitwidth: BW_32)) # FIXME
    end

    private def load_expr (src) : DFGExpr
        kind = LibLLVM_C.get_value_kind(src)
        case kind
        when .argument_value_kind?
            expr = @arguments[src]
        when .instruction_value_kind?
            # this is a reference to a local value created by 'src' instruction
            expr = @locals[src]
        when .constant_int_value_kind?
            expr = make_constant_unchecked(src)
        else
            raise "NYI: unsupported value kind: #{kind}"
        end

        case expr
        when Field
            if expr.@key.@storage == @output_storage
                expr = @outputs[expr.@key.@idx][1]
            end
        end

        expr = with_chain_reduce(expr)

        return expr
    end

    private def store (dst : DFGExpr, src : DFGExpr)
        case dst

        when Alloca
            old_expr = @allocas[dst.@idx]
            @allocas[dst.@idx] = with_chain_add_condition(old_expr, src)

        when GetPointer
            target = dst.@target
            raise "NYI: cannot store at pointer to #{target}" unless target.is_a?(Field)
            raise "NYI: store in non-output struct" unless target.@key.@storage == @output_storage
            old_expr = @outputs[target.@key.@idx][1]
            @outputs[target.@key.@idx] = {target.@key, with_chain_add_condition(old_expr, src)}

        else
            raise "NYI: cannot store at #{dst}"
        end
    end

    private def get_element_ptr (base : DFGExpr, offset : DFGExpr, field : DFGExpr) : DFGExpr
        raise "NYI: GEP base is not a pointer" unless base.is_a?(GetPointer)
        raise "NYI: non-constant GEP offset" unless offset.is_a?(Constant)
        raise "NYI: non-constant GEP field" unless field.is_a?(Constant)

        raise "NYI: GEP with non-zero offset" unless offset.@value == 0

        target = base.@target
        raise "NYI: GEP target is not a struct" unless target.is_a?(Structure)

        key = StorageKey.new(target.@storage, field.@value.to_i32)
        return GetPointer.new(Field.new(key, bitwidth: BW_32))
    end

    private def inspect_basic_block_until (
            bb : LibLLVM::BasicBlock,
            terminator : LibLLVM::BasicBlock?)

        while bb != terminator
            raise "terminator not found (end of function reached)" unless bb
            bb = inspect_basic_block(bb)
        end
    end

    @[AlwaysInline]
    private def get_phi_value (ins) : DFGExpr
        return @locals.fetch(ins) { make_undef_for_ty(LibLLVM_C.type_of(ins)) }
    end

    private def produce_phi_copies (from : LibLLVM::BasicBlock, to : LibLLVM::BasicBlock)
        to.instructions.each do |ins|
            break unless LibLLVM_C.get_instruction_opcode(ins).phi?
            ins.incoming.each do |(block, value)|
                next unless block == from
                old_expr = get_phi_value(ins)
                @locals[ins] = with_chain_add_condition(old_expr, load_expr(value))
            end
        end
    end

    @[AlwaysInline]
    private def set_binary (ins, klass)
        left = load_expr(LibLLVM_C.get_operand(ins, 0))
        right = load_expr(LibLLVM_C.get_operand(ins, 1))
        @locals[ins] = Isekai.dfg_make_binary(klass, left, right)
    end

    @[AlwaysInline]
    private def set_binary_swapped (ins, klass)
        left = load_expr(LibLLVM_C.get_operand(ins, 1))
        right = load_expr(LibLLVM_C.get_operand(ins, 0))
        @locals[ins] = Isekai.dfg_make_binary(klass, left, right)
    end

    @[AlwaysInline]
    private def set_bitwidth_cast (ins, klass)
        arg = load_expr(LibLLVM_C.get_operand(ins, 0))
        new_bitwidth = get_int_ty_bitwidth(LibLLVM_C.type_of(ins))
        @locals[ins] = Isekai.dfg_make_bitwidth_cast(klass, arg, new_bitwidth)
    end

    private def inspect_basic_block (bb) : LibLLVM::BasicBlock?
        bb.instructions.each do |ins|
            case LibLLVM_C.get_instruction_opcode(ins)

            when .alloca?
                ty = LibLLVM_C.get_allocated_type(ins)
                @locals[ins] = Alloca.new(@allocas.size)
                @allocas << make_undef_for_ty(ty)

            when .store?
                src = load_expr(LibLLVM_C.get_operand(ins, 0))
                dst = load_expr(LibLLVM_C.get_operand(ins, 1))
                store(dst: dst, src: src)

            when .load?
                src = LibLLVM_C.get_operand(ins, 0)
                @locals[ins] = dereference(load_expr(src))

            when .phi?
                @locals[ins] = get_phi_value(ins)

            when .get_element_ptr?
                nops = LibLLVM_C.get_num_operands(ins)
                raise "Not supported yet: #{nops}-arg GEP" unless nops == 3

                base = load_expr(LibLLVM_C.get_operand(ins, 0))
                offset = load_expr(LibLLVM_C.get_operand(ins, 1))
                field = load_expr(LibLLVM_C.get_operand(ins, 2))
                @locals[ins] = get_element_ptr(base: base, offset: offset, field: field)

            when .add?   then set_binary(ins, Add)
            when .sub?   then set_binary(ins, Subtract)
            when .mul?   then set_binary(ins, Multiply)
            when .and?   then set_binary(ins, BitAnd)
            when .or?    then set_binary(ins, BitOr)
            when .xor?   then set_binary(ins, Xor)
            when .shl?   then set_binary(ins, LeftShift)

            # TODO: is 'RightShift' signed or unsigned?
            when .a_shr? then set_binary(ins, RightShift)
            when .l_shr? then set_binary(ins, RightShift)

            # TODO: is 'Divide' signed or unsigned?
            when .s_div? then set_binary(ins, Divide)
            when .u_div? then set_binary(ins, Divide)

            # TODO: is 'Modulo' signed or unsigned?
            when .s_rem? then set_binary(ins, Modulo)
            when .u_rem? then set_binary(ins, Modulo)

            when .i_cmp?
                case LibLLVM_C.get_i_cmp_predicate(ins)

                when .int_eq? then set_binary(ins, CmpEQ)
                when .int_ne? then set_binary(ins, CmpNEQ)

                # TODO: is 'CmpLT' signed or unsigned?
                when .int_slt? then set_binary(ins, CmpLT)
                when .int_ult? then set_binary(ins, CmpLT)

                # TODO: is 'CmpLEQ' signed or unsigned?
                when .int_ule? then set_binary(ins, CmpLEQ)
                when .int_sle? then set_binary(ins, CmpLEQ)

                # TODO: is 'CmpLT' signed or unsigned?
                when .int_ugt? then set_binary_swapped(ins, CmpLT)
                when .int_sgt? then set_binary_swapped(ins, CmpLT)

                # TODO: is 'CmpLEQ' signed or unsigned?
                when .int_uge? then set_binary_swapped(ins, CmpLEQ)
                when .int_sge? then set_binary_swapped(ins, CmpLEQ)

                else raise "NYI: ICmp predicate (signed comparison?)"
                end

            when .z_ext? then set_bitwidth_cast(ins, ZeroExtend)
            when .s_ext? then set_bitwidth_cast(ins, SignExtend)
            when .trunc? then set_bitwidth_cast(ins, Truncate)

            when .select?
                pred = load_expr(LibLLVM_C.get_operand(ins, 0))
                val_true = load_expr(LibLLVM_C.get_operand(ins, 1))
                val_false = load_expr(LibLLVM_C.get_operand(ins, 2))
                @locals[ins] = Isekai.dfg_make_conditional(pred, val_true, val_false)

            when .call?
                raise "Unsupported function call (not _unroll_hint())" unless
                    LibLLVM_C.get_called_value(ins) == @unroll_hint_func
                raise "_unroll_hint() must be called with 1 argument" unless
                    LibLLVM_C.get_num_arg_operands(ins) == 1

                arg = load_expr(LibLLVM_C.get_operand(ins, 0))

                raise "_unroll_hint() argument is not constant" unless arg.is_a? Constant
                value = arg.@value.to_i32
                raise "_unroll_hint() argument is out of bounds" if value < 0
                @loop_sanity_limit = value

            when .br?
                successors = ins.successors.to_a
                successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                if ins.conditional?
                    cond = load_expr(LibLLVM_C.get_condition(ins))
                    if_true, if_false = successors

                    if cond.is_a? Constant
                        static_branch = (cond.@value != 0) ? if_true : if_false
                    end

                    sink, is_loop = @preproc_data[bb]
                    if is_loop
                        to_loop = (sink == if_true) ? if_false : if_true

                        if !@unroll_ctls.empty? && @unroll_ctls[-1].@junction == bb
                            ctl = @unroll_ctls[-1]
                            if ctl.done? || static_branch == sink
                                # Stop generating iterations
                                raise "Statically infinite loop" if static_branch == to_loop
                                @chain.pop(ctl.n_dynamic_iters)
                                @unroll_ctls.pop
                                return sink
                            else
                                # Generate another iteration
                                @unroll_ctls[-1] = ctl.iteration(is_dynamic: !static_branch)
                            end
                        else
                            if @loop_sanity_limit <= 0 || static_branch == sink
                                raise "Statically infinite loop" if static_branch == to_loop
                                return sink
                            end
                            # New loop, start the unroll
                            @unroll_ctls << UnrollCtl.new(
                                junction: bb,
                                limit: @loop_sanity_limit,
                                is_dynamic: !static_branch)
                        end

                        @chain << {cond, to_loop == if_true} unless static_branch
                        return to_loop
                    else
                        return static_branch if static_branch

                        @chain << {cond, true}
                        inspect_basic_block_until(if_true, terminator: sink)
                        @chain.pop

                        @chain << {cond, false}
                        inspect_basic_block_until(if_false, terminator: sink)
                        @chain.pop

                        return sink
                    end
                else
                    return successors[0]
                end

            when .switch?
                successors = ins.successors.to_a
                successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                arg = load_expr(LibLLVM_C.get_operand(ins, 0))
                if arg.is_a? Constant
                    (1...successors.size).each do |i|
                        if get_case_value_unchecked(ins, i).@value == arg.@value
                            return successors[i]
                        end
                    end
                    return successors[0]
                end

                sink, _ = @preproc_data[bb]
                # inspect each case
                (1...successors.size).each do |i|
                    cond = Isekai.dfg_make_binary(CmpEQ, arg, get_case_value_unchecked(ins, i))

                    @chain << {cond, true}
                    inspect_basic_block_until(successors[i], terminator: sink)
                    @chain.pop
                    @chain << {cond, false}
                end
                # inspect the default case
                inspect_basic_block_until(successors[0], terminator: sink)
                @chain.pop(successors.size - 1)

                return sink

            when .ret?
                # We assume this is "ret void" as the function returns void.
                return nil

            else
                raise "Unsupported instruction: #{ins}"
            end
        end
    end

    private def inspect_outsource_func (func)
        ret_ty, params, is_var_arg = func.signature

        raise "outsource() return type is not void" unless
            LibLLVM_C.get_type_kind(ret_ty).void_type_kind?

        raise "outsource() is a var arg function" if is_var_arg

        case params.size
        when 2
            inspect_outsource_param(params[0], accept: {:input, :nizk_input})
            inspect_outsource_param(params[1], accept: {:output})
        when 3
            inspect_outsource_param(params[0], accept: {:input})
            inspect_outsource_param(params[1], accept: {:nizk_input})
            inspect_outsource_param(params[2], accept: {:output})
        else
            raise "outsource() takes #{params.size} parameter(s), expected 2 or 3"
        end

        @inputs      = make_input_array @input_storage
        @nizk_inputs = make_input_array @nizk_input_storage

        output_storage = @output_storage.as(Storage)
        @outputs = Array(Tuple(StorageKey, DFGExpr)).new(output_storage.@size) do |i|
            {
                StorageKey.new(output_storage, i),
                make_undef_for_ty(LibLLVM_C.int32_type()) # FIXME
            }
        end

        @preproc_data = Preprocessor.new(func.entry_basic_block).data
        inspect_basic_block_until(func.entry_basic_block, terminator: nil)
    end

    private def inspect_unroll_hint_func (func)
        ret_ty, params, is_var_arg = func.signature

        raise "_unroll_hint() return type is not void" unless
            LibLLVM_C.get_type_kind(ret_ty).void_type_kind?

        raise "_unroll_hint() is a var arg function" if is_var_arg

        raise "_unroll_hint() takes #{params.size} parameters, expected 1" unless
            params.size == 1

        ty = LibLLVM_C.type_of(params[0])
        raise "_unroll_hint() parameter has non-integer type" unless
            LibLLVM_C.get_type_kind(ty).integer_type_kind?

        @unroll_hint_func = func.to_unsafe
    end

    def parse ()
        @ir_module.functions.each do |func|
            if func.declaration? && func.name == "_unroll_hint"
                inspect_unroll_hint_func(func)
            end
        end
        @ir_module.functions.each do |func|
            next if func.declaration?
            raise "Unexpected function defined: #{func.name}" unless func.name == "outsource"
            inspect_outsource_func(func)
            return {@inputs || [] of DFGExpr, @nizk_inputs, @outputs}
        end

        raise "No 'outsource' function found"
    end
end

end
