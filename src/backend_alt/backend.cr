require "../common/dfg"
require "../common/bitwidth"
require "./board"
require "./trace"

private alias ConstTrace = Isekai::AltBackend::ConstTrace
private alias WireTrace = Isekai::AltBackend::WireTrace
private alias JoinedTrace = Isekai::AltBackend::JoinedTrace
private alias SplitTrace = Isekai::AltBackend::SplitTrace
private alias Trace = Isekai::AltBackend::Trace

private def zip_map (left : SplitTrace, right : SplitTrace) : SplitTrace
    raise "Sizes differ" unless left.size == right.size
    return SplitTrace.new(left.size) { |i| yield left[i], right[i] }
end

private def lay_down_bor_cw (board, c, j : JoinedTrace) : JoinedTrace
    return (c == 0) ? j : ConstTrace.new_bool(1)
end

private def lay_down_bor_ww (board, j : JoinedTrace, k : JoinedTrace) : JoinedTrace
    # There are at least three ways to compute j|k for single bits:
    # 1. j + k + j*k, everything modulo 2;
    # 2. j + k - j*k, no modulo;
    # 3. zerop(j + k), no modulo.
    # We choose the third.

    ext_j = Isekai::AltBackend.joined_zext(board, j, 2)
    ext_k = Isekai::AltBackend.joined_zext(board, k, 2)
    ext_sum = Isekai::AltBackend.joined_add(board, ext_j, ext_k)
    return Isekai::AltBackend.joined_zerop(board, ext_sum)
end

private def lay_down_shr (left_bits, right)
    raise "Not yet implemented" unless right.is_a? ConstTrace
    shift = right.value
    return SplitTrace.new(left_bits.size) { |i| left_bits[i + shift]? || yield }
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
        return WireTrace.new(wire, bitwidth.@width)
    end
end

class Constant
    def append_deps (to array : Array(DFGExpr)) : Nil
    end

    def lay_down (board, deps)
        return ConstTrace.new(@value.to_u64, @bitwidth.@width)
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

        not_cond = Isekai.dfg_make_binary(Add, cond, Constant.new(1, cond.@bitwidth))

        cond_is_true, cond_is_false = cond, not_cond
        unless @bitwidth == @cond.@bitwidth
            cond_is_true  = Isekai.dfg_make_bitwidth_cast(ZeroExtend, cond_is_true,  @bitwidth)
            cond_is_false = Isekai.dfg_make_bitwidth_cast(ZeroExtend, cond_is_false, @bitwidth)
        end

        array << Isekai.dfg_make_binary(
            Add,
            Isekai.dfg_make_binary(Multiply, cond_is_true, valtrue),
            Isekai.dfg_make_binary(Multiply, cond_is_false, valfalse))
    end

    def lay_down (board, deps)
        return deps[0]
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

class BitOr
    def lay_down (board, deps)
        left = AltBackend.to_split(board, deps[0])
        right = AltBackend.to_split(board, deps[1])
        return zip_map(left, right) do |a, b|
            case {a, b}
            when {ConstTrace, _}
                lay_down_bor_cw(board, a.value, b)
            when {_, ConstTrace}
                lay_down_bor_cw(board, b.value, a)
            else
                lay_down_bor_ww(board, a, b)
            end
        end
    end
end

class LeftShift
    def lay_down (board, deps)
        right = AltBackend.to_joined(board, deps[1])
        raise "Not yet implemented" unless right.is_a? ConstTrace
        shift = right.value

        left = deps[0]
        if left.is_a? JoinedTrace
            factor = @bitwidth.truncate(1_u64 << shift)
            return AltBackend.joined_mul_const(board, factor, left)
        else
            return SplitTrace.new(left.size) do |i|
                i < shift ? ConstTrace.new_bool(0) : left[i - shift]
            end
        end
    end
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
        array << Isekai.dfg_make_binary(CmpNEQ, @left, @right)
    end

    def lay_down (board, deps)
        neq = AltBackend.to_joined(board, deps[0])
        return AltBackend.joined_add_const(board, 1_u64, neq)
    end
end

class CmpLT
    def lay_down (board, deps)
        left = AltBackend.to_joined(board, deps[0])
        right = AltBackend.to_joined(board, deps[1])

        if left.is_a? ConstTrace
            if left.value == @bitwidth.mask
                # Rewrite 'MAX < x' into '0'.
                return ConstTrace.new_bool(0_u64)
            elsif left.value == 0
                # Rewrite '0 < x' into 'x != 0'.
                return AltBackend.joined_zerop(board, right)
            end
        end
        if right.is_a? ConstTrace
            if right.value == 0
                # Rewrite 'x < 0' into '0'.
                return ConstTrace.new_bool(0_u64)
            elsif right.value == @bitwidth.mask
                # Rewrite 'x < MAX' into 'x + 1 != 0'.
                right_plus_one = AltBackend.joined_add_const(board, 1_u64, right)
                return AltBackend.joined_zerop(board, right_plus_one)
            end
        end

        new_width = @left.@bitwidth.@width + 1
        ext_left = AltBackend.joined_zext(board, left, new_width)
        ext_right = AltBackend.joined_zext(board, right, new_width)

        ext_minus_one = (1_u128 << new_width) - 1

        case {ext_left, ext_right}
        when {ConstTrace, ConstTrace}
            return ConstTrace.new_bool(ext_left.value < ext_right.value ? 1_u64 : 0_u64)
        when {WireTrace, ConstTrace}
            right_summand = (ext_minus_one * ext_right.value) & ext_minus_one
            diff = AltBackend.joined_add_const(board, right_summand, ext_left)
        else
            right_summand = AltBackend.joined_mul_const(board, ext_minus_one, ext_right)
            diff = AltBackend.joined_add(board, ext_left, right_summand)
        end

        diff_bits = AltBackend.to_split(board, diff)
        return diff_bits.last
    end
end

class CmpLEQ
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << Isekai.dfg_make_binary(CmpLT, @right, @left)
    end

    def lay_down (board, deps)
        not_leq = AltBackend.to_joined(board, deps[0])
        return AltBackend.joined_add_const(board, 1_u64, not_leq)
    end
end

class UnaryOp
    def append_deps (to array : Array(DFGExpr)) : Nil
        array << @expr
    end
end

class ZeroExtend
    def lay_down (board, deps)
        trace = deps[0]
        if trace.is_a? JoinedTrace
            return AltBackend.joined_zext(board, trace, @bitwidth.@width)
        else
            return SplitTrace.new(@bitwidth.@width) { |i| trace[i]? || ConstTrace.new_bool(0) }
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
    joined_add_output!(board, joined)
end

end # module Isekai::AltBackend
