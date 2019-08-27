require "./cfg"
require "./graph_utils"
require "./containers"
require "llvm-crystal/lib_llvm"

module Isekai::LLVMFrontend

private class Preprocessor
    private class InvalidGraph < Exception
    end

    @cur_sinks = Containers::Multiset(LibLLVM::BasicBlock).new
    @cfg : ControlFlowGraph
    @bfs_tree : GraphUtils::BfsTree
    # junction => {sink, is_loop}
    @data = {} of LibLLVM::BasicBlock => Tuple(LibLLVM::BasicBlock, Bool)

    private def meeting_point (a, b, junction)
        lca, is_loop = GraphUtils.tree_lca(
            @bfs_tree,
            @cfg.block_to_idx(a),
            @cfg.block_to_idx(b),
            @cfg.block_to_idx(junction))
        return {@cfg.idx_to_block(lca), is_loop}
    end

    private def inspect_until (bb : LibLLVM::BasicBlock, terminator : LibLLVM::BasicBlock?) : Nil
        while bb != terminator
            raise InvalidGraph.new unless bb
            bb = inspect(bb)
        end
    end

    private def inspect (bb) : LibLLVM::BasicBlock?
        raise InvalidGraph.new if @cur_sinks.includes? bb

        ins = bb.terminator
        successors = ins.successors.to_a

        case ins.opcode
        when .br?
            if ins.conditional?
                if_true, if_false = successors

                sink, is_loop = meeting_point(if_true, if_false, junction: bb)
                if is_loop
                    case sink
                    when if_true  then to_loop = if_false
                    when if_false then to_loop = if_true
                    else raise InvalidGraph.new
                    end
                    inspect_until(to_loop, terminator: bb)
                else
                    while true
                        @cur_sinks.add sink
                        begin
                            inspect_until(if_true, terminator: sink)
                            inspect_until(if_false, terminator: sink)
                        rescue InvalidGraph
                            @cur_sinks.delete sink
                            old_sink = sink
                            old_sink.terminator.successors.each do |succ|
                                sink, is_loop = meeting_point(sink, succ, junction: bb)
                                raise InvalidGraph.new if is_loop
                            end
                            raise InvalidGraph.new if sink == old_sink
                        else
                            @cur_sinks.delete sink
                            break
                        end
                    end
                end

                @data[bb] = {sink, is_loop}
                return sink
            else
                return successors[0]
            end

        when .switch?
            sink = successors[0]
            (1...successors.size).each do |i|
                sink, is_loop = meeting_point(sink, successors[i], junction: bb)
                raise InvalidGraph.new if is_loop
            end

            # emulate the order in which 'Parser::inspect_basic_block' visits the successors
            (1...successors.size).each do |i|
                inspect_until(successors[i], terminator: sink)
            end
            inspect_until(successors[0], terminator: sink)

            @data[bb] = {sink, false}
            return sink

        when .ret?
            return nil

        else
            raise "Unsupported terminator instruction: #{ins}"
        end
    end

    def initialize (entry : LibLLVM::BasicBlock)
        @cfg = ControlFlowGraph.new(entry)
        inv = GraphUtils.invert_graph(@cfg)
        @bfs_tree = GraphUtils.build_bfs_tree(on: inv, from: @cfg.final_block_idx)
        inspect_until(entry, terminator: nil)
    end

    def data
        @data
    end
end

end
