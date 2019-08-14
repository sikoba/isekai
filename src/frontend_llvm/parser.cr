require "../common/dfg"
require "../common/bitwidth"
require "../common/symbol_table_key"
require "../common/storage"
require "./preproc"
require "./assumption"
require "./structure"
require "./pointers"
require "./type_utils"
require "llvm-crystal/lib_llvm"
require "llvm-crystal/lib_llvm_c"

include Isekai::LLVMFrontend

# Assuming 'value' is a constant integer value, returns its value as a 'Constant' with the
# appropriate bitwidth.
private def make_constant_unchecked (value) : Constant
    ty = LibLLVM_C.type_of(value)
    return Constant.new(
        LibLLVM_C.const_int_get_z_ext_value(value).to_i64,
        bitwidth: TypeUtils.get_int_ty_bitwidth_unchecked(ty))
end

# Assuming 'ins' is a switch instruction, returns the value of the case with number 'i'.
# 'i' is 1-based if we only consider 'case' statements without 'default', and 0-based if we consider
# all the successors, of which the zeroth is the default (thus 'i == 0' is not allowed).
private def get_case_value_unchecked(ins, i) : Constant
    value = LibLLVM_C.get_operand(ins, i * 2)
    raise "Case value is not an integer constant" unless
        LibLLVM_C.get_value_kind(value).constant_int_value_kind?
    return make_constant_unchecked(value)
end

private def make_input_expr_of_ty (ty, which : InputBase::Kind) : DFGExpr
    offset = 0
    return TypeUtils.make_expr_of_ty(ty) do |kind, scalar_ty|
        case kind
        when TypeUtils::ScalarTypeKind::Integer
            result = InputBase.new(
                which: which,
                idx: offset,
                bitwidth: TypeUtils.get_int_ty_bitwidth_unchecked(scalar_ty))
            offset += 1
            result
        when TypeUtils::ScalarTypeKind::Pointer
            raise "Input structure contains a pointer"
        else
            raise "unreachable"
        end
    end
end

private def make_input_array (s : Structure?)
    return s ? s.flattened.map &.@bitwidth : [] of BitWidth
end

private def make_output_array (s : Structure?)
    return s ? s.flattened : [] of DFGExpr
