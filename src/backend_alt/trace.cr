require "../common/dfg"
require "../common/bitwidth"
require "./board"

module Isekai::AltBackend

struct ConstTrace
    def initialize (@value : UInt64, @bitwidth : BitWidth)
    end

    getter value, bitwidth

    def self.new_bool (value : UInt64)
        return self.new(value, bitwidth: BitWidth.new(1))
    end

    def extend (to new_bitwidth : BitWidth)
        raise "This is truncation, not extension" unless new_bitwidth >= @bitwidth
        return ConstTrace.new(@value, new_bitwidth)
    end
end

struct WireTrace
    def initialize (@wire : Wire, @bitwidth : BitWidth)
    end

    getter wire, bitwidth

    def self.new_bool (wire : Wire)
        return self.new(wire, bitwidth: BitWidth.new(1))
    end

    def extend (to new_bitwidth : BitWidth)
        raise "This is truncation, not extension" unless new_bitwidth >= @bitwidth
        return WireTrace.new(@wire, new_bitwidth)
    end
end

alias JoinedTrace = ConstTrace | WireTrace
alias SplitTrace = Array(JoinedTrace)
alias Trace = JoinedTrace | SplitTrace

def self.to_split (board : Board, trace : Trace) : SplitTrace
    if trace.is_a? WireTrace
        max_nbits = board.max_nbits(trace.wire, bitwidth: trace.bitwidth)
        if max_nbits <= 1
            return SplitTrace.new(trace.bitwidth.@width) do |i|
                i == 0 ? trace : ConstTrace.new_bool(0)
            end
        else
            wires = board.split(trace.wire, into: max_nbits)
            return SplitTrace.new(trace.bitwidth.@width) do |i|
                i < max_nbits ? WireTrace.new_bool(wires[i]) : ConstTrace.new_bool(0)
            end
        end
    elsif trace.is_a? ConstTrace
        return SplitTrace.new(trace.bitwidth.@width) do |i|
            ConstTrace.new_bool((trace.value >> i) & 1)
        end
    else
        return trace
    end
end

def self.to_joined (board : Board, trace : Trace) : JoinedTrace
    if trace.is_a? SplitTrace
        bitwidth = BitWidth.new(trace.size)

        const_summand : UInt64 = 0
        wire_summand : Wire? = nil

        (0...trace.size).each do |pos|
            cur = trace[pos]
            if cur.is_a? ConstTrace
                const_summand += cur.value << pos
            else
                bit_w = board.const_mul(1_u64 << pos, cur.wire, bitwidth: bitwidth)
                if wire_summand
                    # we assume that the 'Board' class is smart enough to figure out these will not
                    # overflow:
                    wire_summand = board.add(wire_summand, bit_w, bitwidth: bitwidth)
                else
                    wire_summand = bit_w
                end
            end
        end

        unless wire_summand
            return ConstTrace.new(const_summand, bitwidth: bitwidth)
        end
        # we assume that the 'Board' class is smart enough to figure out this will not overflow:
        w = board.const_add(const_summand, wire_summand, bitwidth: bitwidth)
        return WireTrace.new(w, bitwidth: bitwidth)
    else
        return trace
    end
end

private def self.joined_add_cw (board : Board, c : UInt64, j : WireTrace) : JoinedTrace
    w = board.const_add(c, j.wire, bitwidth: j.bitwidth)
    return WireTrace.new(w, bitwidth: j.bitwidth)
end

def self.joined_add (board : Board, j : JoinedTrace, k : JoinedTrace) : JoinedTrace
    if j.is_a? ConstTrace
        if k.is_a? ConstTrace
            bitwidth = j.bitwidth & k.bitwidth
            return ConstTrace.new(bitwidth.truncate(j.value + k.value), bitwidth)
        else
            return joined_add_cw(board, j.value, k)
        end
    elsif k.is_a? ConstTrace
        return joined_add_cw(board, k.value, j)
    else
        bitwidth = j.bitwidth & k.bitwidth
        w = board.add(j.wire, k.wire, bitwidth: bitwidth)
        return WireTrace.new(w, bitwidth)
    end
end

private def self.joined_mul_cw (board : Board, c : UInt64, j : WireTrace) : JoinedTrace
    return ConstTrace.new(0, j.bitwidth) if c == 0
    w = board.const_mul(c, j.wire, bitwidth: j.bitwidth)
    return WireTrace.new(w, bitwidth: j.bitwidth)
end

def self.joined_mul (board : Board, j : JoinedTrace, k : JoinedTrace) : JoinedTrace
    if j.is_a? ConstTrace
        if k.is_a? ConstTrace
            bitwidth = j.bitwidth & k.bitwidth
            return ConstTrace.new(bitwidth.truncate(j.value * k.value), bitwidth)
        else
            return joined_mul_cw(board, j.value, k)
        end
    elsif k.is_a? ConstTrace
        return joined_mul_cw(board, k.value, j)
    else
        bitwidth = j.bitwidth & k.bitwidth
        w = board.mul(j.wire, k.wire, bitwidth: bitwidth)
        return WireTrace.new(w, bitwidth)
    end
end

def self.joined_zerop (board : Board, j : JoinedTrace) : JoinedTrace
    if j.is_a? WireTrace
        return WireTrace.new_bool(board.zerop(j.wire, j.bitwidth))
    else
        return ConstTrace.new_bool(j.value != 0 ? 1_u64 : 0_u64)
    end
end

def self.joined_zext (board : Board, j : JoinedTrace, to new_bitwidth : BitWidth) : JoinedTrace
    if j.is_a? WireTrace
        return WireTrace.new(
            board.zext(j.wire, from: j.bitwidth, to: new_bitwidth),
            new_bitwidth)
    else
        return ConstTrace.new(j.value, j.bitwidth)
    end
end

def self.joined_to_wire! (board : Board, j : JoinedTrace) : Wire
    if j.is_a? WireTrace
        return j.wire
    else
        return board.constant(j.value)
    end
end

end
