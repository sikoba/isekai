require "../common/dfg"
require "../common/bitwidth"
require "./board"
require "./trace"

private alias SplitTrace = AltBackend::SplitTrace
private alias WireTrace = AltBackend::WireTrace
private alias ConstTrace = AltBackend::ConstTrace
private alias JoinedTrace = AltBackend::JoinedTrace
private alias Trace = AltBackend::Trace

private def zip_map (left : SplitTrace, right : SplitTrace) : SplitTrace
    raise "Sizes differ" unless left.size == right.size
    return SplitTrace.new(left.size) { |i| yield left[i], right[i] }
end

module Isekai

abstract class DFGExpr
    def append_deps (to array : Array(DFGExpr)) : Nil
        raise "Not implemented"
    end

    def lay_down (board, deps) : Trace
        raise "Not implemented"
    end
end

class InputBase
    def append_deps (to array : Array(DFGExpr)) : Nil
    end

    def lay_down (board, deps)
        case @which
        when Kind::Input
            wire, bitwidth = board.input @idx
        when Kind::NizkInput
            wire, bitwidth = board.nizk_input @idx
        else
            raise "unreachable"
        end
        return WireTrace.new(wire, bitwidth)
    end
end

class Constant
    def append_deps (to array : Array(DFGExpr)) : Nil
    end

    def lay_down (board, deps)
        return ConstTrace.new(@value.to_u64, @bitwidth)
    end
end

class Conditional
    def append_deps (to array : Array(DFGExpr)) : Nil
        cond, valtrue, valfalse = @cond, @valtrue, @valfalse

        # An example of pre-lay_down pattern-matching: rewrite '(X == Y) ? Z : W' to
        # '(X != Y) ? W : Z'.
        if cond.is_a? CmpEQ
            cond = Isekai.dfg_make_binary(CmpNEQ, cond.@left, cond.@right)
            valtrue, valfalse = valfalse, valtrue
        end

        array << cond
        array << valtrue
        array << valfalse
    end

    def lay_down (board, deps)
        cond = AltBackend.to_joined(board, deps[0])
        valtrue = AltBackend.to_joined(board, deps[1])
        valfalse = AltBackend.to_joined(board, deps[2])

        not_cond = AltBackend.joined_add(board, ConstTrace.new_bool(1), cond)

        cond_is_true, cond_is_false = cond, not_cond
        unless @cond.@bitwidth == @bitwidth
            cond_is_true = AltBackend.joined_zext(board, cond_is_true, @bitwidth)
            cond_is_false = AltBackend.joined_zext(board, cond_is_false, @bitwidth)
        end

        true_term = AltBackend.joined_mul(board, cond_is_true, valtrue)
        false_term = AltBackend.joined_mul(board, cond_is_false, valfalse)
        return AltBackend.joined_add(board, true_term, false_term)
    end
end

class BinaryOp
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << @left
        array << @right
    end
end

class Add
    def lay_down (board, deps)
        left = AltBackend.to_joined(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])
        return AltBackend.joined_add(board, left, right)
    end
end

class Multiply
    def lay_down (board, deps)
        left = AltBackend.to_joined(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])
        return AltBackend.joined_mul(board, left, right)
    end
end

class Subtract
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << @left
        minus_one = Constant.new(@bitwidth.truncate(-1.to_u64).to_i64, bitwidth: @bitwidth)
        array << Isekai.dfg_make_binary(Multiply, @right, minus_one)
    end

    def lay_down (board, deps)
        left = AltBackend.to_joined(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])
        return AltBackend.joined_add(board, left, right)
    end
end

class Xor
    def lay_down (board, deps)
        left = AltBackend.to_split(board, deps[0])
        right = AltBackend.to_split(board, deps[1])
        return zip_map(left, right) { |a, b| AltBackend.joined_add(board, a, b) }
    end
end

class BitAnd
    def lay_down (board, deps)
        left = AltBackend.to_split(board, deps[0])
        right = AltBackend.to_split(board, deps[1])
        return zip_map(left, right) { |a, b| AltBackend.joined_mul(board, a, b) }
    end
end

private def lay_down_bor_cw (board, c : UInt64, w)
    return (c == 0) ? w : ConstTrace.new_bool(1)
end

private def lay_down_bor_ww (board, w, x)
    # TODO: replace this with 'w+x-w*x' without modulo
    prod = AltBackend.joined_mul(board, w, x)
    return AltBackend.joined_add(board, AltBackend.joined_add(board, w, x), prod)
end

class BitOr
    def lay_down (board, deps)
        left = AltBackend.to_split(board, deps[0])
        right = AltBackend.to_split(board, deps[1])
        return zip_map(left, right) do |a, b|
            if a.is_a? ConstTrace
                lay_down_bor_cw(board, a.value, b)
            elsif b.is_a? ConstTrace
                lay_down_bor_cw(board, b.value, a)
            else
                lay_down_bor_ww(board, a, b)
            end
        end
    end
