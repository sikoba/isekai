require "./dfg"
require "./frontend/symbol_table_key"
require "./frontend/storage"
require "llvm-crystal/lib_llvm"
require "llvm-crystal/lib_llvm_c"

module Isekai

    class BFSTraverser

        def initialize (bb : LibLLVM::BasicBlock)
            @queue = [bb]
            @queue_start = 0
            @seen = Set{bb}
        end

        private def maybe_add (bb : LibLLVM::BasicBlock)
            return if @seen.includes? bb
            @seen.add(bb)
            @queue << bb
        end

        def next!
            return nil if @queue_start == @queue.size
            bb = @queue[@queue_start]
            @queue_start += 1

            ins = bb.last_instruction
            case LibLLVM_C.get_instruction_opcode(ins)
            when .br?
                (0...LibLLVM_C.get_num_successors(ins)).each do |i|
                    maybe_add(LibLLVM::BasicBlock.new(LibLLVM_C.get_successor(ins, i)))
                end

            when .ret?
                # do nothing
            else
                raise "NYI block terminator instruction (switch?)"
            end

            bb
        end

        def seen? (bb : LibLLVM::BasicBlock)
            @seen.includes? bb
        end
    end

    class BitcodeParser

        def self.select_insert (
                old_expr : DFGExpr,
                new_expr : DFGExpr,
                chain : Array(Tuple(DFGExpr, Bool)),
                chain_index : Int32 = 0) : DFGExpr

            if old_expr.is_a? Conditional && chain_index != chain.size
                cond, flag = chain[chain_index][0], chain[chain_index][1]
                if cond == old_expr.@cond
                    valtrue, valfalse = old_expr.@valtrue, old_expr.@valfalse
                    if flag
                        valtrue = select_insert(valtrue, new_expr, chain, chain_index + 1)
                    else
                        valfalse = select_insert(valfalse, new_expr, chain, chain_index + 1)
                    end
                    return Conditional.new(cond, valtrue, valfalse)
                end
            end

            result = new_expr
            (chain_index...chain.size).reverse_each do |i|
                cond, flag = chain[i][0], chain[i][1]
                if flag
                    result = Conditional.new(cond, result, old_expr)
                else
                    result = Conditional.new(cond, old_expr, result)
                end
            end
            return result
        end

        def self.select_reduce (
                expr : DFGExpr,
                chain : Array(Tuple(DFGExpr, Bool))) : DFGExpr

            chain.each do |(cond, flag)|
                break unless expr.is_a? Conditional
                break unless cond == expr.@cond
                if flag
                    expr = expr.@valtrue
                else
                    expr = expr.@valfalse
                end
            end
            return expr
        end

        def self.make_deref_op (expr : DFGExpr) : DFGExpr
            if expr.is_a?(GetPointerOp)
                expr.@target
            else
                DerefOp.new(expr)
            end
        end

        def self.make_getptr_op (expr : DFGExpr) : DFGExpr
            if expr.is_a?(DerefOp)
                expr.@target
            else
                GetPointerOp.new(expr)
            end
        end

        def self.make_undef_expr! : DFGExpr
            return Constant.new(0)
        end

        def self.make_input_array (storage : Storage?)
            return nil unless storage
            arr = Array(DFGExpr).new
            (0...storage.@size).each do |i|
                arr << Field.new(StorageKey.new(storage, i))
            end
            return arr
        end

        @inputs : Array(DFGExpr)?
        @nizk_inputs : Array(DFGExpr)?
        @outputs = [] of Tuple(StorageKey, DFGExpr)

        @arguments = {} of LibLLVM_C::ValueRef => DFGExpr
        @locals = {} of LibLLVM_C::ValueRef => DFGExpr
        @allocas = [] of DFGExpr

        @input_storage : Storage?
        @nizk_input_storage : Storage?
        @output_storage : Storage?

        @inspected_blocks = Set(LibLLVM::BasicBlock).new

        @chain = [] of Tuple(DFGExpr, Bool)

        def initialize (@input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
        end

        def inspect_param (is_input : Bool, ptr, ty)
            raise "Function parameter is not a pointer" unless
                LibLLVM_C.get_type_kind(ty).pointer_type_kind?

            s_ty = LibLLVM_C.get_element_type(ty)

            raise "Function parameter is a pointer to non-struct" unless
                LibLLVM_C.get_type_kind(s_ty).struct_type_kind?

            raise "Function parameter is a pointer to an incomplete struct" unless
                LibLLVM_C.is_opaque_struct(s_ty) == 0

            s_name = String.new(LibLLVM_C.get_struct_name(s_ty))
            nelems = LibLLVM_C.count_struct_element_types(s_ty).to_i32

            if is_input
                case s_name
                when "struct.Input"
                    raise "Duplicate param type" if @input_storage
                    st = Storage.new("Input", nelems)
                    @input_storage = st

                when "struct.NzikInput" # sic
                    raise "Duplicate param type" if @nizk_input_storage
                    st = Storage.new("NzikInput", nelems)
                    @nizk_input_storage = st

                else
                    raise "Invalid param type: #{s_name} for input parameter"
                end
            else
                raise "Invalid param type: #{s_name} for output parameter" unless
                    s_name == "struct.Output"
                raise "Duplicate param type" if @output_storage
                st = Storage.new("Output", nelems)
                @output_storage = st
            end

            @arguments[ptr] = GetPointerOp.new(Structure.new(st))
        end

        def load_expr_preliminary (src) : DFGExpr
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

        def load_expr (src) : DFGExpr
            expr = load_expr_preliminary(src)
            # TODO: collapse it properly
            case expr
            when .is_a?(AllocaOp)
                expr = BitcodeParser.make_getptr_op(@allocas[expr.@idx])
            when .is_a?(Field)
                if expr.@key.@storage == @output_storage
                    expr = @outputs[expr.@key.@idx][1]
                end
            end

            expr = BitcodeParser.select_reduce(expr, @chain)

            expr
        end

        def store (dst, expr : DFGExpr)
            # TODO: collapse it properly

            dst_kind = LibLLVM_C.get_value_kind(dst)
            raise "NYI: unsupported dst kind: #{dst_kind}" unless dst_kind.instruction_value_kind?

            dst_expr = @locals[dst]
            case dst_expr

            when .is_a?(AllocaOp)
                old_expr = @allocas[dst_expr.@idx]
                @allocas[dst_expr.@idx] = BitcodeParser.select_insert(old_expr, expr, @chain)

            when .is_a?(GetPointerOp)
                target = dst_expr.@target
                raise "NYI: cannot store at pointer to #{target}" unless target.is_a?(Field)
                field = target.as(Field)
                raise "NYI: store in non-output struct" unless field.@key.@storage == @output_storage
                old_expr = @outputs[field.@key.@idx][1]
                @outputs[field.@key.@idx] = {
                    field.@key,
                    BitcodeParser.select_insert(old_expr, expr, @chain)
                }

            else
                raise "NYI: cannot store at #{dst_expr}"
            end
        end

        def get_element_ptr (base : DFGExpr, offset : DFGExpr, field : DFGExpr) : DFGExpr
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

        # TODO make this function static?
        def get_meeting_point (a, b, junction)
            trav_a = BFSTraverser.new(a)
            trav_b = BFSTraverser.new(b)
            while true
                x = trav_a.next!
                return junction if x == junction
                return x if x && trav_b.seen? x

                y = trav_b.next!
                return junction if y == junction
                return y if y && trav_a.seen? y

                return nil unless x || y
            end
        end

        def inspect_basic_block_until (
                bb : LibLLVM::BasicBlock,
                terminator : LibLLVM::BasicBlock?)

            while bb != terminator
                raise "terminator not found (end of function reached)" unless bb
                bb = inspect_basic_block(bb)
            end
        end

        def inspect_basic_block (bb : LibLLVM::BasicBlock) : LibLLVM::BasicBlock?

            if @inspected_blocks.includes?(bb)
                raise "NYI: loop"
            end
            @inspected_blocks.add(bb)

            bb.instructions do |ins|
                case LibLLVM_C.get_instruction_opcode(ins)

                when .alloca?
                    #ty = LibLLVM_C.get_allocated_type(ins)
                    @locals[ins] = AllocaOp.new(@allocas.size)
                    @allocas << BitcodeParser.make_undef_expr!

                when .store?
                    src = LibLLVM_C.get_operand(ins, 0)
                    dst = LibLLVM_C.get_operand(ins, 1)
                    store(dst, load_expr(src))

                when .load?
                    src = LibLLVM_C.get_operand(ins, 0)
                    @locals[ins] = BitcodeParser.make_deref_op(load_expr(src))

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

                when .sub?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Subtract.new(load_expr(left), load_expr(right))

                when .mul?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Multiply.new(load_expr(left), load_expr(right))

                when .s_div?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Divide.new(load_expr(left), load_expr(right))

                when .s_rem?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Modulo.new(load_expr(left), load_expr(right))

                when .shl?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = LeftShift.new(load_expr(left), load_expr(right), 32)

                when .a_shr?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = RightShift.new(load_expr(left), load_expr(right), 32)

                when .and?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = BitAnd.new(load_expr(left), load_expr(right))

                when .or?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = BitOr.new(load_expr(left), load_expr(right))

                when .xor?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Xor.new(load_expr(left), load_expr(right))

                when .select?
                    pred = LibLLVM_C.get_operand(ins, 0)
                    valtrue = LibLLVM_C.get_operand(ins, 1)
                    valfalse = LibLLVM_C.get_operand(ins, 2)
                    @locals[ins] = Conditional.new(
                        load_expr(pred),
                        load_expr(valtrue),
                        load_expr(valfalse))

                when .z_ext?
                    target = LibLLVM_C.get_operand(ins, 0)
                    @locals[ins] = load_expr(target)

                when .i_cmp?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)

                    case LibLLVM_C.get_i_cmp_predicate(ins)
                    when .int_eq?
                        @locals[ins] = CmpEQ.new(load_expr(left), load_expr(right))
                    when .int_ne?
                        @locals[ins] = CmpNEQ.new(load_expr(left), load_expr(right))
                    else
                        raise "NYI: ICmp predicate"
                    end

                when .br?
                    has_cond = LibLLVM_C.is_conditional(ins) != 0
                    if has_cond
                        raise "Unsupported br form" unless LibLLVM_C.get_num_successors(ins) == 2

                        cond = load_expr(LibLLVM_C.get_condition(ins))
                        if_true  = LibLLVM::BasicBlock.new(LibLLVM_C.get_successor(ins, 0))
                        if_false = LibLLVM::BasicBlock.new(LibLLVM_C.get_successor(ins, 1))

                        sink = get_meeting_point(if_true, if_false, bb)
                        if sink == bb
                            raise "ELOOP"
                        end

                        @chain << {cond, true}
                        inspect_basic_block_until(if_true, sink)
                        @chain.pop

                        @chain << {cond, false}
                        inspect_basic_block_until(if_false, sink)
                        @chain.pop

                        return sink
                    else
                        raise "Unsupported br form" unless LibLLVM_C.get_num_successors(ins) == 1
                        target = LibLLVM::BasicBlock.new(LibLLVM_C.get_successor(ins, 0))
                        return target
                    end

                when .ret?
                    # We assume this is "ret void" as the function returns void.
                    return nil

                else
                    repr = LibLLVM.slurp_string(LibLLVM_C.print_value_to_string(ins))
                    raise "Unsupported instruction: #{repr}"
                end
            end
        end

        def inspect_root_func (func)
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
                inspect_param(true,  params[0], param_tys[0])
                inspect_param(false, params[1], param_tys[1])
            when 3
                inspect_param(true,  params[0], param_tys[0])
                inspect_param(true,  params[1], param_tys[1])
                inspect_param(false, params[2], param_tys[2])
            else
                raise "Function takes #{func_nparams} parameter(s), expected 2 or 3"
            end

            @inputs      = BitcodeParser.make_input_array @input_storage
            @nizk_inputs = BitcodeParser.make_input_array @nizk_input_storage

            output_storage = @output_storage.as(Storage)
            (0...output_storage.@size).each do |i|
                @outputs << {
                    StorageKey.new(output_storage, i),
                    BitcodeParser.make_undef_expr!
                }
            end

            inspect_basic_block_until(func.entry_basic_block, nil)
        end

        def parse ()
            module_ = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(@input_file))
            module_.functions do |func|
                next if func.declaration?
                raise "Unexpected function defined: #{func.name}" unless
                    func.name == "outsource"
                inspect_root_func(func)
                return {@inputs || [] of DFGExpr, @nizk_inputs, @outputs}
            end

            raise "No 'outsource' function found"
        end
    end
end