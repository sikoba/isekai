require "../common/dfg"
require "./board"
require "./requests"

private alias Request = Isekai::AltBackend::Requests::Request
private alias JoinedRequest = Isekai::AltBackend::Requests::JoinedRequest
private alias SplitRequest = Isekai::AltBackend::Requests::SplitRequest

private def zip_map (left : SplitRequest, right : SplitRequest) : SplitRequest
    raise "Sizes differ" unless left.size == right.size
    return SplitRequest.new(left.size) { |i| yield left[i], right[i] }
end

module Isekai::AltBackend

def self.for_each_dependency (expr : DFGExpr)
    case expr
    when InputBase, Constant
        # no dependencies
    when Conditional
        yield expr.@cond
        yield expr.@valtrue
        yield expr.@valfalse
    when BinaryOp
        yield expr.@left
        yield expr.@right
    when UnaryOp
        yield expr.@expr
    else
        raise "Not implemented for #{expr.class}"
    end
end

private def self.lay_down_subtract (board, left, right, width)
    minus_one = (1_u128 << width) - 1
    minus_right = Requests.joined_mul_const(minus_one, right)
    return Requests.joined_add(board, left, minus_right)
end

private def self.lay_down_cmp_lt (board, left, right, width)
    new_width = width + 1

    ext_left = Requests.joined_zero_extend(board, left, to: new_width)
    ext_right = Requests.joined_zero_extend(board, right, to: new_width)
    ext_diff = lay_down_subtract(board, ext_left, ext_right, new_width)

    ext_diff_bits = Requests.joined_to_split(board, ext_diff)
    return ext_diff_bits.last
end

def self.lay_down (expr, on board : Board, using deps : Array(Request)) : Request
    case expr
    when InputBase
        case expr.@which
        when .input?
            return Requests.bake_input(board, expr.@idx)
        when .nizk_input?
            return Requests.bake_nizk_input(board, expr.@idx)
        else
            raise "unreachable"
        end

    when Constant
        return Requests.bake_const(expr.@value.to_u64.to_u128, expr.@bitwidth.@width)

    when Conditional
        cond = Requests.to_joined(board, deps[0])
        valtrue = Requests.to_joined(board, deps[1])
        valfalse = Requests.to_joined(board, deps[2])

        ext_cond = Requests.joined_zero_extend(board, cond, to: expr.@bitwidth.@width)
        not_cond = Requests.joined_add_const(1, cond)
        ext_not_cond = Requests.joined_zero_extend(board, not_cond, to: expr.@bitwidth.@width)

        return Requests.joined_add(
            board,
            Requests.joined_mul(board, ext_cond, valtrue),
            Requests.joined_mul(board, ext_not_cond, valfalse))

    when Add
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        return Requests.joined_add(board, left, right)

    when Subtract
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        return lay_down_subtract(board, left, right, expr.@bitwidth.@width)

    when Multiply
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        return Requests.joined_mul(board, left, right)

    when Xor
        left = Requests.to_split(board, deps[0])
        right = Requests.to_split(board, deps[1])
        return zip_map(left, right) { |a, b| Requests.joined_add(board, a, b) }

    when BitAnd
        left = Requests.to_split(board, deps[0])
        right = Requests.to_split(board, deps[1])
        return zip_map(left, right) { |a, b| Requests.joined_mul(board, a, b) }

    when BitOr
        left = Requests.to_split(board, deps[0])
        right = Requests.to_split(board, deps[1])
        return zip_map(left, right) do |a, b|
            if (a_val = a.as_constant)
                a_val != 0 ? a : b
            elsif (b_val = b.as_constant)
                b_val != 0 ? b : a
            else
                # compute as 'zerop(a+b)'
                ext_a = Requests.joined_zero_extend(board, a, to: 2)
                ext_b = Requests.joined_zero_extend(board, b, to: 2)
                ext_sum = Requests.joined_add(board, ext_a, ext_b)
                Requests.joined_zerop(board, ext_sum)
            end
        end

    when LeftShift
        left = deps[0]
        right = Requests.to_joined(board, deps[1])
        shift = right.as_constant
        raise "Not yet implemented: left shift with non-const right operand" unless shift

        if left.is_a? JoinedRequest
            width = expr.@bitwidth.@width
            factor = (shift >= width) ? 0_u128 : 1_u128 << shift
            return Requests.joined_mul_const(factor, left)
        else
            return SplitRequest.new(left.size) do |i|
                i < shift ? Requests.bake_const(0, width: 1) : left[i - shift]
            end
        end

    when RightShift
        left = Requests.to_split(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        shift = right.as_constant
        raise "Not yet implemented: unsigned right shift with non-const right operand" unless shift

        return SplitRequest.new(left.size) do |i|
            left[i + shift]? || Requests.bake_const(0, width: 1)
        end

    when SignedRightShift
        left = Requests.to_split(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        shift = right.as_constant
        raise "Not yet implemented: signed right shift with non-const right operand" unless shift

        return SplitRequest.new(left.size) do |i|
            left[i + shift]? || left.last
        end

    when CmpNEQ
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        return Requests.joined_cmp_neq(board, left, right)

    when CmpEQ
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        neq = Requests.joined_cmp_neq(board, left, right)
        return Requests.joined_add_const(1, neq)

    when CmpLT
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        return lay_down_cmp_lt(board, left, right, expr.@left.@bitwidth.@width)

    when CmpLEQ
        left = Requests.to_joined(board, deps[0])
        right = Requests.to_joined(board, deps[1])
        not_leq = lay_down_cmp_lt(board, right, left, expr.@left.@bitwidth.@width)
        return Requests.joined_add_const(1, not_leq)

    when ZeroExtend
        arg = deps[0]
        new_width = expr.@bitwidth.@width
        if arg.is_a? JoinedRequest
            return Requests.joined_zero_extend(board, arg, to: new_width)
        else
            return SplitRequest.new(new_width) do |i|
                arg[i]? || Requests.bake_const(0, width: 1)
            end
        end

    when SignExtend
        arg = Requests.to_split(board, deps[0])
        new_width = expr.@bitwidth.@width
        return SplitRequest.new(new_width) do |i|
            arg[i]? || arg.last
        end

    when Truncate
        arg = deps[0]
        new_width = expr.@bitwidth.@width
        if arg.is_a? JoinedRequest
            return Requests.joined_trunc(arg, to: new_width)
        else
            return arg.first(new_width)
        end

    else
        raise "Not implemented for #{expr.class}"
    end
end

class Backend
    @cache = {} of UInt64 => Request
    @board : Board

    def initialize (@board : Board)
    end

    private def lay_down! (output : DFGExpr)
        stack = [{output, -1}]
        results = [] of Request
        dependencies = [] of Request

        until stack.empty?
            expr, ndeps = stack.last

            if ndeps == -1
                if @cache.has_key? expr.object_id
                    stack.pop
                    results << @cache[expr.object_id]
                else
                    old_size = stack.size
                    AltBackend.for_each_dependency(expr) { |dep| stack << {dep, -1} }
                    stack[old_size - 1] = {expr, stack.size - old_size}
                end
            else
                stack.pop
                ndeps.times { dependencies << results.pop }

                result = AltBackend.lay_down(expr, on: @board, using: dependencies)
                dependencies.clear

                results << result
                @cache[expr.object_id] = result
            end
        end

        j = Requests.to_joined(@board, results[0])
        Requests.joined_add_output!(@board, j)
    end

    def lay_down_outputs! (outputs : Array(DFGExpr)) : Nil
        outputs.each { |expr| lay_down!(expr) }
        @board.done!
    end
end

end
