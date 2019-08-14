require "../common/bitwidth"
require "./bit_manip"
require "./dynamic_range"

module Isekai::AltBackend

struct Wire
    def initialize (@index : Int32)
    end

    def to_s (io)
        io << @index
    end
end

alias WireList = Array(Wire)

struct OutputBuffer
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

    def write_const_mul (c : UInt64, w, output) : Nil
        @buf << "const-mul-"
        c.to_s(base: 16, io: @buf)
        @buf << " in 1 <" << w << "> out 1 <" << output << ">\n"
    end

    def write_const_mul_neg (c : UInt64, w, output) : Nil
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
    @const_pool = {} of UInt64 => Wire
    @inputs : Array(Tuple(Wire, BitWidth))
    @nizk_inputs : Array(Tuple(Wire, BitWidth))
    @dynamic_ranges = [] of DynamicRange
    @outbuf : OutputBuffer

    private def allocate_wire_index!
        result = @dynamic_ranges.size
        @dynamic_ranges << DynamicRange.new_for constant: 0
        result
    end

    private def allocate_wire! (dynamic_range : DynamicRange) : Wire
        result = Wire.new(@dynamic_ranges.size)
        @dynamic_ranges << dynamic_range
        result
    end

    def initialize (
            input_bitwidths : Array(BitWidth),
            nizk_input_bitwidths : Array(BitWidth),
            output : IO)

        @outbuf = OutputBuffer.new(output)

        @inputs      = input_bitwidths.map { |bw| {allocate_wire!(DynamicRange.new_for(bw)), bw} }
        @one_const   = allocate_wire! DynamicRange.new_for constant: 1
        @nizk_inputs = nizk_input_bitwidths.map { |bw| {allocate_wire!(DynamicRange.new_for(bw)), bw} }

        @inputs.each { |(w, _)| @outbuf.write_input(w) }
        @outbuf.write_one_input(@one_const)
        @nizk_inputs.each { |(w, _)| @outbuf.write_nizk_input(w) }
    end

    def max_nbits (w : Wire, bitwidth : BitWidth)
        @dynamic_ranges[w.@index].max_nbits
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
        result = WireList.new(num) { allocate_wire! DynamicRange.new_bool }
        @outbuf.write_split(w, outputs: result)
        result
    end

    private def yank (w : Wire, bitwidth : BitWidth) : Wire
        bits = split_impl(w, into: bitwidth.@width)
        result = bits[0]
        (1...bits.size).each do |i|
            factor = 1_u64 << i

            bit_w = allocate_wire_index!
            @outbuf.write_const_mul(factor, bits[i], output: bit_w)

            res_w = allocate_wire! DynamicRange.new_for BitWidth.new(i + 1)
            @outbuf.write_add(result, bit_w, output: res_w)

            result = res_w
        end
        result
    end

    def split (w : Wire, into num : Int32) : WireList
        raise "Missed optimization" if num == 0
        raise "Missed optimization" if @dynamic_ranges[w.@index].fits_into_1bit?
        split_impl(w, into: num)
    end

    def zerop (w : Wire, bitwidth : BitWidth) : Wire
        return w if @dynamic_ranges[w.@index].fits_into_1bit?
        # This operation has two output wires!
        dummy = allocate_wire_index!
        result = allocate_wire! DynamicRange.new_bool
        @outbuf.write_zerop(w, dummy_output: dummy, output: result)
        result
    end

    def const_mul (c : UInt64, w : Wire, bitwidth : BitWidth) : Wire
        raise "Missed optimization" if c == 0
        return w if c == 1

        w_range = @dynamic_ranges[w.@index]
        new_range, overflow = w_range.mul(DynamicRange.new_for(constant: c), bitwidth)
        result = allocate_wire! new_range

        @outbuf.write_const_mul(c, w, output: result)

        overflow ? yank(result, bitwidth) : result
    end

    def mul (w : Wire, x : Wire, bitwidth : BitWidth) : Wire
        w_range = @dynamic_ranges[w.@index]
        x_range = @dynamic_ranges[x.@index]
        new_range, overflow = w_range.mul(x_range, bitwidth)
        result = allocate_wire! new_range

        @outbuf.write_mul(w, x, output: result)

        overflow ? yank(result, bitwidth) : result
    end

    def add (w : Wire, x : Wire, bitwidth : BitWidth) : Wire
        w_range = @dynamic_ranges[w.@index]
        x_range = @dynamic_ranges[x.@index]
        new_range, overflow = w_range.add(x_range, bitwidth)
        result = allocate_wire! new_range

        @outbuf.write_add(w, x, output: result)

        overflow ? yank(result, bitwidth) : result
    end

    def const_add (c : UInt64, w : Wire, bitwidth : BitWidth) : Wire
        return w if c == 0
        if bitwidth.@width == 1
            # since 'c' is not 0, is must be '1'; this is 'logical not'
            neg_w = allocate_wire_index!
            @outbuf.write_const_mul_neg(1, w, output: neg_w)
            result = allocate_wire! DynamicRange.new_bool
            @outbuf.write_add(@one_const, neg_w, output: result)
            result
        else
            add(constant(c), w, bitwidth)
        end
    end

    def zext (w : Wire, from old_bitwidth : BitWidth, to new_bitwidth : BitWidth) : Wire
        return w
    end

    def constant (c : UInt64) : Wire
        return one_constant if c == 1
        return @const_pool.fetch(c) do
            result = allocate_wire! DynamicRange.new_for constant: c
            @outbuf.write_const_mul(c, @one_const, output: result)
            result
        end
    end

    def add_output! (w : Wire) : Nil
        @outbuf.write_output w
    end

    def done! : Nil
        @outbuf.flush! total: @dynamic_ranges.size
    end
end

end
