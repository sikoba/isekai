require "../common/dfg"
require "../common/bitwidth"
require "../common/symbol_table_key"
require "../common/storage"
require "./preproc"
require "./assumption"
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

        def [] (k : LibLLVM::Instruction)
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

        def has_key? (k : LibLLVM_C::ValueRef)
            @hash.has_key?(k)
        end

        def has_key? (k : LibLLVM::Instruction)
            @hash.has_key?(k.to_unsafe)
        end
    end

    enum OutsourceParam
        Input
        NizkInput
        Output
    end

    enum OutsourceInputParam
        Input
        NizkInput
    end

    private class ValStruct
        def initialize (@elems : Array(DFGExpr))
        end

        def bitwidth_of (i)
            @elems[i].@bitwidth
        end

        def index_valid? (i)
            i >= 0 && i < @elems.size
        end
    end

    private class ValInputStruct < ValStruct
        def initialize (
                @elems : Array(DFGExpr),
                @flat_offsets : Array(Int32),
                @flat_size : Int32)
        end
    end

    private class IndexRange
        @left  : Int32 = -1
        @right : Int32 = -1

        property left
        property right

        def initialize ()
        end

        def includes? (x)
            @left <= x < @right
        end

        def outermost
            @left == @right ? nil : (@right - 1)
        end
    end

    @arguments = World.new
    @locals = World.new
    @allocas = [] of DFGExpr
    @cached_undefs = World.new

    @val_structs = [] of ValStruct

    # junction => {sink, is_loop}
    @preproc_data = {} of LibLLVM::BasicBlock => Tuple(LibLLVM::BasicBlock, Bool)

    @assumption = Assumption.new
    @unroll_ctls = [] of UnrollCtl

    @unroll_hint_func : LibLLVM_C::ValueRef? = nil

    @input_indices = IndexRange.new
    @nizk_input_indices = IndexRange.new
    @output_indices = IndexRange.new

    @input_storage : Storage? = nil
    @nizk_input_storage : Storage? = nil

    @ir_module : LibLLVM::IrModule

    def initialize (input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
        @ir_module = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(input_file))
    end

    private def cache_undef (value)
        return yield unless value
        begin
            return @cached_undefs[value]
        rescue KeyError
            return @cached_undefs[value] = yield
        end
    end

    # Constructs an expression aprropriate for an undefined value of the given type 'ty'.
    private def make_undef_for_ty (ty, value = nil) : DFGExpr
        kind = LibLLVM_C.get_type_kind(ty)
        case kind

        when .integer_type_kind?
            return Constant.new(0, bitwidth: get_int_ty_bitwidth_unchecked(ty))

        when .pointer_type_kind?
            return DynamicPointer.new

        when .array_type_kind?
            return cache_undef(value) do
                nelems = LibLLVM_C.get_array_length(ty)
                elem_ty = LibLLVM_C.get_element_type(ty)
                elems = Array(DFGExpr).new(nelems) do
                    make_undef_for_ty(elem_ty)
                end
                @val_structs << ValStruct.new(elems)
                CoolStruct.new(idx: @val_structs.size - 1)
            end

        when .struct_type_kind?
            return cache_undef(value) do
                nelems = LibLLVM_C.count_struct_element_types(ty)
                elems = Array(DFGExpr).new(nelems) do |i|
                    elem_ty = LibLLVM_C.struct_get_type_at_index(ty, i)
                    make_undef_for_ty(elem_ty)
                end
                @val_structs << ValStruct.new(elems)
                CoolStruct.new(idx: @val_structs.size - 1)
            end

        else
            raise "Unsupported type kind: #{kind}"
        end
    end

    private def convert_into_input_struct! (expr : DFGExpr, start_from : Int32) : Int32
        return start_from + 1 unless expr.is_a? CoolStruct

        elems = @val_structs[expr.@idx].@elems
        flat_offsets = Array(Int32).new(elems.size)

        offset = start_from
        elems.each do |elem|
            flat_offsets << offset
            offset = convert_into_input_struct!(elem, start_from: offset)
        end
        @val_structs[expr.@idx] = ValInputStruct.new(
            elems: elems,
            flat_offsets: flat_offsets,
            flat_size: offset)
        return offset
    end

    private def input_idx? (idx) : OutsourceInputParam?
        if @input_indices.includes? idx
            return OutsourceInputParam::Input
        elsif @nizk_input_indices.includes? idx
            return OutsourceInputParam::NizkInput
        else
            return nil
        end
    end

    private def dereference (expr : DFGExpr, even_input = false) : DFGExpr
        case expr
        when GetPointer
            expr = expr.@target
        when Alloca
            expr = @allocas[expr.@idx]
        else
            raise "Cannot dereference #{expr}"
        end

        case expr
        when CoolField
            st = @val_structs[expr.@struct_idx]
            if which_input = input_idx? expr.@struct_idx
                if even_input
                    expr = st.@elems[expr.@field_idx]
                else
                    flat_idx = st.as(ValInputStruct).@flat_offsets[expr.@field_idx]
                    bitwidth = st.bitwidth_of(expr.@field_idx)

                    case which_input
                    when OutsourceInputParam::Input
                        storage = @input_storage.as(Storage)
                    when OutsourceInputParam::NizkInput
                        storage = @nizk_input_storage.as(Storage)
                    else
                        raise "Unexpected OutsourceInputParam"
                    end

                    expr = Field.new(StorageKey.new(storage, flat_idx), bitwidth: bitwidth)
                end
            else
                expr = st.@elems[expr.@field_idx]
            end
        end

        return expr
    end

    private def modify_index_range (ir : IndexRange)
        ir.left = @val_structs.size
        result = yield
        ir.right = @val_structs.size
        return result
    end

    private def inspect_outsource_param (value, param_kind)
        ty = LibLLVM_C.type_of(value)
        raise "outsource() parameter is not a pointer" unless
            LibLLVM_C.get_type_kind(ty).pointer_type_kind?

        s_ty = LibLLVM_C.get_element_type(ty)

        raise "outsource() parameter is a pointer to non-struct" unless
            LibLLVM_C.get_type_kind(s_ty).struct_type_kind?

        raise "outsource() parameter is a pointer to an incomplete struct" unless
            LibLLVM_C.is_opaque_struct(s_ty) == 0

        case param_kind
        when OutsourceParam::Input
            expr = modify_index_range(@input_indices) { make_undef_for_ty(s_ty) }
            convert_into_input_struct!(expr, start_from: 0)
        when OutsourceParam::NizkInput
            expr = modify_index_range(@nizk_input_indices) { make_undef_for_ty(s_ty) }
            convert_into_input_struct!(expr, start_from: 0)
        when OutsourceParam::Output
            expr = modify_index_range(@output_indices) { make_undef_for_ty(s_ty) }
            # yep, this is required...
            convert_into_input_struct!(expr, start_from: 0)
        else
            raise "Unexpected param_kind: #{param_kind}"
        end

        @arguments[value] = GetPointer.new(expr)
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
        expr = @assumption.reduce(expr)
        return expr
    end

    private def store (dst : DFGExpr, src : DFGExpr)
        case dst

        when Alloca
            old_expr = @allocas[dst.@idx]
            @allocas[dst.@idx] = @assumption.conditionalize(old_expr, src)

        when GetPointer
            target = dst.@target
            case target
            when CoolField
                raise "Cannot store in input parameter" if input_idx? target.@struct_idx
                st = @val_structs[target.@struct_idx]
                old_expr = st.@elems[target.@field_idx]
                st.@elems[target.@field_idx] = @assumption.conditionalize(old_expr, src)
            else
                raise "Cannot store at pointer to #{target}"
            end

        else
            raise "Cannot store at #{dst}"
        end
    end

    private def get_element_ptr (base : DFGExpr, offset : DFGExpr, field : DFGExpr) : DFGExpr
        raise "NYI: non-constant GEP offset" unless offset.is_a?(Constant)
        raise "NYI: non-constant GEP field" unless field.is_a?(Constant)

        target = dereference(base, even_input: true)

        case target
        when CoolStruct
            raise "NYI: GEP of struct with non-zero offset" unless offset.@value == 0
            elem_idx = field.@value
            unless @val_structs[target.@idx].index_valid? elem_idx
                raise "Array index is out of bounds"
            end
            return GetPointer.new(CoolField.new(
                struct_idx: target.@idx,
                field_idx: elem_idx.to_i32))
        else
            raise "NYI: cannot GEP of pointer to #{target}"
        end
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
        return @locals.fetch(ins) { make_undef_for_ty(LibLLVM_C.type_of(ins), ins) }
    end

    private def produce_phi_copies (from : LibLLVM::BasicBlock, to : LibLLVM::BasicBlock)
        to.instructions.each do |ins|
            break unless LibLLVM_C.get_instruction_opcode(ins).phi?
            ins.incoming.each do |(block, value)|
                next unless block == from
                old_expr = get_phi_value(ins)
                @locals[ins] = @assumption.conditionalize(old_expr, load_expr(value))
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
                expr = make_undef_for_ty(ty, ins)
                begin
                    existing = @locals[ins]
                rescue KeyError
                    @locals[ins] = Alloca.new(@allocas.size)
                    @allocas << expr
                else
                    @allocas[existing.as(Alloca).@idx] = expr
                end

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
                raise "NYI: #{nops}-arg GEP" unless nops == 3

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

                else raise "Unknown 'icmp' predicate: #{pred}"
                end

            when .z_ext? then set_bitwidth_cast(ins, ZeroExtend)
            when .s_ext? then set_bitwidth_cast(ins, SignExtend)
            when .trunc? then set_bitwidth_cast(ins, Truncate)

            # TODO: support bitcast instruction?

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

    private def each_in_flattened (idx, &block : DFGExpr->)
        @val_structs[idx].@elems.each do |elem|
            if elem.is_a? CoolStruct
                each_in_flattened(elem.@idx, &block)
            else
                block.call elem
            end
        end
    end

    private def make_input_array (name, indices)
        idx = indices.outermost
        return {nil, [] of DFGExpr} unless idx

        n = @val_structs[idx].as(ValInputStruct).@flat_size
        storage = Storage.new(name, n)
        arr = Array(DFGExpr).new(n)
        each_in_flattened(idx) do |elem|
            i = arr.size
            arr << Field.new(StorageKey.new(storage, i), bitwidth: elem.@bitwidth)
        end
        return {storage, arr}
    end

    private def make_output_array (name, indices)
        idx = indices.outermost
        return [] of Tuple(StorageKey, DFGExpr) unless idx

        n = @val_structs[idx].as(ValInputStruct).@flat_size
        storage = Storage.new(name, n)
        arr = Array(Tuple(StorageKey, DFGExpr)).new(n)
        each_in_flattened(idx) do |elem|
            i = arr.size
            arr << {StorageKey.new(storage, i), elem}
        end
        return arr
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

        @input_storage, inputs = make_input_array("input", @input_indices)
        @nizk_input_storage, nizk_inputs = make_input_array("nizk_input", @nizk_input_indices)

        @preproc_data = Preprocessor.new(func.entry_basic_block).data
        inspect_basic_block_until(func.entry_basic_block, terminator: nil)
        raise "Sanity-check failed" unless @assumption.empty?

        return inputs, nizk_inputs, make_output_array("output", @output_indices)
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
