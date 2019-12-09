require "./common/dfg"

module Isekai::FmtConv

private def self.make_input_fields (bws : Array(BitWidth), name : String) : Array(DFGExpr)
    storage = Storage.new(name, bws.size)
    bws.map_with_index { |bw, i| Field.new(StorageKey.new(storage, i), bw).as(DFGExpr) }
end

private def self.convert_leafs! (expr : DFGExpr, &block : DFGExpr -> DFGExpr) : DFGExpr
    case expr
    when NagaiVerbatim, Constant, InputBase, Field
        block.call(expr)
    when Conditional
        expr.set_operands!(
            cond: convert_leafs!(expr.@cond, &block),
            valtrue: convert_leafs!(expr.@valtrue, &block),
            valfalse: convert_leafs!(expr.@valfalse, &block))
        expr
    when BinaryOp
        expr.set_operands!(
            left: convert_leafs!(expr.@left, &block),
            right: convert_leafs!(expr.@right, &block))
        expr
    when UnaryOp
        expr.set_operand!(convert_leafs!(expr.@expr, &block))
        expr
    else
        raise "Not implemented for #{expr.class}"
    end
end

def self.new_to_old (
        inputs : Array(BitWidth),
        nizk_inputs : Array(BitWidth),
        outputs : Array(DFGExpr)
    ) : {Array(DFGExpr), Array(DFGExpr), Array({StorageKey, DFGExpr})}

    input_fields = make_input_fields(inputs, name: "input")
    nizk_input_fields = make_input_fields(nizk_inputs, name: "nizk_input")

    output_storage = Storage.new("output", outputs.size)
    results = outputs.map_with_index do |expr, i|
        new_expr = convert_leafs!(expr) do |leaf|
            if leaf.is_a? InputBase
                case leaf.@which
                when InputBase::Kind::Input     then input_fields[leaf.@idx]
                when InputBase::Kind::NizkInput then nizk_input_fields[leaf.@idx]
                else raise "unreachable"
                end
            else
                leaf
            end
        end
        {StorageKey.new(output_storage, i), new_expr}
    end
    return input_fields, nizk_input_fields, results
end

end
