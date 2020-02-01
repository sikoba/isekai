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

module Isekai::LLVMFrontend

# Assuming 'value' is a constant integer value, returns its value as a 'Constant' with the
# appropriate bitwidth.
def self.make_constant_unchecked (value) : Constant
    return Constant.new(
        value.zero_extended_int_value.to_i64!,
        bitwidth: TypeUtils.get_type_bitwidth_unchecked(value.type))
end

# Assuming 'operands' are operands of a 'switch' instruction, returns the value of the case with
# number 'i'. 'i' is 1-based if we only consider 'case' statements without 'default', and 0-based if
# we consider all the successors, of which the zeroth is the default (thus 'i == 0' is not allowed).
def self.get_case_value (operands, i) : Constant
    value = operands[i * 2]
    raise "Case value is not an integer constant" unless value.kind.constant_int_value_kind?
    return make_constant_unchecked(value)
end

def self.make_input_expr_of_type (type, which : InputBase::Kind) : DFGExpr
    offset = 0
    return TypeUtils.make_expr_of_type(type) do |scalar_type|
        case scalar_type.kind
        when .integer_type_kind?
            result = InputBase.new(
                which: which,
                idx: offset,
                bitwidth: TypeUtils.get_type_bitwidth_unchecked(scalar_type))
            offset += 1
            result
        when .pointer_type_kind?
            result = InputBase.new(
                which: which,
                idx: offset,
                bitwidth: BitWidth.new_for_undefined)
            offset += 1
            result
        else
            raise "unreachable"
        end
    end
end

def self.make_output_expr_of_type (type) : DFGExpr
    return TypeUtils.make_expr_of_type(type) do |scalar_type|
        case scalar_type.kind
        when .integer_type_kind?
            Constant.new(0, bitwidth: TypeUtils.get_type_bitwidth_unchecked(scalar_type))
        when .pointer_type_kind?
            NagaiVerbatim.new(BigInt.new(0))
        else
            raise "unreachable"
        end
    end
end

def self.make_input_array (s : Structure?) : Array(BitWidth)
    return s ? s.flattened.map &.@bitwidth : [] of BitWidth
end

def self.make_output_array (s : Structure?) : Array(DFGExpr)
    return s ? s.flattened : [] of DFGExpr
end

