require "../common/bitwidth"
require "./bit_manip"
require "./dynamic_range"

module Isekai::AltBackend

struct Wire
    private INVALID = -1

    def initialize (@index : Int32)
    end

    def self.new_invalid
        self.new(INVALID)
    end

    def invalid?
        @index == INVALID
    end

    def == (other : Wire)
        @index == other.@index
    end

    def to_s (io)
        io << @index
    end
end

alias WireList = Array(Wire)

private struct OutputBuffer
    def initialize (@file : IO)
        @buf = IO::Memory.new
    end

    def write_input (w) : Nil
        @buf << "input " << w << " # input\n"
    end

    def write_one_input (w) : Nil
        @buf << "input " << w << " # one-input\n"
    end

    def write_nizk_input (w) : Nil
        @buf << "nizkinput " << w << " # input\n"
    end

    def write_const_mul (c : UInt128, w, output) : Nil
        @buf << "const-mul-"
        c.to_s(base: 16, io: @buf)
        @buf << " in 1 <" << w << "> out 1 <" << output << ">\n"
    end

    def write_const_mul_neg (c : UInt128, w, output) : Nil
        @buf << "const-mul-neg-"
        c.to_s(base: 16, io: @buf)
        @buf << " in 1 <" << w << "> out 1 <" << output << ">\n"
    end

    def write_mul (w, x, output) : Nil
        @buf << "mul in 2 <" << w << " " << x << "> out 1 <" << output << ">\n"
    end

    def write_add (w, x, output) : Nil
        @buf << "add in 2 <" << w << " " << x << "> out 1 <" << output << ">\n"
    end

    def write_split (w, outputs) : Nil
        @buf << "split in 1 <" << w << "> out " << outputs.size << " <"
        @buf << outputs[0] unless outputs.empty?
        (1...outputs.size).each { |i| @buf << " " << outputs[i] }
        @buf << ">\n"
    end

    def write_zerop (w, dummy_output, output) : Nil
        @buf << "zerop in 1 <" << w << "> out 2 <" << dummy_output << " " << output << ">\n"
    end

    def write_output (w) : Nil
        @buf << "output " << w << "\n"
    end

    def flush! (total)
        @file << "total " << total << "\n"
        @file << @buf
        @file.flush
    end
end

