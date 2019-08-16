require "../common/dfg"
require "../common/bitwidth"
require "./board"

@[AlwaysInline]
private def truncate (x : UInt64, width : Int32) : UInt64
    x & ((1_u64 << width) - 1)
end

@[AlwaysInline]
private def assert_same_width! (a : Int32, b : Int32)
    raise "Bit widths differ" unless a == b
end

module Isekai::AltBackend

# 'width' may be > 64, but the actual value will always be modulo 2^64.
struct ConstTrace
    def initialize (@value : UInt64, @width : Int32)
    end

    getter value, width

    def self.new_bool (value : UInt64)
        return self.new(value, width: 1)
    end
end

struct WireTrace
    def initialize (@wire : Wire, @width : Int32)
    end

    getter wire, width

    def self.new_bool (wire : Wire)
        return self.new(wire, width: 1)
    end
end

alias JoinedTrace = ConstTrace | WireTrace
alias SplitTrace = Array(JoinedTrace)
alias Trace = JoinedTrace | SplitTrace

def self.to_split (board : Board, trace : Trace) : SplitTrace
    case trace
    when WireTrace
        max_nbits = board.max_nbits(trace.wire, width: trace.width)
        if max_nbits <= 1
            return SplitTrace.new(trace.width) do |i|
                i == 0 ? WireTrace.new_bool(trace.wire) : ConstTrace.new_bool(0)
            end
        else
            wires = board.split(trace.wire, into: max_nbits)
            return SplitTrace.new(trace.width) do |i|
                i < max_nbits ? WireTrace.new_bool(wires[i]) : ConstTrace.new_bool(0)
            end
        end
    when ConstTrace
        return SplitTrace.new(trace.width) do |i|
            ConstTrace.new_bool((trace.value >> i) & 1)
        end
    else
        return trace
    end
end

def self.to_joined (board : Board, trace : Trace) : JoinedTrace
    if trace.is_a? SplitTrace
        width = trace.size

        const_summand : UInt128 = 0
        wire_summand : Wire? = nil

        trace.each_with_index do |bit, pos|
            if bit.is_a? ConstTrace
                const_summand += bit.value.to_u128 << pos
            else
                bit_w = board.const_mul(1_u128 << pos, bit.wire, width)
                if wire_summand
                    wire_summand = board.add(wire_summand, bit_w, width)
                else
                    wire_summand = bit_w
                end
            end
        end

        unless wire_summand
            return ConstTrace.new(const_summand.to_u64, width)
        end
        # we assume that the 'Board' class is smart enough to figure out this will not overflow:
        w = board.const_add(const_summand, wire_summand, width)
        return WireTrace.new(w, width)
    else
        return trace
    end
end

private def self.joined_add_cw (board : Board, c, j : WireTrace) : JoinedTrace
    w = board.const_add(c, j.wire, j.width)
    return WireTrace.new(w, j.width)
end

def self.joined_add_const (board : Board, c, j : JoinedTrace) : JoinedTrace
    if j.is_a? WireTrace
        return joined_add_cw(board, c, j)
    else
        return ConstTrace.new(truncate(j.value + c.to_u64, j.width), j.width)
    end
end

def self.joined_add (board : Board, j : JoinedTrace, k : JoinedTrace) : JoinedTrace
    assert_same_width! j.width, k.width
    case {j, k}
    when {ConstTrace, ConstTrace}
        return ConstTrace.new(truncate(j.value + k.value, j.width), j.width)
    when {ConstTrace, WireTrace}
        return joined_add_cw(board, j.value, k)
    when {WireTrace, ConstTrace}
        return joined_add_cw(board, k.value, j)
    when {WireTrace, WireTrace}
        w = board.add(j.wire, k.wire, j.width)
        return WireTrace.new(w, j.width)
    else
        raise "unreachable"
    end
end

private def self.joined_mul_cw (board : Board, c, j : WireTrace) : JoinedTrace
    return ConstTrace.new(0, j.width) if c == 0
    w = board.const_mul(c, j.wire, j.width)
    return WireTrace.new(w, j.width)
end

def self.joined_mul_const (board : Board, c, j : JoinedTrace) : JoinedTrace
    if j.is_a? WireTrace
        return joined_mul_cw(board, c, j)
    else
        return ConstTrace.new(truncate(j.value * c.to_u64, j.width), j.width)
    end
end

def self.joined_mul (board : Board, j : JoinedTrace, k : JoinedTrace) : JoinedTrace
    assert_same_width! j.width, k.width
    case {j, k}
    when {ConstTrace, ConstTrace}
        return ConstTrace.new(truncate(j.value * k.value, j.width), j.width)
    when {ConstTrace, WireTrace}
        return joined_mul_cw(board, j.value, k)
    when {WireTrace, ConstTrace}
        return joined_mul_cw(board, k.value, j)
    when {WireTrace, WireTrace}
        w = board.mul(j.wire, k.wire, j.width)
        return WireTrace.new(w, j.width)
    else
        raise "unreachable"
    end
end

def self.joined_zerop (board : Board, j : JoinedTrace) : JoinedTrace
    if j.is_a? WireTrace
        return WireTrace.new_bool(board.zerop(j.wire, j.width))
    else
        return ConstTrace.new_bool(j.value != 0 ? 1_u64 : 0_u64)
    end
end

def self.joined_zext (board : Board, j : JoinedTrace, to new_width : Int32) : JoinedTrace
    old_width = j.width
    raise "This is truncation, not extension" unless old_width <= new_width
    if j.is_a? WireTrace
        return WireTrace.new(board.zext(j.wire, from: old_width, to: new_width), new_width)
    else
        return ConstTrace.new(j.value, new_width)
    end
end

def self.joined_add_output! (board : Board, j : JoinedTrace) : Nil
    if j.is_a? WireTrace
        w = j.wire
    else
        w = board.constant(j.value)
    end
    board.add_output!(w, j.width)
end

end
