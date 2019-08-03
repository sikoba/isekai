require "./dfg"
require "./frontend/symbol_table_key"
require "./frontend/storage"
require "./graph_utils"
require "llvm-crystal/lib_llvm"
require "llvm-crystal/lib_llvm_c"

# Assuming 'ins' is a terminator instruction, returns its successors as an array.
private def collect_successors(ins)
    n = LibLLVM_C.get_num_successors(ins)
    return Array(LibLLVM::BasicBlock).new(n) do |i|
        LibLLVM::BasicBlock.new(LibLLVM_C.get_successor(ins, i))
    end
end

# Assuming 'ins' is a switch instruction, returns the value (as an integer) of the case with
# number 'i' (1-based if we only consider 'case' statements without 'default', 0-based if we
# consider all the successors, of which the zeroth is the default).
private def get_case_value(ins, i)
    val = LibLLVM_C.get_operand(ins, i * 2)
    raise "Case value is not an integer constant" unless
        LibLLVM_C.get_value_kind(val).constant_int_value_kind?
    return LibLLVM_C.const_int_get_s_ext_value(val)
end

private class ControlFlowGraph

    @blocks = [] of LibLLVM::BasicBlock
    @block2idx = {} of LibLLVM::BasicBlock => Int32
    @sink : Int32 = -1

    private def discover (bb : LibLLVM::BasicBlock)
        return if @block2idx[bb]?

        idx = @blocks.size
        @blocks << bb
        @block2idx[bb] = idx

        has_succ = false
        bb.successors do |succ|
            has_succ = true
            discover(succ)
        end
        unless has_succ
            raise "Multiple sinks" unless @sink == -1
            @sink = idx
        end
    end

    def initialize (entry : LibLLVM::BasicBlock)
        discover(entry)
        raise "No sink" if @sink == -1
    end

    def nvertices
        return @blocks.size
    end

    def sink
        return @sink
    end

    def edges_from (v : Int32)
        @blocks[v].successors do |bb|
            yield @block2idx[bb]
        end
    end

    def block_to_idx (bb : LibLLVM::BasicBlock)
        return @block2idx[bb]
    end

    def idx_to_block (idx : Int32)
        return @blocks[idx]
    end
end