end

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
            @n_dynamic_iters
        end

        def done?
            @counter == @limit
        end

        def iteration (is_dynamic : Bool)
            @counter += 1
            @n_dynamic_iters += is_dynamic ? 1 : 0
            return self
        end
    end

    private struct World
        @hash = {} of LibLLVM_C::ValueRef => DFGExpr

        @[AlwaysInline]
        def [] (k : LibLLVM_C::ValueRef)
            @hash[k]
        end

        @[AlwaysInline]
        def [] (k : LibLLVM::Instruction)
            @hash[k.to_unsafe]
        end

        @[AlwaysInline]
        def []= (k : LibLLVM_C::ValueRef, v)
            @hash[k] = v
        end

        @[AlwaysInline]
        def []= (k : LibLLVM::Instruction, v)
            @hash[k.to_unsafe] = v
        end
    end

    enum OutsourceParam
        Input
        NizkInput
        Output
    end

    @arguments = World.new
    @locals = World.new
    @cached_undef_exprs = World.new

    # junction => {sink, is_loop}
    @preproc_data = {} of LibLLVM::BasicBlock => Tuple(LibLLVM::BasicBlock, Bool)

    @assumption = Assumption.new
    @unroll_ctls = [] of UnrollCtl

    @unroll_hint_func : LibLLVM_C::ValueRef? = nil

    @input_struct : Structure? = nil
    @nizk_input_struct : Structure? = nil
    @output_struct : Structure? = nil

    @ir_module : LibLLVM::IrModule

    def initialize (input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
        @ir_module = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(input_file))
    end

    private def make_undef_expr_of_ty_cached (ty, cache_token)
        begin
            return @cached_undef_exprs[cache_token]
        rescue KeyError
            return @cached_undef_exprs[cache_token] = TypeUtils.make_undef_expr_of_ty(ty)
        end
    end

    private def inspect_outsource_param (value, which_param : OutsourceParam) : Nil
        ty = LibLLVM_C.type_of(value)
        raise "outsource() parameter is not a pointer" unless
            LibLLVM_C.get_type_kind(ty).pointer_type_kind?

        s_ty = LibLLVM_C.get_element_type(ty)

        raise "outsource() parameter is a pointer to non-struct" unless
            LibLLVM_C.get_type_kind(s_ty).struct_type_kind?

        case which_param
        when OutsourceParam::Input
            expr = make_input_expr_of_ty(s_ty, InputBase::Kind::Input)
            raise "unreachable" unless expr.is_a? Structure
            @input_struct = expr

        when OutsourceParam::NizkInput
            expr = make_input_expr_of_ty(s_ty, InputBase::Kind::NizkInput)
            raise "unreachable" unless expr.is_a? Structure
            @nizk_input_struct = expr

        when OutsourceParam::Output
            expr = TypeUtils.make_undef_expr_of_ty(s_ty)
            raise "unreachable" unless expr.is_a? Structure
            @output_struct = expr

        else
            raise "unreachable"
        end

        @arguments[value] = StaticPointer.new(expr)
    end

    private def as_expr (value) : DFGExpr
        kind = LibLLVM_C.get_value_kind(value)
        case kind
        when .argument_value_kind?
            expr = @arguments[value]
        when .instruction_value_kind?
            # this is a reference to a local value created by 'value' instruction
            expr = @locals[value]
        when .constant_int_value_kind?
            expr = make_constant_unchecked(value)
        else
            raise "Unsupported value kind: #{kind}"
        end
        expr = @assumption.reduce(expr)
        return expr
    end

    private def store (at ptr : DFGExpr, value : DFGExpr) : Nil
        case ptr
        when AbstractPointer
            old_expr = ptr.load()
            ptr.store!(@assumption.conditionalize(old_expr, value))
        when Conditional
            @assumption.push(ptr.@cond, true)
            store(at: ptr.@valtrue, value: value)
            @assumption.pop

            @assumption.push(ptr.@cond, false)
            store(at: ptr.@valfalse, value: value)
            @assumption.pop
        else
            raise "Cannot store at #{ptr}"
        end
    end

    private def load (from ptr : DFGExpr) : DFGExpr
        case ptr
        when AbstractPointer
            return ptr.load()
        when Conditional
            return Isekai.dfg_make_conditional(
                ptr.@cond,
                load(from: ptr.@valtrue),
                load(from: ptr.@valfalse))
        else
            raise "Cannot load from #{ptr}"
        end
    end

    private def move_ptr (ptr : DFGExpr, by offset : DFGExpr) : DFGExpr
        case ptr
        when AbstractPointer
            return ptr.move(by: offset)
        when Conditional
            return Isekai.dfg_make_conditional(
                ptr.@cond,
                move_ptr(ptr.@valtrue, by: offset),
                move_ptr(ptr.@valfalse, by: offset))
        else
            raise "Cannot apply move_ptr to #{ptr}"
        end
    end

    private def get_field_ptr (base : DFGExpr, field : DFGExpr) : DFGExpr
        case base
        when Structure
            return PointerFactory.bake_field_pointer(base: base, field: field)
        when Conditional
            return Isekai.dfg_make_conditional(
                base.@cond,
                get_field_ptr(base: base.@valtrue, field: field),
                get_field_ptr(base: base.@valtrue, field: field))
        else
            raise "Cannot get_field_ptr of #{base}"
        end
    end

    private def get_element_ptr (base : DFGExpr) : DFGExpr
        result = base

        offset = yield
        return result unless offset
        result = move_ptr(result, by: offset)

        while field = yield
            result = load(from: result)
            result = get_field_ptr(base: result, field: field)
        end
        return result
    end

    private def inspect_basic_block_until (
            bb : LibLLVM::BasicBlock,
            terminator : LibLLVM::BasicBlock?)

        while bb != terminator
            raise "terminator not found (end of function reached)" unless bb
            bb = inspect_basic_block(bb)
        end
    end

    private def get_phi_value (ins) : DFGExpr
        begin
            # Note no 'as_expr()' here, as it calls '@assumption.reduce' on the result, which we
            # don't want here.
            return @locals[ins]
        rescue KeyError
            return make_undef_expr_of_ty_cached(LibLLVM_C.type_of(ins), cache_token: ins)
        end
    end

    private def produce_phi_copies (from : LibLLVM::BasicBlock, to : LibLLVM::BasicBlock)
        to.instructions.each do |ins|
            break unless LibLLVM_C.get_instruction_opcode(ins).phi?
            ins.incoming.each do |(block, value)|
                next unless block == from
                old_expr = get_phi_value(ins)
                @locals[ins] = @assumption.conditionalize(old_expr, as_expr(value))
            end
        end
    end

    private def unroll_hint_called (ins)
        raise "_unroll_hint() must be called with 1 argument" unless
            LibLLVM_C.get_num_arg_operands(ins) == 1

        arg = as_expr(LibLLVM_C.get_operand(ins, 0))

        raise "_unroll_hint() argument is not constant" unless arg.is_a? Constant
        value = arg.@value.to_i32
        raise "_unroll_hint() argument is out of bounds" if value < 0
        @loop_sanity_limit = value
    end

    @[AlwaysInline]
    private def set_binary (ins, klass)
        left = as_expr(LibLLVM_C.get_operand(ins, 0))
        right = as_expr(LibLLVM_C.get_operand(ins, 1))
        @locals[ins] = Isekai.dfg_make_binary(klass, left, right)
    end

    @[AlwaysInline]
    private def set_binary_swapped (ins, klass)
        left = as_expr(LibLLVM_C.get_operand(ins, 1))
        right = as_expr(LibLLVM_C.get_operand(ins, 0))
        @locals[ins] = Isekai.dfg_make_binary(klass, left, right)
    end

    @[AlwaysInline]
    private def set_bitwidth_cast (ins, klass)
        arg = as_expr(LibLLVM_C.get_operand(ins, 0))
        new_bitwidth = TypeUtils.get_int_ty_bitwidth(LibLLVM_C.type_of(ins))
        @locals[ins] = Isekai.dfg_make_bitwidth_cast(klass, arg, new_bitwidth)
    end

    private def inspect_basic_block (bb) : LibLLVM::BasicBlock?
        bb.instructions.each do |ins|
            case LibLLVM_C.get_instruction_opcode(ins)

            when .alloca?
                ty = LibLLVM_C.get_allocated_type(ins)
                expr = make_undef_expr_of_ty_cached(ty, cache_token: ins)
                @locals[ins] = StaticPointer.new(expr)

            when .store?
                src = as_expr(LibLLVM_C.get_operand(ins, 0))
                dst = as_expr(LibLLVM_C.get_operand(ins, 1))
                store(at: dst, value: src)

            when .load?
                src = as_expr(LibLLVM_C.get_operand(ins, 0))
                @locals[ins] = load(from: src)

            when .phi?
                @locals[ins] = get_phi_value(ins)

            when .get_element_ptr?
                nops = LibLLVM_C.get_num_operands(ins)
                base = as_expr(LibLLVM_C.get_operand(ins, 0))
                i = 1
                @locals[ins] = get_element_ptr(base) do
                    if i == nops
                        nil
                    else
                        expr = as_expr(LibLLVM_C.get_operand(ins, i))
                        i += 1
                        expr
                    end
                end

            when .add?   then set_binary(ins, Add)
            when .sub?   then set_binary(ins, Subtract)
            when .mul?   then set_binary(ins, Multiply)
            when .and?   then set_binary(ins, BitAnd)
            when .or?    then set_binary(ins, BitOr)
            when .xor?   then set_binary(ins, Xor)
            when .shl?   then set_binary(ins, LeftShift)
            when .a_shr? then set_binary(ins, SignedRightShift)
            when .l_shr? then set_binary(ins, RightShift)

            # TODO: is 'Divide' signed or unsigned?
            when .s_div? then set_binary(ins, Divide)
            when .u_div? then set_binary(ins, Divide)

            # TODO: is 'Modulo' signed or unsigned?
            when .s_rem? then set_binary(ins, Modulo)
            when .u_rem? then set_binary(ins, Modulo)

            when .i_cmp?
                pred = LibLLVM_C.get_i_cmp_predicate(ins)
                case pred

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

                else raise "unreachable"
                end

            when .z_ext? then set_bitwidth_cast(ins, ZeroExtend)
            when .s_ext? then set_bitwidth_cast(ins, SignExtend)
            when .trunc? then set_bitwidth_cast(ins, Truncate)

            # TODO: support for 'bitcast' instruction

            when .select?
                pred = as_expr(LibLLVM_C.get_operand(ins, 0))
                val_true = as_expr(LibLLVM_C.get_operand(ins, 1))
                val_false = as_expr(LibLLVM_C.get_operand(ins, 2))
                @locals[ins] = Isekai.dfg_make_conditional(pred, val_true, val_false)

            when .call?
                called = LibLLVM_C.get_called_value(ins)
                if called == @unroll_hint_func
                    unroll_hint_called(ins)
                else
                    raise "Unsupported function call"
                end

            when .br?
                successors = ins.successors.to_a
                successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                if ins.conditional?
                    cond = as_expr(LibLLVM_C.get_condition(ins))
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
                                @assumption.pop(ctl.n_dynamic_iters)
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

                        @assumption.push(cond, to_loop == if_true) unless static_branch
                        return to_loop
                    else
                        return static_branch if static_branch

                        @assumption.push(cond, true)
                        inspect_basic_block_until(if_true, terminator: sink)
                        @assumption.pop

                        @assumption.push(cond, false)
                        inspect_basic_block_until(if_false, terminator: sink)
                        @assumption.pop

                        return sink
                    end
                else
                    return successors[0]
                end

            when .switch?
                successors = ins.successors.to_a
                successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                arg = as_expr(LibLLVM_C.get_operand(ins, 0))
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

                    @assumption.push(cond, true)
                    inspect_basic_block_until(successors[i], terminator: sink)
                    @assumption.pop
                    @assumption.push(cond, false)
                end
                # inspect the default case
                inspect_basic_block_until(successors[0], terminator: sink)
                @assumption.pop(successors.size - 1)

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
            inspect_outsource_param(params[0], OutsourceParam::Input)
            inspect_outsource_param(params[1], OutsourceParam::Output)
        when 3
            inspect_outsource_param(params[0], OutsourceParam::Input)
            inspect_outsource_param(params[1], OutsourceParam::NizkInput)
            inspect_outsource_param(params[2], OutsourceParam::Output)
        else
            raise "outsource() takes #{params.size} parameter(s), expected 2 or 3"
        end

        @preproc_data = Preprocessor.new(func.entry_basic_block).data
        inspect_basic_block_until(func.entry_basic_block, terminator: nil)
        raise "Sanity-check failed" unless @assumption.empty?

        return {
            make_input_array(@input_struct),
            make_input_array(@nizk_input_struct),
            make_output_array(@output_struct),
        }
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
            return inspect_outsource_func(func)
        end

        raise "No 'outsource' function found"
    end
end

end
