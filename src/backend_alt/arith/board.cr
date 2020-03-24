require "big"
require "../../common/bitwidth"
require "./dynamic_range"

module Isekai::AltBackend::Arith

struct Wire
    private INVALID = -1

    @[AlwaysInline]
    def initialize (@index : Int32)
    end

    @[AlwaysInline]
    def self.new_invalid
        self.new(INVALID)
    end

    @[AlwaysInline]
    def invalid?
        @index == INVALID
    end

    @[AlwaysInline]
    def == (other : Wire)
        @index == other.@index
    end

    def to_s (io)
        @index.to_s(io: io)
        self
    end
end

struct WireRange
    include Indexable(Wire)

    def initialize (@start : Int32, @finish : Int32)
    end

    def self.new_for_single (w : Wire)
        self.new(w.@index, w.@index + 1)
    end

    def size
        @finish - @start
    end

    def unsafe_fetch (index : Int)
        Wire.new(@start + index)
    end
end

private struct OutputBuffer

    def self.write_maybe_comment (comment : ::Symbol?, to file : File) : Nil
        if comment
            file << " # " << comment
        end
    end

    def self.write_collection (wires, to file : File) : Nil
        n = wires.size
        file << n << " <"
        unless n == 0
            file << wires[0]
            (1...n).each do |i|
                file << " " << wires[i]
            end
        end
        file << ">"
    end

    private struct InputCmd
        def initialize (@w : Wire, @comment : ::Symbol?)
        end

        def write (to file : File) : Nil
            file << "input " << @w
            OutputBuffer.write_maybe_comment(@comment, to: file)
            file << "\n"
        end
    end

    private struct NizkInputCmd
        def initialize (@w : Wire, @comment : ::Symbol?)
        end

        def write (to file : File) : Nil
            file << "nizkinput " << @w
            OutputBuffer.write_maybe_comment(@comment, to: file)
            file << "\n"
        end
    end

    private struct OutputCmd
        def initialize (@w : Wire, @comment : ::Symbol?)
        end

        def write (to file : File) : Nil
            file << "output " << @w
            OutputBuffer.write_maybe_comment(@comment, to: file)
            file << "\n"
        end
    end

    private struct ConstMulCmd
        def initialize (@i : Wire, @c : UInt128, @o : Wire)
        end

        def write (to file : File) : Nil
            file << "const-mul-"
            @c.to_s(base: 16, io: file)
            file << " in 1 <" << @i << "> out 1 <" << @o << ">\n"
        end
    end

    private struct ConstMulNegCmd
        def initialize (@i : Wire, @c : UInt128, @o : Wire)
        end

        def write (to file : File) : Nil
            file << "const-mul-neg-"
            @c.to_s(base: 16, io: file)
            file << " in 1 <" << @i << "> out 1 <" << @o << ">\n"
        end
    end

    private struct ConstMulVerbatimCmd
        def initialize (@i : Wire, @c : BigInt, @o : Wire)
        end

        def write (to file : File) : Nil
            if @c < 0
                file << "const-mul-neg"
            else
                file << "const-mul-"
            end
            @c.to_s(base: 16, io: file)
            file << " in 1 <" << @i << "> out 1 <" << @o << ">\n"
        end
    end

    private struct MulCmd
        def initialize (@i1 : Wire, @i2 : Wire, @o : Wire)
        end

        def write (to file : File) : Nil
            file << "mul in 2 <" << @i1 << " " << @i2 << "> out 1 <" << @o << ">\n"
        end
    end

    private struct AddCmd
        def initialize (@i1 : Wire, @i2 : Wire, @o : Wire)
        end

        def write (to file : File) : Nil
            file << "add in 2 <" << @i1 << " " << @i2 << "> out 1 <" << @o << ">\n"
        end
    end

    private struct DivCmd
        def initialize (@i1 : Wire, @i2 : Wire, @o : Wire)
        end

        def write (to file : File) : Nil
            file << "div in 2 <" << @i1 << " " << @i2 << "> out 1 <" << @o << ">\n"
        end
    end

    private struct SplitCmd
        def initialize (@i : Wire, @o : WireRange)
        end

        def write (to file : File) : Nil
            file << "split in 1 <" << @i << "> out "
            OutputBuffer.write_collection(@o, to: file)
            file << "\n"
        end
    end

    private struct ZeropCmd
        def initialize (@i : Wire, @o1 : Wire, @o2 : Wire)
        end

        def write (to file : File) : Nil
            file << "zerop in 1 <" << @i << "> out 2 <" << @o1 << " " << @o2 << ">\n"
        end
    end

    private struct DivideCmd
        def initialize (@width : Int32, @i1 : Wire, @i2 : Wire, @o1 : Wire, @o2 : Wire)
        end

        def write (to file : File) : Nil
            file << "div_" << @width << " in 2 <" << @i1 << " " << @i2 << "> out 2 <" << @o1
            file << " " << @o2 << ">\n"
        end
    end

    private struct DloadCmd
        def initialize (@i : Array(Wire), @o : Wire)
        end

        def write (to file : File) : Nil
            file << "dload in "
            OutputBuffer.write_collection(@i, to: file)
            file << " out 1 <" << @o << ">\n"
        end
    end

    private struct AsplitCmd
        def initialize (@i : Wire, @o : WireRange)
        end

        def write (to file : File) : Nil
            file << "asplit in 1 <" << @i << "> out "
            OutputBuffer.write_collection(@o, to: file)
            file << "\n"
        end
    end

    alias Cmd = Union(
        InputCmd,
        NizkInputCmd,
        OutputCmd,
        ConstMulCmd,
        ConstMulNegCmd,
        ConstMulVerbatimCmd,
        MulCmd,
        AddCmd,
        DivCmd,
        SplitCmd,
        ZeropCmd,
        DivideCmd,
        DloadCmd,
        AsplitCmd)

    @file : File
    @commands = [] of Cmd

    def initialize (@file)
    end

    def write_input (w : Wire, comment : ::Symbol? = nil) : Nil
        @commands << InputCmd.new(w, comment: comment || :"input")
    end

    def write_nizk_input (w : Wire, comment : ::Symbol? = nil) : Nil
        @commands << NizkInputCmd.new(w, comment: comment || :"input")
    end

    def write_output (w : Wire, comment : ::Symbol? = nil) : Nil
        @commands << OutputCmd.new(w, comment: comment)
    end

    def write_const_mul (c : UInt128, w : Wire, output : Wire) : Nil
        @commands << ConstMulCmd.new(w, c, output)
    end

    def write_const_mul_neg (c : UInt128, w : Wire, output : Wire) : Nil
        @commands << ConstMulNegCmd.new(w, c, output)
    end

    def write_const_mul_verbatim (c : BigInt, w : Wire, output : Wire) : Nil
        @commands << ConstMulVerbatimCmd.new(w, c, output)
    end

    def write_mul (w : Wire, x : Wire, output : Wire) : Nil
        @commands << MulCmd.new(w, x, output)
    end

    def write_add (w : Wire, x : Wire, output : Wire) : Nil
        @commands << AddCmd.new(w, x, output)
    end

    def write_div (w : Wire, x : Wire, output : Wire) : Nil
        @commands << DivCmd.new(w, x, output)
    end

    def write_split (w : Wire, outputs : WireRange) : Nil
        @commands << SplitCmd.new(w, outputs)
    end

    def write_zerop (w : Wire, dummy_output : Wire, output : Wire) : Nil
        @commands << ZeropCmd.new(w, dummy_output, output)
    end

    def write_dload (values : Array(Wire), idx : Wire, output : Wire) : Nil
        inputs = values.dup
        inputs.unshift(idx)
        @commands << DloadCmd.new(inputs, output)
    end

    def write_divide (w : Wire, x : Wire, output_q : Wire, output_r : Wire, width : Int32) : Nil
        @commands << DivideCmd.new(width, w, x, output_q, output_r)
    end

    def write_asplit (w : Wire, outputs : WireRange) : Nil
        @commands << AsplitCmd.new(w, outputs)
    end

    def flush! (total : Int32) : Nil
        @file << "total " << total << "\n"
        @commands.each do |cmd|
            cmd.write to: @file
        end
        @file.flush
    end