end

class LeftShift
    def lay_down (board, deps)
        left = AltBackend.to_joined(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])
        raise "Not yet implemented" unless right.is_a? ConstTrace

        shift = right.value
        factor = ConstTrace.new(@bitwidth.truncate(1_u64 << shift), @bitwidth)
        return AltBackend.joined_mul(board, left, factor)
    end
end

private def lay_down_shr (left_bits, right)
    raise "Not yet implemented" unless right.is_a? ConstTrace
    shift = right.value
    return SplitTrace.new(left_bits.size) { |i| left_bits[i + shift]? || yield }
end

class RightShift
    def lay_down (board, deps)
        left_bits = AltBackend.to_split(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])
        lay_down_shr(left_bits, right) { ConstTrace.new_bool(0) }
    end
end

class SignedRightShift
    def lay_down (board, deps)
        left_bits = AltBackend.to_split(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])
        lay_down_shr(left_bits, right) { left_bits.last }
    end
end

# Comparisons of unsigned integers: perform subtraction (a - b) and look at the flags of the result.
# C is the 'carry' flag, Z is the 'zero' flag.
# ---
# a >  b: C=1 and Z=0
# a >= b: C=1
# a =  b: Z=1
# a <  b: C=0
# a <= b: C=0 or Z=1

class CmpNEQ
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << Isekai.dfg_make_binary(Subtract, @left, @right)
    end

    def lay_down (board, deps)
        diff = AltBackend.to_joined(board, deps[0])
        return AltBackend.joined_zerop(board, diff)
    end
end

class CmpEQ
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << Isekai.dfg_make_binary(Subtract, @left, @right)
    end

    def lay_down (board, deps)
        diff = AltBackend.to_joined(board, deps[0])
        neq = AltBackend.joined_zerop(board, diff)
        return AltBackend.joined_add(board, ConstTrace.new_bool(1), neq)
    end
end

#class CmpLT
#    # This implementation seems to be wrong.
#
#    def append_deps (to array : Array(DFGExpr)) : Nil
#        array << Isekai.dfg_make_binary(Subtract, @left, @right)
#    end
#
#    def lay_down (board, deps)
#        bits = as_split(board, deps[0], into: @bitwidth.@width)
#        return bits.last
#    end
#end
#
#class CmpLEQ
#    # This implementation seems to be wrong.
#
#    def append_deps (to array : Array(DFGExpr)) : Nil
#        right_plus_one = Isekai.dfg_make_binary(
#            Add,
#            @right,
#            Constant.new(1, bitwidth: @bitwidth))
#        array << Isekai.dfg_make_binary(Subtract, @left, right_plus_one)
#    end
#
#    def lay_down (board, deps)
#        bits = as_split(board, deps[0], into: @bitwidth.@width)
#        return bits.last
#    end
#end

class UnaryOp
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << @expr
    end
end

class ZeroExtend
    def lay_down (board, deps)
        trace = deps[0]
        if trace.is_a? JoinedTrace
            return AltBackend.joined_zext(board, trace, @bitwidth)
        else
            return SplitTrace.new(@bitwidth.@width) do |i|
                trace[i]? || ConstTrace.new_bool(0)
            end
        end
    end
end

class SignExtend
    def lay_down (board, deps)
        bits = AltBackend.to_split(board, deps[0])
        return SplitTrace.new(@bitwidth.@width) { |i| bits[i]? || bits.last }
    end
end

class Truncate
    def lay_down (board, deps)
        bits = AltBackend.to_split(board, deps[0])
        return bits.first(@bitwidth.@width)
    end
end

end # module Isekai

module Isekai::AltBackend

def self.lay_down_output! (board : Board, output : DFGExpr) : Nil
    stack = [output]
    ndeps_stack = [-1]

    results = [] of Trace
    deps_buffer = [] of Trace

    cache = {} of UInt64 => Trace

    until stack.empty?
        i = stack.size - 1
        expr, ndeps = stack[i], ndeps_stack[i]
        if ndeps < 0
            if cache.has_key? expr.object_id
                stack.pop
                ndeps_stack.pop
                results << cache[expr.object_id]
            else
                expr.append_deps(to: stack)
                ndeps = stack.size - (i + 1)
                ndeps_stack[i] = ndeps
                ndeps.times { ndeps_stack << -1 }
            end
        else
            stack.pop
            ndeps_stack.pop

            ndeps.times { deps_buffer << results.pop }
            result = expr.lay_down(board, deps_buffer)
            deps_buffer.clear

            cache[expr.object_id] = result
            results << result
        end
    end

    joined = AltBackend.to_joined(board, results[0])
    wire = AltBackend.joined_to_wire!(board, joined)
    board.add_output!(wire)
end

end # module Isekai::AltBackend