class Board
    @one_const : Wire
    @const_pool = {} of UInt128 => Wire
    @neg_const_pool = {} of UInt128 => Wire
    @inputs : Array(Tuple(Wire, BitWidth))
    @nizk_inputs : Array(Tuple(Wire, BitWidth))
    @dynamic_ranges = [] of DynamicRange
    @outbuf : OutputBuffer
    @p_bits : Int32

    private def allocate_wire! (dynamic_range : DynamicRange) : Wire
        result = Wire.new(@dynamic_ranges.size)
        @dynamic_ranges << dynamic_range
        result
    end

    def initialize (
            input_bitwidths : Array(BitWidth),
            nizk_input_bitwidths : Array(BitWidth),
            output : IO,
            @p_bits : Int32)

        @outbuf = OutputBuffer.new(output)

        @inputs = input_bitwidths.map do |bitwidth|
            {allocate_wire!(DynamicRange.new_for_bitwidth(bitwidth)), bitwidth}
        end
        @one_const = allocate_wire! DynamicRange.new_for_const 1_u128
        @nizk_inputs = nizk_input_bitwidths.map do |bitwidth|
            {allocate_wire!(DynamicRange.new_for_bitwidth(bitwidth)), bitwidth}
        end

        @inputs.each { |(w, _)| @outbuf.write_input(w) }
        @outbuf.write_one_input(@one_const)
        @nizk_inputs.each { |(w, _)| @outbuf.write_nizk_input(w) }
    end

    def max_nbits (w : Wire, width : Int32) : Int32
        n = @dynamic_ranges[w.@index].max_nbits || @p_bits
        BitManip.min(n, width)
    end

    private def may_exceed? (w : Wire, width : Int32) : Bool
        return (@dynamic_ranges[w.@index].max_nbits || 0) > width
    end

    private def dangerous? (dyn_range : DynamicRange) : Bool
        return (dyn_range.max_nbits || 0) >= @p_bits
    end

    def input (idx : Int32) : {Wire, BitWidth}
        @inputs[idx]
    end

    def one_constant : Wire
        @one_const
    end

    def nizk_input (idx : Int32) : {Wire, BitWidth}
        @nizk_inputs[idx]
    end

    private def split_impl (w : Wire, into num : Int32) : WireList
        result = WireList.new(num) { allocate_wire! DynamicRange.new_for_bool }
        @outbuf.write_split(w, outputs: result)
        result
    end

    private def lowbit (w : Wire) : Wire
        if (@dynamic_ranges[w.@index].max_nbits || 0) <= 1
            w
        else
            split_impl(w, into: 1)[0]
        end
    end

    private def yank (w : Wire, width : Int32) : Wire
        bits = split_impl(w, into: width)
        result = lowbit(bits[0])
        (1...bits.size).each do |i|
            w = lowbit(bits[i])
            factor = 1_u128 << i
            dyn_range = DynamicRange.new_for_const factor

            cur_w = allocate_wire! dyn_range
            @outbuf.write_const_mul(factor, w, output: cur_w)

            res_w = allocate_wire! dyn_range
            @outbuf.write_add(result, cur_w, output: res_w)

            result = res_w
        end
        result
    end

    def truncate (w : Wire, to width : Int32) : Wire
        if may_exceed?(w, width)
            yank(w, width)
        else
            w
        end
    end

    def split (w : Wire, into num : Int32) : WireList
        raise "Missed optimization" if num == 0
        raise "Missed optimization" if (@dynamic_ranges[w.@index].max_nbits || 0) <= 1
        split_impl(w, into: num)
    end

    def zerop (w : Wire, width : Int32?) : Wire
        if width
            arg = truncate(w, to: width)
        else
            arg = w
        end

        if (@dynamic_ranges[arg.@index].max_nbits || @p_bits) <= 1
            return arg
        end

        # This operation has two output wires!
        dummy = allocate_wire! DynamicRange.new_for_bool
        result = allocate_wire! DynamicRange.new_for_bool
        @outbuf.write_zerop(arg, dummy_output: dummy, output: result)
        result
    end

    private def cast_to_safe_ww (w : Wire, x : Wire, width : Int32?)
        unless width
            return w, x, DynamicRange.new_for_undefined
        end

        w_range = @dynamic_ranges[w.@index]
        x_range = @dynamic_ranges[x.@index]
        if w_range < x_range
            w, x = x, w
            w_range, x_range = x_range, w_range
        end
        # now, w_range >= x_range

        new_range = yield w_range, x_range
        unless dangerous?(new_range)
            arg1, arg2 = w, x
        else
            arg1 = yank(w, width)
            new_range = yield @dynamic_ranges[arg1.@index], x_range
            unless dangerous?(new_range)
                arg2 = x
            else
                arg2 = yank(x, width)
                new_range = yield @dynamic_ranges[arg1.@index], @dynamic_ranges[arg2.@index]
                raise "Unexpected" if dangerous?(new_range)
            end
        end
        return arg1, arg2, new_range
    end

    private def cast_to_safe_cw (c : UInt128, w : Wire, width : Int32?)
        unless width
            return w, DynamicRange.new_for_undefined
        end

        new_range = yield @dynamic_ranges[w.@index], c
        unless dangerous?(new_range)
            arg = w
        else
            arg = yank(w, width)
            new_range = yield @dynamic_ranges[arg.@index], c
            raise "Unexpected" if dangerous?(new_range)
        end
        return arg, new_range
    end

    def const_mul (c : UInt128, w : Wire, width : Int32?) : Wire
        raise "Missed optimization" if c == 0
        return w if c == 1

        arg, new_range = cast_to_safe_cw(c, w, width) { |a, b| a * b }

        result = allocate_wire! new_range
        @outbuf.write_const_mul(c, w, output: result)
        result
    end

    def mul (w : Wire, x : Wire, width : Int32?) : Wire
        arg1, arg2, new_range = cast_to_safe_ww(w, x, width) { |a, b| a * b }

        result = allocate_wire! new_range
        @outbuf.write_mul(arg1, arg2, output: result)
        result
    end

    def add (w : Wire, x : Wire, width : Int32?) : Wire
        arg1, arg2, new_range = cast_to_safe_ww(w, x, width) { |a, b| a + b }

        result = allocate_wire! new_range
        @outbuf.write_add(arg1, arg2, output: result)
        result
    end

    def const_add (c : UInt128, w : Wire, width : Int32?) : Wire
        return w if c == 0

        arg, new_range = cast_to_safe_cw(c, w, width) { |a, b| a + b }

        result = allocate_wire! new_range
        @outbuf.write_add(arg, constant(c), output: result)
        result
    end

    def const_mul_neg (c : UInt128, w : Wire, width : Int32?) : Wire
        raise "Missed optimization" if c == 0
        if width
            arg = truncate(w, to: width)
        else
            arg = w
        end
        result = allocate_wire! DynamicRange.new_for_undefined
        @outbuf.write_const_mul_neg(c, arg, output: result)
        result
    end

    def assume_width! (w : Wire, width : Int32) : Nil
        @dynamic_ranges[w.@index] = DynamicRange.new_for_width width
    end

    def constant (c : UInt128) : Wire
        return one_constant if c == 1
        return @const_pool.fetch(c) do
            result = allocate_wire! DynamicRange.new_for_const c
            @outbuf.write_const_mul(c, @one_const, output: result)
            @const_pool[c] = result
            result
        end
    end

    def constant_neg (c : UInt128) : Wire
        raise "Missed optimization" if c == 0
        return @neg_const_pool.fetch(c) do
            result = allocate_wire! DynamicRange.new_for_undefined
            @outbuf.write_const_mul_neg(c, @one_const, output: result)
            @neg_const_pool[c] = result
            result
        end
    end

    def add_output! (w : Wire, width : Int32?) : Nil
        if width
            arg = truncate(w, to: width)
        else
            arg = w
        end
        @outbuf.write_output arg
    end

    def done! : Nil
        @outbuf.flush! total: @dynamic_ranges.size
    end
end

end
