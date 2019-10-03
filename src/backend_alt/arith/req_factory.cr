require "./board"
require "./dynamic_range"
require "./bit_manip"

@[AlwaysInline]
private def truncate (x : UInt128, width : Int32) : UInt128
    x & ((1_u128 << width) - 1)
end

@[AlwaysInline]
private def common_width! (a : Int32, b : Int32) : Int32
    raise "Bit widths differ" unless a == b
    return a
end

module Isekai::AltBackend::Arith

struct RequestFactory
    struct JoinedRequest
        # This represents the value of 'a*x+b'. Constants are represented as '0*I+b', where 'I' is an
        # "invalid" wire.
        def initialize (@a : UInt128, @x : Wire, @b : UInt128, @width : Int32)
        end

        getter width

        @[AlwaysInline]
        def self.new_for_wire (w : Wire, width : Int32)
            self.new(a: 1, x: w, b: 0, width: width)
        end

        @[AlwaysInline]
        def self.new_for_const (c : UInt128, width : Int32)
            self.new(a: 0, x: Wire.new_invalid, b: c, width: width)
        end

        @[AlwaysInline]
        def constant?
            @a == 0
        end

        @[AlwaysInline]
        def as_constant : UInt128?
            @a == 0 ? @b : nil
        end
    end

    alias SplitRequest = Array(JoinedRequest)

    @board : Board
    @sloppy : Bool

    def initialize (@board, @sloppy)
    end

    def bake_input (idx : Int32) : JoinedRequest
        wire, bitwidth = @board.input(idx)
        return JoinedRequest.new_for_wire(wire, width: bitwidth.@width)
    end

    def bake_nizk_input (idx : Int32) : JoinedRequest
        wire, bitwidth = @board.nizk_input(idx)
        return JoinedRequest.new_for_wire(wire, width: bitwidth.@width)
    end

    def bake_const (c : UInt128, width : Int32) : JoinedRequest
        return JoinedRequest.new_for_const(c, width: width)
    end

    def joined_add_output! (j : JoinedRequest) : Nil
        wire = joined_to_wire! j
        @board.add_output!(
            wire,
            policy: @sloppy ?
                TruncatePolicy.new_no_truncate :
                TruncatePolicy.new_to_width(j.@width))
    end

    private def bake_overflow_policy (width : Int32) : OverflowPolicy
        if @sloppy && width != 1
            OverflowPolicy.new_cannot_overflow(width)
        else
            OverflowPolicy.new_wrap_around(width)
        end
    end

    private def joined_to_wire! (j : JoinedRequest) : Wire
        if j.constant?
            return @board.constant(j.@b)
        else
            ax = @board.const_mul(j.@a, j.@x, policy: bake_overflow_policy(j.@width))
            return @board.const_add(j.@b, ax, policy: bake_overflow_policy(j.@width))
        end
    end

    def joined_add_const (c : UInt128, j : JoinedRequest) : JoinedRequest
        return JoinedRequest.new(
            a: j.@a,
            x: j.@x,
            b: truncate(c &+ j.@b, j.@width),
            width: j.@width)
    end

    def joined_add (j : JoinedRequest, k : JoinedRequest) : JoinedRequest
        width = common_width! j.@width, k.@width

        if j.@x == k.@x
            return JoinedRequest.new(
                a: truncate(j.@a &+ k.@a, width),
                x: j.@x,
                b: truncate(j.@b &+ k.@b, width),
                width: width)
        end

        return joined_add_const(j.@b, k) if j.constant?
        return joined_add_const(k.@b, j) if k.constant?

        j_ax = @board.const_mul(j.@a, j.@x, policy: bake_overflow_policy(width))
        k_ax = @board.const_mul(k.@a, k.@x, policy: bake_overflow_policy(width))
        return JoinedRequest.new(
            a: 1,
            x: @board.add(j_ax, k_ax, policy: bake_overflow_policy(width)),
            b: truncate(j.@b &+ k.@b, width),
            width: width)
    end

    def joined_mul_const (c : UInt128, j : JoinedRequest)
        return JoinedRequest.new(
            a: truncate(c &* j.@a, j.@width),
            x: j.@x,
            b: truncate(c &* j.@b, j.@width),
            width: j.@width)
    end

    def joined_mul (j : JoinedRequest, k : JoinedRequest) : JoinedRequest
        width = common_width! j.@width, k.@width

        return joined_mul_const(j.@b, k) if j.constant?
        return joined_mul_const(k.@b, j) if k.constant?

        if width == 1 && j.@x == k.@x
            # Modulo 2, x^2 = x, so:
            # (x + A)(x + B) = x^2 + Ax + Bx + AB = (A+B+1)x + AB
            return JoinedRequest.new(
                a: j.@b ^ k.@b ^ 1,
                x: j.@x,
                b: j.@b & k.@b,
                width: 1)
        end

        j_wire = joined_to_wire! j
        k_wire = joined_to_wire! k
        result = @board.mul(j_wire, k_wire, policy: bake_overflow_policy(width))
        return JoinedRequest.new_for_wire(result, width: width)
    end

    def joined_sub (
            j : JoinedRequest,
            k : JoinedRequest,
            force_correct : Bool = false) : JoinedRequest | SplitRequest

        width = common_width! j.@width, k.@width
        minus_one = (1_u128 << width) - 1

        if @sloppy && width != 1
            unless force_correct
                j_wire = @board.truncate(joined_to_wire!(j), to: width)
                k_wire = @board.truncate(joined_to_wire!(k), to: width)
                minus_k_wire = @board.const_mul_neg(
                    1,
                    k_wire,
                    policy: TruncatePolicy.new_no_truncate)
                result = @board.add(
                    j_wire,
                    minus_k_wire,
                    policy: OverflowPolicy.new_set_undef_range)
                @board.assume_width!(result, @board.max_nbits(j_wire).not_nil!)
                return JoinedRequest.new_for_wire(result, width: width)
            end

            j_wire = joined_to_wire! j
            k_wire = joined_to_wire! k
            minus_k_wire = @board.const_mul(
                minus_one,
                k_wire,
                policy: OverflowPolicy.new_wrap_around(width))
            result_wire = @board.add(
                j_wire,
                minus_k_wire,
                policy: OverflowPolicy.new_wrap_around(width))

            bits = @board.split(result_wire)
            return SplitRequest.new(width) do |i|
                if i < bits.size
                    JoinedRequest.new_for_wire(bits[i], width: 1)
                else
                    JoinedRequest.new_for_const(0, width: 1)
                end
            end
        end

        return joined_add(j, joined_mul_const(minus_one, k))
    end

    private def cond_wcc (c : Wire, t : UInt128, f : UInt128, width : Int32) : JoinedRequest
        diff = t.to_i128 - f.to_i128
        return JoinedRequest.new_for_const(f, width: width) if diff == 0

        c = @board.truncate(c, to: 1)
        if diff > 0
            left_summand = @board.const_mul(
                diff.to_u128,
                c,
                policy: OverflowPolicy.new_set_undef_range)
        else
            left_summand = @board.const_mul_neg(
                (-diff).to_u128,
                c,
                policy: TruncatePolicy.new_no_truncate)
        end

        result = @board.const_add(f, left_summand, policy: OverflowPolicy.new_set_undef_range)
        @board.assume_width!(result, Math.max(BitManip.nbits(t), BitManip.nbits(f)))
        return JoinedRequest.new_for_wire(result, width: width)
    end

    def joined_cond (c : JoinedRequest, t : JoinedRequest, f : JoinedRequest) : JoinedRequest
        width = common_width! t.@width, f.@width
        if c.constant?
            return (c.@b != 0) ? t : f
        end
        if c.@b != 0
            t, f = f, t
            c = JoinedRequest.new_for_wire(c.@x, width: 1)
        end

        if f.constant? && t.constant?
            return cond_wcc(c.@x, t.@b, f.@b, width: width)
        end

        if t.@x == f.@x && t.@a == f.@a
            return joined_add(
                JoinedRequest.new(a: t.@a, x: t.@x, b: 0, width: width),
                cond_wcc(c.@x, t.@b, f.@b, width: width))
        end

        t_wire = joined_to_wire! t
        f_wire = joined_to_wire! f

        t_max_nbits = @board.max_nbits(t_wire).not_nil!
        f_max_nbits = @board.max_nbits(f_wire).not_nil!

        minus_f_wire = @board.const_mul_neg(
            1,
            f_wire,
            policy: TruncatePolicy.new_no_truncate)
        t_minus_f_wire = @board.add(
            t_wire,
            minus_f_wire,
            policy: OverflowPolicy.new_set_undef_range)
        left_summand = @board.mul(
            @board.truncate(c.@x, to: 1),
            t_minus_f_wire,
            policy: OverflowPolicy.new_set_undef_range)
        result = @board.add(
            left_summand,
            f_wire,
            policy: OverflowPolicy.new_set_undef_range)
        @board.assume_width!(result, Math.max(t_max_nbits, f_max_nbits))
        return JoinedRequest.new_for_wire(result, width: width)
    end

    def joined_or_1bit (j : JoinedRequest, k : JoinedRequest) : JoinedRequest
        if j.constant?
            return (j.@b != 0) ? j : k
        end
        if k.constant?
            return (k.@b != 0) ? k : j
        end
        j_wire = @board.truncate(joined_to_wire!(j), to: 1)
        k_wire = @board.truncate(joined_to_wire!(k), to: 1)
        jk = @board.mul(j_wire, k_wire, policy: OverflowPolicy.new_set_undef_range)
        minus_jk = @board.const_mul_neg(1, jk, policy: TruncatePolicy.new_no_truncate)
        k_minus_jk = @board.add(k_wire, minus_jk, policy: OverflowPolicy.new_set_undef_range)
        result = @board.add(j_wire, k_minus_jk, policy: OverflowPolicy.new_set_undef_range)
        @board.assume_width!(result, 1)
        return JoinedRequest.new_for_wire(result, width: 1)
    end

    def joined_zerop (j : JoinedRequest) : JoinedRequest
        if j.constant?
            return JoinedRequest.new_for_const(j.@b == 0 ? 0_u128 : 1_u128, width: 1)
        else
            j_wire = joined_to_wire! j
            result = @board.zerop(j_wire, j.@width)
            return JoinedRequest.new_for_wire(result, width: 1)
        end
    end

    def joined_zero_extend (j : JoinedRequest, to new_width : Int32) : JoinedRequest | SplitRequest
        old_width = j.@width
        return j if old_width == new_width
        raise "This is truncation, not extension" if new_width < old_width

        if j.constant?
            return JoinedRequest.new_for_const(j.@b, width: new_width)
        else
            j_wire = joined_to_wire! j
            if @board.max_nbits(j_wire).not_nil! <= old_width
                return JoinedRequest.new_for_wire(j_wire, new_width)
            end
            bits = @board.split(j_wire)
            return SplitRequest.new(new_width) do |i|
                if i < old_width
                    JoinedRequest.new_for_wire(bits[i], width: 1)
                else
                    JoinedRequest.new_for_const(0, width: 1)
                end
            end
        end
    end

    def joined_to_split (j : JoinedRequest) : SplitRequest
        width = j.@width
        if j.constant?
            value = j.@b
            return SplitRequest.new(width) do |i|
                JoinedRequest.new_for_const((value >> i) & 1, width: 1)
            end
        else
            j_wire = joined_to_wire! j
            bits = @board.split(j_wire)
            return SplitRequest.new(width) do |i|
                if i < bits.size
                    JoinedRequest.new_for_wire(bits[i], width: 1)
                else
                    JoinedRequest.new_for_const(0, width: 1)
                end
            end
        end
    end

    def joined_trunc (j : JoinedRequest, to new_width : Int32) : JoinedRequest
        return JoinedRequest.new(
            a: truncate(j.@a, new_width),
            x: j.@x,
            b: truncate(j.@b, new_width),
            width: new_width)
    end

    def joined_cmp_neq (j : JoinedRequest, k : JoinedRequest) : JoinedRequest
        width = common_width! j.@width, k.@width
        return joined_add(j, k) if width == 1
        if j.constant? && k.constant?
            return JoinedRequest.new_for_const(j.@b != k.@b ? 1_u128 : 0_u128, width: 1)
        end

        j_wire = @board.truncate(joined_to_wire!(j), to: width)
        k_wire = @board.truncate(joined_to_wire!(k), to: width)
        minus_k_wire = @board.const_mul_neg(1, k_wire, policy: TruncatePolicy.new_no_truncate)
        diff = @board.add(j_wire, minus_k_wire, policy: OverflowPolicy.new_set_undef_range)
        result = @board.zerop(diff, policy: TruncatePolicy.new_no_truncate)
        return JoinedRequest.new_for_wire(result, width: 1)
    end

    def split_to_joined (bits : SplitRequest) : JoinedRequest
        const_summand = 0_u128
        wire_summand : Wire? = nil

        bits.each_with_index do |bit, i|
            if bit.constant?
                const_summand |= bit.@b << i
                next
            end

            ext_x = @board.truncate(joined_to_wire!(bit), to: 1)
            bit_wire = @board.const_mul(
                1_u128 << i,
                ext_x,
                policy: OverflowPolicy.new_cannot_overflow(i + 1))

            if wire_summand
                wire_summand = @board.add(
                    wire_summand,
                    bit_wire,
                    policy: OverflowPolicy.new_cannot_overflow(i + 1))
            else
                wire_summand = bit_wire
            end
        end

        if wire_summand
            return JoinedRequest.new(
                a: 1,
                x: wire_summand,
                b: const_summand,
                width: bits.size)
        else
            return JoinedRequest.new_for_const(const_summand, width: bits.size)
        end
    end
end

end
