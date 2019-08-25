require "./req_factory"
require "../../common/dfg"

private def zip_map (left, right)
    raise "Sizes differ" unless left.size == right.size
    return typeof(left).new(left.size) { |i| yield left[i], right[i] }
end

module Isekai::AltBackend::Boolean

struct Backend
    private alias Bit = RequestFactory::Bit
    private alias Request = Array(Bit)

    @req_factory : RequestFactory
    @cache = {} of UInt64 => Request

    def initialize (@req_factory)
    end

    private def const_to_request (c, width) : Request
        Request.new(width) { |i| Bit.new_for_const(0 != ((c >> i) & 1)) }
    end

    def visit_dependencies (expr : DFGExpr)
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

    private def request_as_constant (req : Request) : UInt64?
        result = 0_u64
        req.each_with_index do |bit, pos|
            value = bit.as_constant
            return nil unless value
            result |= value << pos
        end
        result
    end

    private def lay_down_cmp_neq (left : Request, right : Request) : Bit
        result = Bit.new_for_const(false)
        left.zip(right) do |a, b|
            result = @req_factory.bit_or(result, @req_factory.bit_xor(a, b))
        end
        result
    end

    private def lay_down_subtract_borrow (left : Request, right : Request) : Bit
        borrow = Bit.new_for_const(false)
        left.zip(right) do |a, b|
            # TODO: this can be further optimized if either of 'a', 'b', 'borrow' are constant.
            b_xor_c = @req_factory.bit_xor(b, borrow)
            summand_1 = @req_factory.bit_and(a.negation, b_xor_c)
            summand_2 = @req_factory.bit_and(b, borrow)
            borrow = @req_factory.bit_xor(summand_1, summand_2)
        end
        borrow
    end

    def has_cached? (expr : DFGExpr)
        @cache.has_key?(expr.object_id)
    end

    @[AlwaysInline]
    private def get_cached (expr : DFGExpr) : Request
        @cache[expr.object_id]
    end

    private struct ProofOfCache
    end

    @[AlwaysInline]
    private def cache! (expr : DFGExpr, request : Request) : ProofOfCache
        @cache[expr.object_id] = request
        return ProofOfCache.new
    end

    def lay_down_and_cache (expr : DFGExpr) : ProofOfCache
        case expr
        when InputBase
            case expr.@which
            when .input?
                return cache! expr, @req_factory.input_bits(expr.@idx)
            when .nizk_input?
                return cache! expr, @req_factory.nizk_input_bits(expr.@idx)
            else
                raise "unreachable"
            end

        when Constant
            return cache! expr, const_to_request(expr.@value, expr.@bitwidth.@width)

        when Conditional
            cond_bit = get_cached(expr.@cond)[0]
            valtrue = get_cached(expr.@valtrue)
            valfalse = get_cached(expr.@valfalse)

            if (val = cond_bit.as_constant)
                return cache!(expr, (val != 0) ? valtrue : valfalse)
            end

            if cond_bit.negated?
                valtrue, valfalse = valfalse, valtrue
                cond_bit = cond_bit.negation
            end
            return cache!(expr, zip_map(valtrue, valfalse) do |a, b|
                # TODO: this can be further optimized if 'a' and/or 'b' are constant.
                sum = @req_factory.bit_xor(a, b)
                c_mul_sum = @req_factory.bit_and(cond_bit, sum)
                @req_factory.bit_xor(b, c_mul_sum)
            end)

        when Xor
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            return cache!(expr, zip_map(left, right) { |a, b| @req_factory.bit_xor(a, b) })

        when BitAnd
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            return cache!(expr, zip_map(left, right) { |a, b| @req_factory.bit_and(a, b) })

        when BitOr
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            return cache!(expr, zip_map(left, right) { |a, b| @req_factory.bit_or(a, b) })

        when LeftShift
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            shift = request_as_constant right
            raise "Not implemented: left shift with non-const right operand" unless shift

            return cache!(expr, Request.new(left.size) do |i|
                i < shift ? Bit.new_for_const(false) : left[i - shift]
            end)

        when RightShift
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            shift = request_as_constant right
            raise "Not implemented: unsigned right shift with non-const right operand" unless shift

            return cache!(expr, Request.new(left.size) do |i|
                left[i + shift]? || Bit.new_for_const(false)
            end)

        when SignedRightShift
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            shift = request_as_constant right
            raise "Not implemented: signed right shift with non-const right operand" unless shift

            return cache!(expr, Request.new(left.size) do |i|
                left[i + shift]? || left.last
            end)

        when CmpNEQ
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            bit = lay_down_cmp_neq(left, right)
            return cache! expr, [bit]

        when CmpEQ
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            bit = lay_down_cmp_neq(left, right).negation
            return cache! expr, [bit]

        when CmpLT
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            bit = lay_down_subtract_borrow(left, right)
            return cache! expr, [bit]

        when CmpLEQ
            left = get_cached(expr.@left)
            right = get_cached(expr.@right)
            bit = lay_down_subtract_borrow(right, left).negation
            return cache! expr, [bit]

        when ZeroExtend
            arg = get_cached(expr.@expr)
            new_width = expr.@bitwidth.@width
            return cache!(expr, Request.new(new_width) do |i|
                arg[i]? || Bit.new_for_const(false)
            end)

        when SignExtend
            arg = get_cached(expr.@expr)
            new_width = expr.@bitwidth.@width
            return cache!(expr, Request.new(new_width) do |i|
                arg[i]? || arg.last
            end)

        when Truncate
            arg = get_cached(expr.@expr)
            new_width = expr.@bitwidth.@width
            return cache! expr, arg.first(new_width)

        else
            raise "Not implemented for #{expr.class}"
        end
    end

    def add_output_cached! (expr : DFGExpr) : Nil
        get_cached(expr).each do |bit|
            @req_factory.bit_add_output!(bit)
        end
    end
end

end
