require "../common/dfg"
require "../common/bitwidth"
require "./board"

@[AlwaysInline]
private def truncate (x : UInt128, width : Int32) : UInt128
    x & ((1_u128 << width) - 1)
end

@[AlwaysInline]
private def common_width! (a : Int32, b : Int32) : Int32
    raise "Bit widths differ" unless a == b
    return a
end

module Isekai::AltBackend::Requests

struct JoinedRequest
    # This represents the value of 'a*x+b'. Constants are represented as '0*I+b', where 'I' is an
    # "invalid" wire.
    def initialize (@a : UInt128, @x : Wire, @b : UInt128, @width : Int32)
    end

    def self.new_for_wire (w : Wire, width : Int32)
        self.new(a: 1, x: w, b: 0, width: width)
    end

    def self.new_for_const (c : UInt128, width : Int32)
        self.new(a: 0, x: Wire.new_invalid, b: c, width: width)
    end

    def as_constant : UInt128?
        @a == 0 ? @b : nil
    end
end

alias SplitRequest = Array(JoinedRequest)

def self.bake_input (board, idx : Int32) : JoinedRequest
    wire, bitwidth = board.input(idx)
    return JoinedRequest.new_for_wire(wire, width: bitwidth.@width)
end

def self.bake_nizk_input (board, idx : Int32) : JoinedRequest
    wire, bitwidth = board.nizk_input(idx)
    return JoinedRequest.new_for_wire(wire, width: bitwidth.@width)
end

def self.bake_const (c : UInt128, width : Int32) : JoinedRequest
    return JoinedRequest.new_for_const(c, width: width)
end

private def self.joined_to_wire (board, j : JoinedRequest) : Wire
    if j.@a == 0
        return board.constant(j.@b)
    else
        ax = board.const_mul(j.@a, j.@x, j.@width)
        return board.const_add(j.@b, ax, j.@width)
    end
end

def self.joined_add_const(c : UInt128, j : JoinedRequest) : JoinedRequest
    return JoinedRequest.new(
        a: j.@a,
        x: j.@x,
        b: truncate(c + j.@b, j.@width),
        width: j.@width)
end

def self.joined_add (board, j : JoinedRequest, k : JoinedRequest) : JoinedRequest
    width = common_width! j.@width, k.@width

    if j.@x == k.@x
        return JoinedRequest.new(
            a: truncate(j.@a + k.@a, width),
            x: j.@x,
            b: truncate(j.@b + k.@b, width),
            width: width)
    end

    return joined_add_const(j.@b, k) if j.@a == 0
    return joined_add_const(k.@b, j) if k.@a == 0

    j_ax = board.const_mul(j.@a, j.@x, width)
    k_ax = board.const_mul(k.@a, k.@x, width)
    return JoinedRequest.new(
        a: 1,
        x: board.add(j_ax, k_ax, width),
        b: truncate(j.@b + k.@b, width),
        width: width)
end

def self.joined_mul_const (c : UInt128, j : JoinedRequest)
    return JoinedRequest.new(
        a: truncate(c * j.@a, j.@width),
        x: j.@x,
        b: truncate(c * j.@b, j.@width),
        width: j.@width)
end

def self.joined_mul (board, j : JoinedRequest, k : JoinedRequest) : JoinedRequest
    width = common_width! j.@width, k.@width

    return joined_mul_const(j.@b, k) if j.@a == 0
    return joined_mul_const(k.@b, j) if k.@a == 0

    j_wire = joined_to_wire(board, j)
    k_wire = joined_to_wire(board, k)
    result = board.mul(j_wire, k_wire, width)
    return JoinedRequest.new_for_wire(result, width: width)
end

def self.joined_mul_const_neg (board, c : UInt128, j : JoinedRequest) : JoinedRequest
    if j.@a == 0 && j.@b == 0
        return j
    end
    j_wire = joined_to_wire(board, j)
    return JoinedRequest.new_for_wire(
        board.const_mul_neg(c, j_wire, j.@width),
        width: j.@width)
end

def self.joined_zerop (board, j : JoinedRequest) : JoinedRequest
    if j.@a == 0
        return JoinedRequest.new_for_const(j.@b == 0 ? 0_u128 : 1_u128, width: 1)
    else
        j_wire = joined_to_wire(board, j)
        result = board.zerop(j_wire, j.@width)
        return JoinedRequest.new_for_wire(result, width: 1)
    end
end

