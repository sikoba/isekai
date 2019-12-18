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

    @[AlwaysInline]
    def to_u128
        @index.to_u128
    end

    @[AlwaysInline]
    def to_i32
        @index
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
    private struct Datum
        enum Command
            Input
            NizkInput
            Output
            ConstMul
            ConstMulNeg
            ConstMulVerbatim
            Mul
            Add
            Div
            Split
            Zerop
        end

        @arg1 : UInt128
        @arg2 : Int32
        @arg3 : Int32
        @command : Command

        @[AlwaysInline]
        def initialize (@command, arg1, arg2 = -1, arg3 = -1)
            @arg1 = arg1.to_u128
            @arg2 = arg2.to_i32
            @arg3 = arg3.to_i32
        end
    end

    @data = Array(Datum).new
    @verbatims = Array(BigInt).new
    @comments = Array(::Symbol).new
    @file : File

    def initialize (@file)
    end

    private def add_comment! (comment : ::Symbol? = nil) : Int32
        if comment
            result = @comments.size
            @comments << comment
            result
        else
            -1
        end
    end

    def write_input (w : Wire, comment : ::Symbol? = nil) : Nil
        comment ||= :"input"
        @data << Datum.new(Datum::Command::Input, w, add_comment!(comment))
    end

    def write_nizk_input (w : Wire, comment : ::Symbol? = nil) : Nil
        comment ||= :"input"
        @data << Datum.new(Datum::Command::NizkInput, w, add_comment!(comment))
    end

    def write_const_mul (c : UInt128, w : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::ConstMul, c, w, output)
    end

    def write_const_mul_neg (c : UInt128, w : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::ConstMulNeg, c, w, output)
    end

    def write_const_mul_verbatim (c : BigInt, w : Wire, output : Wire) : Nil
        verbatim_idx = @verbatims.size
        @verbatims << c
        @data << Datum.new(Datum::Command::ConstMulVerbatim, verbatim_idx, w, output)
    end

    def write_mul (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Mul, w, x, output)
    end

    def write_add (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Add, w, x, output)
    end

    def write_div (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Div, w, x, output)
    end

    def write_split (w : Wire, outputs : WireRange) : Nil
        @data << Datum.new(Datum::Command::Split, w, outputs.@start, outputs.@finish)
    end

    def write_zerop (w : Wire, dummy_output : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Zerop, w, dummy_output, output)
    end

    def write_output (w : Wire, comment : ::Symbol? = nil) : Nil
        @data << Datum.new(Datum::Command::Output, w, add_comment!(comment))
    end

    private def append_comment_to_file! (idx : Int32)
        unless idx == -1
            @file << " # " << @comments[idx]
        end
    end

    def flush! (total : Int32) : Nil
        @file << "total " << total << "\n"

        @data.each do |datum|
            case datum.@command

            when .input?
                @file << "input " << datum.@arg1
                append_comment_to_file!(datum.@arg2)
                @file << "\n"

            when .nizk_input?
                @file << "nizkinput " << datum.@arg1
                append_comment_to_file!(datum.@arg2)
                @file << "\n"

            when .output?
                @file << "output " << datum.@arg1
                append_comment_to_file!(datum.@arg2)
                @file << "\n"

            when .const_mul?
                @file << "const-mul-"
                datum.@arg1.to_s(base: 16, io: @file)
                @file << " in 1 <" << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .const_mul_neg?
                @file << "const-mul-neg-"
                datum.@arg1.to_s(base: 16, io: @file)
                @file << " in 1 <" << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .const_mul_verbatim?
                verbatim = @verbatims[datum.@arg1]
                if verbatim < 0
                    @file << "const-mul-neg"
                else
                    @file << "const-mul-"
                end
                verbatim.to_s(base: 16, io: @file)
                @file << " in 1 <" << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .mul?
                @file << "mul in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .add?
                @file << "add in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .div?
                @file << "div in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .split?
                range_start, range_finish = datum.@arg2, datum.@arg3
                nrange = range_finish - range_start
                @file << "split in 1 <" << datum.@arg1 << "> out " << nrange << " <"
                @file << range_start unless nrange == 0
                (range_start+1...range_finish).each { |i| @file << " " << i }
                @file << ">\n"

            when .zerop?
                @file << "zerop in 1 <" << datum.@arg1 << "> out 2 <" << datum.@arg2 << " " << datum.@arg3 << ">\n"

            else
                raise "unreachable"
            end
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

struct TruncatePolicy
    @width : Int32

    def initialize (@width)
    end

    def self.new_to_width (width : Int32)
        self.new(width)
    end

    def self.new_no_truncate
        self.new(-1)
    end

    def no_truncate?
        @width == -1
    end

    def truncate_to_width : Int32?
        @width unless no_truncate?
    end
end

struct Board
    @one_const : Wire
    @const_pool = {} of UInt128 => Wire
    @neg_const_pool = {} of UInt128 => Wire
    @big_const_pool = {} of BigInt => Wire
    @cached_splits = {} of Int32 => WireRange
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

    def zerop (w : Wire, policy : TruncatePolicy) : Wire
        if (width = policy.truncate_to_width)
            arg = truncate(w, to: width)
        else
            arg = w
        end

        n = @dynamic_ranges[arg.@index].max_nbits
        if n && n <= 1
            return arg
        end

        # This operation has two output wires!
        dummy = allocate_wire! DynamicRange.new_for_bool
        result = allocate_wire! DynamicRange.new_for_bool
        @outbuf.write_zerop(arg, dummy_output: dummy, output: result)
        result
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

    def const_mul_neg (c : UInt128, w : Wire, policy : TruncatePolicy) : Wire
        raise "Missed optimization" if c == 0
        if (width = policy.truncate_to_width)
            arg = truncate(w, to: width)
        else
            arg = w
        end
        result = allocate_wire! DynamicRange.new_for_undefined
        @outbuf.write_const_mul_neg(c, arg, output: result)
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

    def add_output! (w : Wire, policy : TruncatePolicy, nagai : Bool = false) : Nil
        if (width = policy.truncate_to_width)
            arg = truncate(w, to: width)
        else
            arg = w
        end

        # do the output-cast thing
        o = allocate_wire! @dynamic_ranges[arg.@index]
        @outbuf.write_mul(arg, @one_const, output: o)

        @outbuf.write_output o, comment: (:"NAGAI" if nagai)
    end

    def done! : Nil
        @outbuf.flush! total: @dynamic_ranges.size
    end
end

end