class Parser

    private struct UnrollCtl
        @counter : UInt32
        @n_dynamic_iters : UInt32

        def initialize (@junction : LibLLVM::BasicBlock, @limit : UInt32, is_dynamic : Bool)
            @counter = 1
            @n_dynamic_iters = is_dynamic ? 1_u32 : 0_u32
        end

        getter n_dynamic_iters, junction, limit

        def done?
            @counter == @limit
        end

        def iteration (is_dynamic : Bool)
            @counter += 1
            @n_dynamic_iters += is_dynamic ? 1 : 0
            return self
        end
    end

    private class Specials
        property unroll_hint : LibLLVM::Any? = nil
        property unroll_hint_once : LibLLVM::Any? = nil
        property unroll_hint_once_pop : LibLLVM::Any? = nil

        property nagai_init_pos : LibLLVM::Any? = nil
        property nagai_init_neg : LibLLVM::Any? = nil
        property nagai_init_from_str : LibLLVM::Any? = nil
        property nagai_copy : LibLLVM::Any? = nil
        property nagai_add : LibLLVM::Any? = nil
        property nagai_mul : LibLLVM::Any? = nil
        property nagai_getbit : LibLLVM::Any? = nil
        property nagai_div : LibLLVM::Any? = nil
        property nagai_nonzero : LibLLVM::Any? = nil
        property nagai_lowbits : LibLLVM::Any? = nil
        property nagai_free : LibLLVM::Any? = nil
    end

    enum OutsourceParam
        Input
        NizkInput
        Output
    end

    @arguments = {} of LibLLVM::Any => DFGExpr
    @locals = {} of LibLLVM::Any => DFGExpr

    # junction => {sink, is_loop}
    @preproc_data = {} of LibLLVM::BasicBlock => Tuple(LibLLVM::BasicBlock, Bool)

    @assumption = Assumption.new
    @unroll_ctls = [] of UnrollCtl

    @specials = Specials.new

    @input_struct : Structure? = nil
    @nizk_input_struct : Structure? = nil
    @output_struct : Structure? = nil

    @llvm_module : LibLLVM::Module

    @unroll_limit : UInt32
    @unroll_limit_pushed : UInt32? = nil

    def initialize (
            input_file : String,
            loop_sanity_limit : Int32,
            @p_bits_min : Int32)

        @llvm_module = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(input_file))
        @unroll_limit = loop_sanity_limit.to_u32
    end

    private def inspect_outsource_param (value : LibLLVM::Any, which_param : OutsourceParam) : Nil
        type = value.type
        raise "outsource() parameter is not a pointer" unless type.pointer?
        struct_type = type.element_type
        raise "outsource() parameter is a pointer to non-struct" unless struct_type.struct?

        case which_param
        when .input?
            expr = LLVMFrontend.make_input_expr_of_type(struct_type, InputBase::Kind::Input)
            raise "unreachable" unless expr.is_a? Structure
            @input_struct = expr

        when .nizk_input?
            expr = LLVMFrontend.make_input_expr_of_type(struct_type, InputBase::Kind::NizkInput)
            raise "unreachable" unless expr.is_a? Structure
            @nizk_input_struct = expr

        when .output?
            expr = LLVMFrontend.make_output_expr_of_type(struct_type)
            raise "unreachable" unless expr.is_a? Structure
            @output_struct = expr

        else
            raise "unreachable"
        end

        @arguments[value] = StaticPointer.new(expr)
    end

    private def eval_const_expr (value : LibLLVM::Any) : DFGExpr
        unless value.const_opcode.get_element_ptr?
            raise "only get_element_ptr constant expressions are supported (found '#{value}')"
        end

        text = value.const_operands[0]
        unless text.kind.global_variable_value_kind?
            raise "argument to constant-expression get_element_ptr must be global, not '#{text}'"
        end

        initializer = text.global_initializer
        unless initializer
            raise "global '#{value}' has no initializer"
        end
        unless initializer.kind.constant_data_array_value_kind?
            raise "global '#{value}' is not a constant array"
        end
        unless initializer.const_string?
            raise "global '#{value}' is not a constant string"
        end

        TypeUtils.byte_seq_to_expr(initializer.to_const_string)
    end

    private def as_expr (value : LibLLVM::Any) : DFGExpr
        case value.kind
        when .argument_value_kind?
            expr = @arguments[value]
        when .instruction_value_kind?
            # this is a reference to a local value created by 'value' instruction
            expr = @locals[value]
        when .constant_int_value_kind?
            expr = LLVMFrontend.make_constant_unchecked(value)
        when .constant_expr_value_kind?
            expr = eval_const_expr(value)
        else
            raise "Unsupported value kind: #{value.kind}"
        end
        @assumption.reduce(expr)
    end

    private def store (at ptr : DFGExpr, value : DFGExpr) : Nil
        case ptr
        when AbstractPointer
            ptr.store!(value, @assumption)
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
            return ptr.load(@assumption)
        when Conditional
            return Conditional.bake(
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
            return Conditional.bake(
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
            return Conditional.bake(
                base.@cond,
                get_field_ptr(base: base.@valtrue, field: field),
                get_field_ptr(base: base.@valfalse, field: field))
        else
            raise "Cannot get_field_ptr of #{base}"
        end
    end

    private def get_element_ptr (operands) : DFGExpr
        result = as_expr(operands[0])
        offset = as_expr(operands[1])
        result = move_ptr(result, by: offset)
        (2...operands.size).each do |i|
            result = get_field_ptr(base: load(from: result), field: as_expr(operands[i]))
        end
        result
    end

    private def inspect_basic_block_until (
            bb : LibLLVM::BasicBlock,
            terminator : LibLLVM::BasicBlock?) : Nil

        while bb != terminator
            raise "terminator not found (end of function reached)" unless bb
            bb = inspect_basic_block(bb)
        end
    end

    private def get_phi_value (ins : LibLLVM::Instruction) : DFGExpr
        # Note no 'as_expr()' here, as it calls '@assumption.reduce' on the result, which we
        # don't want here.
        return @locals[ins.to_any]? || TypeUtils.make_undef_expr_of_type(ins.type)
    end

    private def produce_phi_copies (from : LibLLVM::BasicBlock, to : LibLLVM::BasicBlock) : Nil
        to.instructions.each do |ins|
            break unless ins.opcode.phi?
            ins.incoming.each do |(block, value)|
                next unless block == from
                @locals[ins.to_any] = @assumption.conditionalize(
                    old_expr: get_phi_value(ins),
                    new_expr: as_expr(value))
            end
        end
    end

    private def handle_unroll_hint_call (ins : LibLLVM::Instruction) : Nil
    end

    @[AlwaysInline]
    private def set_binary (ins, klass) : Nil
        operands = ins.operands
        left = as_expr(operands[0])
        right = as_expr(operands[1])
        @locals[ins.to_any] = klass.bake(left, right)
    end

    @[AlwaysInline]
    private def set_binary_swapped (ins, klass) : Nil
        operands = ins.operands
        left = as_expr(operands[1])
        right = as_expr(operands[0])
        @locals[ins.to_any] = klass.bake(left, right)
    end

    @[AlwaysInline]
    private def set_bitwidth_cast (ins, klass) : Nil
        operands = ins.operands
        arg = as_expr(operands[0])
        new_bitwidth = TypeUtils.get_type_bitwidth(ins.type)
        @locals[ins.to_any] = klass.bake(arg, new_bitwidth)
    end

    private def handle_call (ins) : Nil
        operands = ins.operands
        case ins.callee
        when @specials.unroll_hint
            arg = as_expr(operands[0])
            raise "_unroll_hint() argument is not constant" unless arg.is_a? Constant
            @unroll_limit = arg.@value.to_u32

        when @specials.unroll_hint_once
            arg = as_expr(operands[0])
            raise "unroll_hint_once() argument is not constant" unless arg.is_a? Constant
            @unroll_limit_pushed = arg.@value.to_u32

        when @specials.unroll_hint_once_pop
            @unroll_limit_pushed = nil

        when @specials.nagai_init_pos
            @locals[ins.to_any] = Nagai.bake(
                as_expr(operands[0]),
                negative: false)

        when @specials.nagai_init_neg
            @locals[ins.to_any] = Nagai.bake(
                as_expr(operands[0]),
                negative: true)

        when @specials.nagai_init_from_str
            bytes = TypeUtils.expr_to_byte_seq(as_expr(operands[0]))
            unless bytes
                raise "'nagai_init_from_str': invalid argument: #{operands[0]}"
            end
            unless bytes.last? == 0
                raise "'nagai_init_from_str': argument is not zero-terminated"
            end
            @locals[ins.to_any] = NagaiVerbatim.new(
                BigInt.new(
                    String.new(bytes.to_unsafe),
                    base: 10
                )
            )

        when @specials.nagai_add
            @locals[ins.to_any] = NagaiAdd.bake(
                as_expr(operands[0]),
                as_expr(operands[1]),
                p_bits_min: @p_bits_min)

        when @specials.nagai_mul
            @locals[ins.to_any] = NagaiMultiply.bake(
                as_expr(operands[0]),
                as_expr(operands[1]),
                p_bits_min: @p_bits_min)

        when @specials.nagai_getbit
            @locals[ins.to_any] = NagaiGetBit.bake(
                as_expr(operands[0]),
                as_expr(operands[1]),
                p_bits_min: @p_bits_min)

        when @specials.nagai_div
            @locals[ins.to_any] = NagaiDivide.bake(
                as_expr(operands[0]),
                as_expr(operands[1]))

        when @specials.nagai_lowbits
            @locals[ins.to_any] = NagaiLowBits.bake(
                as_expr(operands[0]),
                p_bits_min: @p_bits_min)

        when @specials.nagai_nonzero
            @locals[ins.to_any] = NagaiNonZero.bake(
                as_expr(operands[0]),
                p_bits_min: @p_bits_min)

        when @specials.nagai_copy
            @locals[ins.to_any] = as_expr(operands[0])

        when @specials.nagai_free
            # do nothing

        else
            raise "Unsupported function called: #{ins.callee.name}"
        end
    end

    private def inspect_basic_block (bb) : LibLLVM::BasicBlock?
        bb.instructions.each do |ins|
            case ins.opcode

            when .alloca?
                @locals[ins.to_any] ||= StaticPointer.new(
                    TypeUtils.make_undef_expr_of_type(ins.alloca_type))

            when .store?
                operands = ins.operands
                src = as_expr(operands[0])
                dst = as_expr(operands[1])
                store(at: dst, value: src)

            when .load?
                operands = ins.operands
                src = as_expr(operands[0])
                @locals[ins.to_any] = load(from: src)

            when .phi?
                @locals[ins.to_any] = get_phi_value(ins)

            when .get_element_ptr?
                operands = ins.operands
                @locals[ins.to_any] = get_element_ptr(operands)

            when .add?   then set_binary(ins, Add)
            when .sub?   then set_binary(ins, Subtract)
            when .mul?   then set_binary(ins, Multiply)
            when .and?   then set_binary(ins, BitAnd)
            when .or?    then set_binary(ins, BitOr)
            when .xor?   then set_binary(ins, Xor)
            when .shl?   then set_binary(ins, LeftShift)
            when .a_shr? then set_binary(ins, SignedRightShift)
            when .l_shr? then set_binary(ins, RightShift)

            when .s_div? then set_binary(ins, SignedDivide)
            when .u_div? then set_binary(ins, Divide)

            when .s_rem? then set_binary(ins, SignedModulo)
            when .u_rem? then set_binary(ins, Modulo)

            when .i_cmp?
                case ins.icmp_predicate

                when .int_eq? then set_binary(ins, CmpEQ)
                when .int_ne? then set_binary(ins, CmpNEQ)

                when .int_slt? then set_binary(ins, SignedCmpLT)
                when .int_ult? then set_binary(ins, CmpLT)

                when .int_sle? then set_binary(ins, SignedCmpLEQ)
                when .int_ule? then set_binary(ins, CmpLEQ)

                when .int_sgt? then set_binary_swapped(ins, SignedCmpLT)
                when .int_ugt? then set_binary_swapped(ins, CmpLT)

                when .int_sge? then set_binary_swapped(ins, SignedCmpLEQ)
                when .int_uge? then set_binary_swapped(ins, CmpLEQ)

                else raise "unreachable"
                end

            when .z_ext? then set_bitwidth_cast(ins, ZeroExtend)
            when .s_ext? then set_bitwidth_cast(ins, SignExtend)
            when .trunc? then set_bitwidth_cast(ins, Truncate)

            when .select?
                operands = ins.operands
                pred = as_expr(operands[0])
                val_true = as_expr(operands[1])
                val_false = as_expr(operands[2])
                @locals[ins.to_any] = Conditional.bake(pred, val_true, val_false)

            when .call?
                handle_call(ins)

            when .br?
                successors = ins.successors.to_a
                successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                unless ins.conditional?
                    return successors[0]
                end

                cond = as_expr(ins.condition)
                if_true, if_false = successors

                if cond.is_a? Constant
                    static_branch = (cond.@value != 0) ? if_true : if_false
                end

                sink, is_loop = @preproc_data[bb]
                if is_loop
                    to_loop = (sink == if_true) ? if_false : if_true

                    if !@unroll_ctls.empty? && @unroll_ctls[-1].junction == bb
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
                        current_limit = @unroll_limit_pushed || @unroll_limit
                        if current_limit == 0 || static_branch == sink
                            raise "Statically infinite loop" if static_branch == to_loop
                            return sink
                        end
                        # New loop, start the unroll
                        @unroll_ctls << UnrollCtl.new(
                            junction: bb,
                            limit: current_limit,
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

            when .switch?
                successors = ins.successors.to_a
                successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                operands = ins.operands
                arg = as_expr(operands[0])
                if arg.is_a? Constant
                    (1...successors.size).each do |i|
                        case_value = LLVMFrontend.get_case_value(operands, i)
                        return successors[i] if case_value.@value == arg.@value
                    end
                    return successors[0]
                end

                sink, _ = @preproc_data[bb]
                # inspect each case
                (1...successors.size).each do |i|
                    cond = CmpEQ.bake(arg, LLVMFrontend.get_case_value(operands, i))

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

    private def inspect_outsource_func (func) : Nil
        signature = func.function_type
        raise "outsource() return type is not void" unless signature.return_type.void?
        raise "outsource() is a var arg function" if signature.var_args?

        params = func.params
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
    end

    private def check_special_func (
            func : LibLLVM::Function,
            return_type : TypeUtils::FuzzyType,
            arg_types : Array(TypeUtils::FuzzyType)) : LibLLVM::Any

        signature = func.function_type
        unless TypeUtils.fuzzy_match(signature.return_type, return_type)
            raise "#{func}: expected return type #{return_type}, found #{signature.return_type}"
        end
        if signature.var_args?
            raise "#{func}: declared as a var arg function" if signature.var_args?
        end

        params = func.params
        unless arg_types.size == params.size
            raise "#{func}: takes #{params.size} parameter(s), expected #{arg_types.size}"
        end
        (0...params.size).each do |i|
            expected, found = arg_types[i], params[i].type
            unless TypeUtils.fuzzy_match(found, expected)
                raise "#{func}: parameter #{i + 1}: expected type #{expected}, found #{found}"
            end
        end

        func.to_any
    end

    private def find_special_func (name) : LibLLVM::Function?
        func = @llvm_module.functions[name]?
        return nil unless func
        raise "Found definition of special function '#{name}'" unless func.declaration?
        func
    end

    def parse ()
        if (func = find_special_func "_unroll_hint")
            @specials.unroll_hint = check_special_func(
                func,
                return_type: LibLLVM::Type.new_void,
                arg_types: [
                    :integral,
                ]
            )
        end

        if (func = find_special_func "_unroll_hint_once")
            @specials.unroll_hint_once = check_special_func(
                func,
                return_type: LibLLVM::Type.new_void,
                arg_types: [
                    :integral,
                ]
            )
        end

        if (func = find_special_func "_unroll_hint_once_pop")
            @specials.unroll_hint_once_pop = check_special_func(
                func,
                return_type: LibLLVM::Type.new_void,
                arg_types: [] of TypeUtils::FuzzyType
            )
        end

        if (func = find_special_func "nagai_init_pos")
            @specials.nagai_init_pos = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    LibLLVM::Type.new_integral(nbits: 64),
                ]
            )
        end

        if (func = find_special_func "nagai_init_neg")
            @specials.nagai_init_neg = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    LibLLVM::Type.new_integral(nbits: 64),
                ]
            )
        end

        if (func = find_special_func "nagai_init_from_str")
            @specials.nagai_init_from_str = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_copy")
            @specials.nagai_copy = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_add")
            @specials.nagai_add = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    :pointer,
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_mul")
            @specials.nagai_mul = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    :pointer,
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_getbit")
            @specials.nagai_getbit = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    :pointer,
                    :integral,
                ]
            )
        end

        if (func = find_special_func "nagai_div")
            @specials.nagai_div = check_special_func(
                func,
                return_type: :pointer,
                arg_types: [
                    :pointer,
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_nonzero")
            @specials.nagai_nonzero = check_special_func(
                func,
                return_type: LibLLVM::Type.new_integral(nbits: 1),
                arg_types: [
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_lowbits")
            @specials.nagai_lowbits = check_special_func(
                func,
                return_type: LibLLVM::Type.new_integral(nbits: 64),
                arg_types: [
                    :pointer,
                ]
            )
        end

        if (func = find_special_func "nagai_free")
            @specials.nagai_free = check_special_func(
                func,
                return_type: LibLLVM::Type.new_void,
                arg_types: [
                    :pointer,
                ]
            )
        end

        func = @llvm_module.functions["outsource"]
        raise "'outsource' function is only declared but not defined" if func.declaration?
        inspect_outsource_func(func)
        return {
            LLVMFrontend.make_input_array(@input_struct),
            LLVMFrontend.make_input_array(@nizk_input_struct),
            LLVMFrontend.make_output_array(@output_struct),
        }
    end
end

end