def self.joined_zext (board, j : JoinedRequest, to new_width : Int32) : JoinedRequest
    old_width = j.@width
    return j if old_width == new_width
    raise "This is truncation, not extension" if new_width < old_width

    if j.@a == 0
        return JoinedRequest.new_for_const(j.@b, width: new_width)
    else
        j_wire = joined_to_wire(board, j)
        result = board.truncate(j_wire, to: old_width)
        return JoinedRequest.new_for_wire(result, width: new_width)
    end
end

def self.joined_to_split (board, j : JoinedRequest) : SplitRequest
    width = j.@width
    if j.@a == 0
        value = j.@b
        return SplitRequest.new(width) do |i|
            JoinedRequest.new_for_const((value >> i) & 1, width: 1)
        end
    else
        j_wire = joined_to_wire(board, j)
        max_nbits = board.max_nbits(j_wire, width)
        if max_nbits <= 1
            bits = [j_wire]
        else
            bits = board.split(j_wire, into: max_nbits)
        end
        return SplitRequest.new(width) do |i|
            if i < bits.size
                JoinedRequest.new_for_wire(bits[i], width: 1)
            else
                JoinedRequest.new_for_const(0, width: 1)
            end
        end
    end
end

def self.joined_trunc (j : JoinedRequest, to new_width : Int32) : JoinedRequest
    return JoinedRequest.new(
        a: truncate(j.@a, new_width),
        x: j.@x,
        b: truncate(j.@b, new_width),
        width: new_width)
end

private def self.joined_cmp_neq_cw (board, c : UInt128, j : JoinedRequest) : JoinedRequest
    width = j.@width
    w = board.const_mul(j.@a, j.@x, width)
    cmp_against = truncate(c - j.@b, width)
    if cmp_against != 0
        w = board.truncate(w, to: width)
        diff = board.add(w, board.constant_neg(cmp_against), width: -1)
        result = board.zerop(diff, width: -1)
    else
        result = board.zerop(w, width: width)
    end
    return JoinedRequest.new_for_wire(result, width: 1)
end

private def self.joined_cmp_neq_ww (board, j : JoinedRequest, k : JoinedRequest) : JoinedRequest
    width = j.@width

    w = board.const_mul(j.@a, j.@x, width)
    x = board.const_mul(k.@a, k.@x, width)
    add_to_w = truncate(j.@b - k.@b, width)
    w = board.const_add(add_to_w, w, width)
    w = board.truncate(w, to: width)

    minus_x = board.const_mul_neg(1, x, width: width)
    diff = board.add(w, minus_x, width: -1)
    result = board.zerop(diff, width: -1)

    return JoinedRequest.new_for_wire(result, width: 1)
end

def self.joined_cmp_neq (board, j : JoinedRequest, k : JoinedRequest) : JoinedRequest
    _ = common_width! j.@width, k.@width
    case {j.@a, k.@a}
    when {0, 0}
        return JoinedRequest.new_for_const(j.@b != k.@b ? 1_u128 : 0_u128, width: 1)
    when {0, _}
        return joined_cmp_neq_cw(board, j.@b, k)
    when {_, 0}
        return joined_cmp_neq_cw(board, k.@b, j)
    else
        return joined_cmp_neq_ww(board, j, k)
    end
end

def self.split_to_joined (board, bits : SplitRequest) : JoinedRequest
    const_summand = 0_u128
    wire_summand : Wire? = nil
    wire_summand_width = 0

    bits.each_with_index do |bit, i|
        if bit.@a == 0
            const_summand += bit.@b << i
            next
        end
        ext_x = board.truncate(joined_to_wire(board, bit), to: 1)
        bit_wire = board.const_mul(1_u128 << i, ext_x, i + 1)
        if wire_summand
            wire_summand = board.add(wire_summand, bit_wire, i + 1)
        else
            wire_summand = bit_wire
        end
        wire_summand_width = i + 1
    end

    if wire_summand
        board.assume_width!(wire_summand, wire_summand_width)
        return JoinedRequest.new(
            a: 1,
            x: wire_summand,
            b: const_summand,
            width: bits.size)
    else
        return JoinedRequest.new_for_const(const_summand, width: bits.size)
    end
end

alias Request = JoinedRequest | SplitRequest

def self.to_joined (board, r : Request) : JoinedRequest
    (r.is_a? JoinedRequest) ? r : split_to_joined(board, r)
end

def self.to_split (board, r : Request) : SplitRequest
    (r.is_a? SplitRequest) ? r : joined_to_split(board, r)
end

def self.joined_to_output! (board, j : JoinedRequest) : {Wire, Int32}
    wire = joined_to_wire(board, j)
    {wire, j.@width}
end

end