module Isekai

    class BitcodeParser

        private struct UnrollCtl
            private macro bool2i (b)
                if {{ b }}
                    1
                else
                    0
                end
            end

            @counter : Int32
            @n_dynamic_iters : Int32

            def initialize (@block : LibLLVM::BasicBlock, @limit : Int32, is_dynamic : Bool)
                @counter = 1
                @n_dynamic_iters = bool2i(is_dynamic)
            end

            def n_dynamic_iters
                @n_dynamic_iters
            end

            def done?
                return @counter == @limit
            end

            def iteration (is_dynamic : Bool)
                @counter += 1
                @n_dynamic_iters += bool2i(is_dynamic)
                return self
            end
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

        @cfg : ControlFlowGraph?
        @bfs_tree : GraphUtils::BfsTree?

        @chain = [] of Tuple(DFGExpr, Bool)
        @unroll_ctls = [] of UnrollCtl

        @unroll_hint_func : LibLLVM_C::ValueRef? = nil

        @ir_module : LibLLVM::IrModule

        def initialize (input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
            @ir_module = LibLLVM.module_from_buffer(LibLLVM.buffer_from_file(input_file))
        end

        private def init_graphs (entry : LibLLVM::BasicBlock)
            @cfg = cfg = ControlFlowGraph.new(entry)
            inv = GraphUtils.invert_graph(cfg)
            @bfs_tree = GraphUtils.build_bfs_tree(inv, cfg.sink)
        end

        private def with_chain_add_condition (
                old_expr : DFGExpr,
                new_expr : DFGExpr,
                chain_index : Int32 = 0) : DFGExpr

            if old_expr.is_a? Conditional && chain_index != @chain.size
                cond, flag = @chain[chain_index][0], @chain[chain_index][1]
                if cond === old_expr.@cond
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
                break unless cond === expr.@cond
                if flag
                    expr = expr.@valtrue
                else
                    expr = expr.@valfalse
                end
            end
            return expr
        end

        private def make_deref_op (expr : DFGExpr) : DFGExpr
            case expr
            when GetPointerOp
                expr.@target
            when AllocaOp
                @allocas[expr.@idx]
            else
                DerefOp.new(expr)
            end
        end

        private def make_undef_expr : DFGExpr
            return Constant.new(0)
        end

        private def make_input_array (storage : Storage?)
            return nil unless storage
            return Array(DFGExpr).new(storage.@size) do |i|
                Field.new(StorageKey.new(storage, i))
            end
        end

        private def get_meeting_point (a, b, junction)
            raise "@cfg not initialized" unless cfg = @cfg
            raise "@bfs_tree not initialized" unless bfs_tree = @bfs_tree
            lca, j_on_path = GraphUtils.tree_lca(
                bfs_tree,
                cfg.block_to_idx(a), cfg.block_to_idx(b), cfg.block_to_idx(junction))
            return {cfg.idx_to_block(lca), j_on_path}
        end

        private def inspect_param (ptr, ty, accept)
            raise "Function parameter is not a pointer" unless
                LibLLVM_C.get_type_kind(ty).pointer_type_kind?

            s_ty = LibLLVM_C.get_element_type(ty)

            raise "Function parameter is a pointer to non-struct" unless
                LibLLVM_C.get_type_kind(s_ty).struct_type_kind?

            raise "Function parameter is a pointer to an incomplete struct" unless
                LibLLVM_C.is_opaque_struct(s_ty) == 0

            s_name = String.new(LibLLVM_C.get_struct_name(s_ty))
            nelems = LibLLVM_C.count_struct_element_types(s_ty).to_i32

            case s_name
            when "struct.Input"
                raise "Wrong position for #{s_name}* parameter" unless accept.includes? :input
                st = Storage.new("Input", nelems)
                @input_storage = st

            when "struct.NzikInput" # sic
                raise "Wrong position for #{s_name}* parameter" unless accept.includes? :nizk_input
                st = Storage.new("NzikInput", nelems)
                @nizk_input_storage = st

            when "struct.Output"
                raise "Wrong position for #{s_name}* parameter" unless accept.includes? :output
                st = Storage.new("Output", nelems)
                @output_storage = st

            else
                raise "Unexpected parameter type: #{s_name}*"
            end

            @arguments[ptr] = GetPointerOp.new(Structure.new(st))
        end

        private def load_expr_preliminary (src) : DFGExpr
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

        private def load_expr (src) : DFGExpr
            expr = load_expr_preliminary(src)
            case expr
            when Field
                if expr.@key.@storage == @output_storage
                    expr = @outputs[expr.@key.@idx][1]
                end
            end
            expr = with_chain_reduce(expr)
            return expr
        end

        private def store (dst, expr : DFGExpr)
            dst_kind = LibLLVM_C.get_value_kind(dst)
            raise "NYI: unsupported dst kind: #{dst_kind}" unless dst_kind.instruction_value_kind?

            dst_expr = @locals[dst]
            case dst_expr

            when AllocaOp
                old_expr = @allocas[dst_expr.@idx]
                @allocas[dst_expr.@idx] = with_chain_add_condition(old_expr, expr)

            when GetPointerOp
                target = dst_expr.@target
                raise "NYI: cannot store at pointer to #{target}" unless target.is_a?(Field)
                raise "NYI: store in non-output struct" unless target.@key.@storage == @output_storage
                old_expr = @outputs[target.@key.@idx][1]
                @outputs[target.@key.@idx] = {target.@key, with_chain_add_condition(old_expr, expr)}

            else
                raise "NYI: cannot store at #{dst_expr}"
            end
        end

        private def get_element_ptr (base : DFGExpr, offset : DFGExpr, field : DFGExpr) : DFGExpr
            raise "NYI: GEP base is not a pointer" unless base.is_a?(GetPointerOp)
            raise "NYI: non-constant GEP offset" unless offset.is_a?(Constant)
            raise "NYI: non-constant GEP field" unless field.is_a?(Constant)

            raise "NYI: GEP with non-zero offset" unless offset.@value == 0

            target = base.@target
            raise "NYI: GEP target is not a struct" unless target.is_a?(Structure)

            key = StorageKey.new(target.@storage, field.@value)
            return GetPointerOp.new(Field.new(key))
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
            return @locals[ins]? || make_undef_expr
        end

        private def produce_phi_copies (from : LibLLVM::BasicBlock, to : LibLLVM::BasicBlock)
            to.instructions do |ins|
                break unless LibLLVM_C.get_instruction_opcode(ins).phi?
                (0...LibLLVM_C.count_incoming(ins)).each do |i|
                    next unless from.to_unsafe == LibLLVM_C.get_incoming_block(ins, i)
                    expr = load_expr(LibLLVM_C.get_incoming_value(ins, i))
                    @locals[ins] = with_chain_add_condition(get_phi_value(ins), expr)
                end
            end
        end

        private def inspect_basic_block (bb : LibLLVM::BasicBlock) : LibLLVM::BasicBlock?

            bb.instructions do |ins|
                case LibLLVM_C.get_instruction_opcode(ins)

                when .alloca?
                    #ty = LibLLVM_C.get_allocated_type(ins)
                    @locals[ins] = AllocaOp.new(@allocas.size)
                    @allocas << make_undef_expr

                when .store?
                    src = LibLLVM_C.get_operand(ins, 0)
                    dst = LibLLVM_C.get_operand(ins, 1)
                    store(dst: dst, expr: load_expr(src))

                when .load?
                    src = LibLLVM_C.get_operand(ins, 0)
                    @locals[ins] = make_deref_op(load_expr(src))

                when .phi?
                    @locals[ins] = get_phi_value(ins)

                when .get_element_ptr?
                    nops = LibLLVM_C.get_num_operands(ins)
                    raise "Not supported yet: #{nops}-arg GEP" unless nops == 3

                    base = LibLLVM_C.get_operand(ins, 0)
                    offset = LibLLVM_C.get_operand(ins, 1)
                    field = LibLLVM_C.get_operand(ins, 2)

                    @locals[ins] = get_element_ptr(
                        base: load_expr(base),
                        offset: load_expr(offset),
                        field: load_expr(field))

                when .add?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(Add, load_expr(left), load_expr(right))

                when .sub?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(Subtract, load_expr(left), load_expr(right))

                when .mul?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(Multiply, load_expr(left), load_expr(right))

                when .s_div?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(Divide, load_expr(left), load_expr(right))

                when .s_rem?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(Modulo, load_expr(left), load_expr(right))

                when .shl?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(LeftShift, load_expr(left), load_expr(right), 32)

                when .a_shr?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(RightShift, load_expr(left), load_expr(right), 32)

                when .and?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(BitAnd, load_expr(left), load_expr(right))

                when .or?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(BitOr, load_expr(left), load_expr(right))

                when .xor?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)
                    @locals[ins] = Isekai.dfg_make_binary(Xor, load_expr(left), load_expr(right))

                when .select?
                    pred = LibLLVM_C.get_operand(ins, 0)
                    valtrue = LibLLVM_C.get_operand(ins, 1)
                    valfalse = LibLLVM_C.get_operand(ins, 2)
                    @locals[ins] = Isekai.dfg_make_conditional(
                        load_expr(pred),
                        load_expr(valtrue),
                        load_expr(valfalse))

                when .call?
                    raise "Unsupported function call (not _unroll_hint)" unless
                        (uhf = @unroll_hint_func) && LibLLVM_C.get_called_value(ins) == uhf
                    raise "_unroll_hint must be called with 1 argument" unless
                        LibLLVM_C.get_num_arg_operands(ins) == 1
                    arg = LibLLVM_C.get_operand(ins, 0)

                    raise "_unroll_hint argument is not an integer constant" unless
                        LibLLVM_C.get_value_kind(arg).constant_int_value_kind?

                    value = LibLLVM_C.const_int_get_s_ext_value(arg).to_i32
                    raise "_unroll_hint argument is out of bounds" if value < 0

                    @loop_sanity_limit = value

                when .z_ext?
                    # TODO
                    target = LibLLVM_C.get_operand(ins, 0)
                    @locals[ins] = load_expr(target)

                when .i_cmp?
                    left = LibLLVM_C.get_operand(ins, 0)
                    right = LibLLVM_C.get_operand(ins, 1)

                    case LibLLVM_C.get_i_cmp_predicate(ins)
                    when .int_eq?
                        @locals[ins] = Isekai.dfg_make_binary(CmpEQ, load_expr(left), load_expr(right))
                    when .int_ne?
                        @locals[ins] = Isekai.dfg_make_binary(CmpNEQ, load_expr(left), load_expr(right))
                    else
                        raise "NYI: ICmp predicate"
                    end

                when .br?
                    successors = collect_successors(ins)
                    successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                    if LibLLVM_C.is_conditional(ins) != 0
                        # This is a conditional branch...
                        raise "Unsupported br form" unless successors.size == 2
                        cond = load_expr(LibLLVM_C.get_condition(ins))
                        if_true, if_false = successors

                        if cond.is_a? Constant
                            if cond.@value != 0
                                static_branch = if_true
                            else
                                static_branch = if_false
                            end
                        end

                        sink, is_loop = get_meeting_point(if_true, if_false, junction: bb)
                        if is_loop
                            if sink == if_true
                                to_loop = if_false
                            elsif sink == if_false
                                to_loop = if_true
                            else
                                raise "Unsupported control flow pattern"
                            end

                            if !@unroll_ctls.empty? && @unroll_ctls[-1].@block == sink
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
                                    sink, @loop_sanity_limit, is_dynamic: !static_branch)
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
                        # This is an unconditional branch.
                        raise "Unsupported br form" unless successors.size == 1
                        return successors[0]
                    end

                when .switch?
                    successors = collect_successors(ins)
                    successors.each { |succ| produce_phi_copies(from: bb, to: succ) }

                    sink = successors[0]
                    (1...successors.size).each do |i|
                        sink, is_loop = get_meeting_point(sink, successors[i], junction: bb)
                        raise "Unsupported control flow pattern" if is_loop
                    end

                    arg = load_expr(LibLLVM_C.get_operand(ins, 0))
                    if arg.is_a? Constant
                        (1...successors.size).each do |i|
                            if get_case_value(ins, i).to_i32 == arg.@value
                                return successors[i]
                            end
                        end
                        return successors[0]
                    end

                    # inspect each case
                    (1...successors.size).each do |i|
                        value = get_case_value(ins, i)
                        cond = Isekai.dfg_make_binary(CmpEQ, arg, Constant.new(value.to_i32))

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
                    repr = LibLLVM.slurp_string(LibLLVM_C.print_value_to_string(ins))
                    raise "Unsupported instruction: #{repr}"
                end
            end
        end

        private def inspect_root_func (func)
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
                inspect_param(params[0], param_tys[0], accept: {:input, :nizk_input})
                inspect_param(params[1], param_tys[1], accept: {:output})
            when 3
                inspect_param(params[0], param_tys[0], accept: {:input})
                inspect_param(params[1], param_tys[1], accept: {:nizk_input})
                inspect_param(params[2], param_tys[2], accept: {:output})
            else
                raise "Function takes #{func_nparams} parameter(s), expected 2 or 3"
            end

            @inputs      = make_input_array @input_storage
            @nizk_inputs = make_input_array @nizk_input_storage

            output_storage = @output_storage.as(Storage)
            @outputs = Array(Tuple(StorageKey, DFGExpr)).new(output_storage.@size) do |i|
                {StorageKey.new(output_storage, i), make_undef_expr}
            end

            init_graphs(func.entry_basic_block)
            inspect_basic_block_until(func.entry_basic_block, terminator: nil)
        end

        def parse ()
            @ir_module.functions do |func|
                if func.declaration? && func.name == "_unroll_hint"
                    @unroll_hint_func = func.to_unsafe
                end
            end
            @ir_module.functions do |func|
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
