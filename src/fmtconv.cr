require "./common/dfg"

module Isekai

abstract class DFGExpr
    def modify_leafs! (block) : DFGExpr
        raise "Not implemented"
    end
end

class InputBase
    def modify_leafs! (block) : DFGExpr
        block.call(self)
    end
end

class Field
    def modify_leafs! (block) : DFGExpr
        block.call(self)
    end
end

class Constant
    def modify_leafs! (block) : DFGExpr
        block.call(self)
    end
end

class Conditional
    def modify_leafs! (block) : DFGExpr
        @cond = @cond.modify_leafs!(block)
        @valtrue = @valtrue.modify_leafs!(block)
        @valfalse = @valfalse.modify_leafs!(block)
        self
    end
end

class BinaryOp
    def modify_leafs! (block) : DFGExpr
        @left = @left.modify_leafs!(block)
        @right = @right.modify_leafs!(block)
        self
    end
end

class UnaryOp
    def modify_leafs! (block) : DFGExpr
        @expr = @expr.modify_leafs!(block)
        self
    end
end

end # module Isekai

module Isekai::FmtConv

private def self.make_input_fields (bws : Array(BitWidth), name : String) : Array(DFGExpr)
    storage = Storage.new(name, bws.size)
    bws.map_with_index { |bw, i| Field.new(StorageKey.new(storage, i), bw).as(DFGExpr) }
end

def self.new_to_old (
        inputs : Array(BitWidth),
        nizk_inputs : Array(BitWidth),
        outputs : Array(DFGExpr)
    ) : {Array(DFGExpr), Array(DFGExpr), Array({StorageKey, DFGExpr})}

    input_fields = make_input_fields(inputs, name: "input")
    nizk_input_fields = make_input_fields(nizk_inputs, name: "nizk_input")

    conv_leaf = ->(leaf : DFGExpr) {
        if leaf.is_a? InputBase
            case leaf.@which
            when InputBase::Kind::Input     then input_fields[leaf.@idx]
            when InputBase::Kind::NizkInput then nizk_input_fields[leaf.@idx]
            else raise "unreachable"
            end
        else
            leaf
        end
    }

    output_storage = Storage.new("output", outputs.size)
    results = outputs.map_with_index do |expr, i|
        new_expr = expr.modify_leafs!(conv_leaf)
        {StorageKey.new(output_storage, i), new_expr}
    end
    return input_fields, nizk_input_fields, results
end

end # module Isekai::FmtConv