end

struct OverflowPolicy
    @width : Int32

    def initialize (@width)
    end

    def self.new_wrap_around (width : Int32)
        self.new(width)
    end

    def self.new_set_undef_range
        self.new(0)
    end

    def self.new_cannot_overflow (width : Int32)
        self.new(-width)
    end

    def wrap_around_width : Int32?
        @width if @width > 0
    end

    def set_undef_range?
        @width == 0
    end

    def cannot_overflow_width : Int32?
        -@width if @width < 0
    end
end

struct Board
    @one_const : Wire
    @const_pool = {} of UInt128 => Wire
    @neg_const_pool = {} of UInt128 => Wire
    @big_const_pool = {} of BigInt => Wire
    @cached_splits = {} of Int32 => WireRange
    @cached_asplits = {} of Tuple(Int32, Int32) => WireRange
    @inputs : Array(Tuple(Wire, BitWidth))
    @nizk_inputs : Array(Tuple(Wire, BitWidth))
    @dynamic_ranges = [] of DynamicRange
    @outbuf : OutputBuffer
    @p_bits_min : Int32
    @p_bits_max : Int32

    private def allocate_wire! (dynamic_range : DynamicRange) : Wire
        result = Wire.new(@dynamic_ranges.size)
        @dynamic_ranges << dynamic_range
        result
    end

    private def allocate_wire_range! (n : Int32, dynamic_range : DynamicRange) : WireRange
        start = @dynamic_ranges.size
        n.times { @dynamic_ranges << dynamic_range }
        finish = @dynamic_ranges.size
        WireRange.new(start: start, finish: finish)
    end

    def initialize (
            input_bitwidths : Array(BitWidth),
            nizk_input_bitwidths : Array(BitWidth),
            output : File,
            @p_bits_min : Int32,
            @p_bits_max : Int32)

        @outbuf = OutputBuffer.new(output)

        @inputs = input_bitwidths.map do |bitwidth|
            {allocate_wire!(DynamicRange.new_for_bitwidth(bitwidth)), bitwidth}
        end
        @one_const = allocate_wire! DynamicRange.new_for_const 1_u128
        @nizk_inputs = nizk_input_bitwidths.map do |bitwidth|
            {allocate_wire!(DynamicRange.new_for_bitwidth(bitwidth)), bitwidth}
        end

        @inputs.each do |(wire, bitwidth)|
            @outbuf.write_input wire, comment: (:"input NAGAI" if bitwidth.undefined?)
        end

        @outbuf.write_input(@one_const, comment: :"one-input")

        @nizk_inputs.each do |(wire, bitwidth)|
            @outbuf.write_nizk_input wire, comment: (:"input NAGAI" if bitwidth.undefined?)
        end
    end

    def max_nbits (w : Wire) : Int32?
        @dynamic_ranges[w.@index].max_nbits
    end

    private def may_exceed? (w : Wire, width : Int32) : Bool
        n = @dynamic_ranges[w.@index].max_nbits
        raise "may_exceed?() called on an undefined-width wire" unless n
        return n > width
    end

    private def dangerous? (dyn_range : DynamicRange) : Bool
        n = dyn_range.max_nbits
        raise "dangerous?() called on an undefined-width dynamic range" unless n
        return n >= @p_bits_min
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

    def split (w : Wire) : WireRange
        @cached_splits.fetch(w.@index) do
            w_range = @dynamic_ranges[w.@index]

            n = w_range.max_nbits || @p_bits_max
            if n <= 1
                result = WireRange.new_for_single(w)
            else
                result = allocate_wire_range!(n, DynamicRange.new_for_bool)
                @outbuf.write_split(w, outputs: result)
            end

            @cached_splits[w.@index] = result
            result
        end
    end

    private def yank (w : Wire, width : Int32) : Wire
        bits = split(w)
        result = bits[0]
        n = Math.min(width, bits.size)
        (1...n).each do |i|
            w = bits[i]
            factor = 1_u128 << i
            dyn_range = DynamicRange.new_for_width(i + 1)

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

    def zerop (w : Wire) : Wire
        n = @dynamic_ranges[w.@index].max_nbits
        if n && n <= 1
            return w
        end

        # This operation has two output wires!
        dummy = allocate_wire! DynamicRange.new_for_bool
        result = allocate_wire! DynamicRange.new_for_bool
        @outbuf.write_zerop(w, dummy_output: dummy, output: result)
        result
    end

    def dload (values : Array(Wire), idx : Wire) : Wire
        max_width = values.max_of { |w| @dynamic_ranges[w.@index].max_nbits.not_nil! }
        result = allocate_wire! DynamicRange.new_for_width(max_width)
        @outbuf.write_dload(values, idx, output: result)
        result
    end

    def asplit (w : Wire, size : Int32) : WireRange
        key = {w.@index, size}
        @cached_asplits.fetch(key) do
            result = allocate_wire_range! size, DynamicRange.new_for_bool
            @outbuf.write_asplit(w, outputs: result)
            @cached_asplits[key] = result
            result
        end
    end

    def divide (w : Wire, x : Wire, width : Int32) : {Wire, Wire}
        q = allocate_wire! @dynamic_ranges[w.@index]
        r = allocate_wire! @dynamic_ranges[x.@index]
        @outbuf.write_divide(w, x, output_q: q, output_r: r, width: width)
        {q, r}
    end

    private def cast_to_safe_ww (w : Wire, x : Wire, policy : OverflowPolicy)
        case
        when policy.set_undef_range?
            return w, x, DynamicRange.new_for_undefined

        when (width = policy.cannot_overflow_width)
            arg1 = truncate(w, to: width)
            arg2 = truncate(x, to: width)
            new_range = yield @dynamic_ranges[arg1.@index],  @dynamic_ranges[arg2.@index]
            max_range = DynamicRange.new_for_width width
            return arg1, arg2, (new_range < max_range ? new_range : max_range)

        when (width = policy.wrap_around_width)
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

        else
            raise "unreachable"
        end
    end

    private def cast_to_safe_cw (c : UInt128, w : Wire, policy : OverflowPolicy)
        case
        when policy.set_undef_range?
            return w, DynamicRange.new_for_undefined

        when (width = policy.cannot_overflow_width)
            arg = truncate(w, to: width)
            new_range = yield @dynamic_ranges[arg.@index], c
            max_range = DynamicRange.new_for_width width
            return arg, (new_range < max_range ? new_range : max_range)

        when (width = policy.wrap_around_width)
            new_range = yield @dynamic_ranges[w.@index], c
            unless dangerous?(new_range)
                arg = w
            else
                arg = yank(w, width)
                new_range = yield @dynamic_ranges[arg.@index], c
                raise "Unexpected" if dangerous?(new_range)
            end
            return arg, new_range

        else
            raise "unreachable"
        end
    end

    def const_mul (c : UInt128, w : Wire, policy : OverflowPolicy) : Wire
        raise "Missed optimization" if c == 0
        return w if c == 1

        arg, new_range = cast_to_safe_cw(c, w, policy) { |a, b| a * b }

        result = allocate_wire! new_range
        @outbuf.write_const_mul(c, arg, output: result)
        result
    end

    def const_mul (c : BigInt, w : Wire) : Wire
        raise "Missed optimization" if c == 0
        return w if c == 1

        result = allocate_wire! DynamicRange.new_for_undefined
        @outbuf.write_const_mul_verbatim(c, w, output: result)
        result
    end

    def mul (w : Wire, x : Wire, policy : OverflowPolicy) : Wire
        arg1, arg2, new_range = cast_to_safe_ww(w, x, policy) { |a, b| a * b }

        result = allocate_wire! new_range
        @outbuf.write_mul(arg1, arg2, output: result)
        result
    end

    def add (w : Wire, x : Wire, policy : OverflowPolicy) : Wire
        if policy.wrap_around_width == 1
            # this is 1-bit xor
            arg1 = truncate(w, to: 1)
            arg2 = truncate(x, to: 1)

            prod = allocate_wire! DynamicRange.new_for_bool
            @outbuf.write_mul(arg1, arg2, output: prod)

            minus_2_prod = allocate_wire! DynamicRange.new_for_undefined
            @outbuf.write_const_mul_neg(2, prod, output: minus_2_prod)

            simple_sum = allocate_wire! DynamicRange.new_for_width 2
            @outbuf.write_add(arg1, arg2, output: simple_sum)

            result = allocate_wire! DynamicRange.new_for_bool
            @outbuf.write_add(simple_sum, minus_2_prod, output: result)

            return result
        end

        arg1, arg2, new_range = cast_to_safe_ww(w, x, policy) { |a, b| a + b }

        result = allocate_wire! new_range
        @outbuf.write_add(arg1, arg2, output: result)
        result
    end

    def const_add (c : UInt128, w : Wire, policy : OverflowPolicy) : Wire
        return w if c == 0

        if policy.wrap_around_width == 1
            # 'c' must be 1; this is logical not.
            arg = truncate(w, to: 1)

            minus_arg = allocate_wire! DynamicRange.new_for_undefined
            @outbuf.write_const_mul_neg(1, arg, output: minus_arg)

            result = allocate_wire! DynamicRange.new_for_bool
            @outbuf.write_add(minus_arg, @one_const, output: result)

            return result
        end

        arg, new_range = cast_to_safe_cw(c, w, policy) { |a, b| a + b }

        result = allocate_wire! new_range
        @outbuf.write_add(arg, constant(c), output: result)
        result
    end

    def const_add (c : BigInt, w : Wire) : Wire
        return w if c == 0
        add(constant_verbatim(c), w, OverflowPolicy.new_set_undef_range)
    end

    def const_mul_neg (c : UInt128, w : Wire) : Wire
        raise "Missed optimization" if c == 0
        result = allocate_wire! DynamicRange.new_for_undefined
        @outbuf.write_const_mul_neg(c, w, output: result)
        result
    end

    def div (w : Wire, x : Wire) : Wire
        result = allocate_wire! DynamicRange.new_for_undefined
        @outbuf.write_div(w, x, output: result)
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

    def constant_verbatim (c : BigInt) : Wire
        if c < 0
            neg_c = -c
            return constant_neg(neg_c.to_u64!.to_u128!) if neg_c <= UInt64::MAX
        else
            return constant(c.to_u64!.to_u128!) if c <= UInt64::MAX
        end
        return @big_const_pool.fetch(c) do
            result = allocate_wire! DynamicRange.new_for_undefined
            @outbuf.write_const_mul_verbatim(c, @one_const, output: result)
            @big_const_pool[c] = result
            result
        end
    end

    def add_output! (w : Wire, nagai : Bool = false) : Nil
        # do the output-cast thing
        o = allocate_wire! @dynamic_ranges[w.@index]
        @outbuf.write_mul(w, @one_const, output: o)

        @outbuf.write_output o, comment: (:"NAGAI" if nagai)
    end

    def done! : Nil
        @outbuf.flush! total: @dynamic_ranges.size
    end
end

end
