require "../../common/bitwidth"

module Isekai::AltBackend::Boolean

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
    def to_i32
        @index
    end
end

private struct OutputBuffer
    private struct Datum
        enum Command
            Input
            OneInput
            NizkInput
            Output
            And
            Or
            Xor
            Nand
        end

        @command : Command
        @arg1 : Int32
        @arg2 : Int32
        @arg3 : Int32

        @[AlwaysInline]
        def initialize (@command, arg1, arg2 = -1, arg3 = -1)
            @arg1 = arg1.to_i32
            @arg2 = arg2.to_i32
            @arg3 = arg3.to_i32
        end
    end

    @data = Array(Datum).new
    @file : IO

    def initialize (@file)
    end

    def write_input (w : Wire) : Nil
        @data << Datum.new(Datum::Command::Input, w)
    end

    def write_one_input (w : Wire) : Nil
        @data << Datum.new(Datum::Command::OneInput, w)
    end

    def write_nizk_input (w : Wire) : Nil
        @data << Datum.new(Datum::Command::NizkInput, w)
    end

    def write_and (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::And, w, x, output)
    end

    def write_or (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Or, w, x, output)
    end

    def write_xor (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Xor, w, x, output)
    end

    def write_nand (w : Wire, x : Wire, output : Wire) : Nil
        @data << Datum.new(Datum::Command::Nand, w, x, output)
    end

    def write_output (w : Wire) : Nil
        @data << Datum.new(Datum::Command::Output, w)
    end

    def flush! (total : Int32) : Nil
        @file << "total " << total << "\n"

        @data.each do |datum|
            case datum.@command

            when .input?
                @file << "input " << datum.@arg1 << " # input\n"

            when .one_input?
                @file << "input " << datum.@arg1 << " # one-input\n"

            when .nizk_input?
                @file << "nizkinput " << datum.@arg1 << " # input\n"

            when .output?
                @file << "output " << datum.@arg1 << "\n"

            when .and?
                @file << "and in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .or?
                @file << "or in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .xor?
                @file << "xor in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            when .nand?
                @file << "nand in 2 <" << datum.@arg1 << " " << datum.@arg2 << "> out 1 <" << datum.@arg3 << ">\n"

            else
                raise "unreachable"
            end
        end

        @file.flush
    end
end

alias WireList = Array(Wire)

class Board
    @one_const : Wire
    @next_wire_index : Int32 = 0
    @inputs : Array(WireList)
    @nizk_inputs : Array(WireList)
    @outbuf : OutputBuffer
    @zero_const : Wire? = nil

    private def allocate_wire! : Wire
        result = Wire.new(@next_wire_index)
        @next_wire_index += 1
        result
    end

    private def allocate_wire_range! (n : Int32) : WireList
        WireList.new(n) { allocate_wire! }
    end

    def initialize (
            input_bitwidths : Array(BitWidth),
            nizk_input_bitwidths : Array(BitWidth),
            output : IO)

        @outbuf = OutputBuffer.new(output)

        @inputs = input_bitwidths.map { |bw| allocate_wire_range!(bw.@width) }
        @one_const = allocate_wire!
        @nizk_inputs = nizk_input_bitwidths.map { |bw| allocate_wire_range!(bw.@width) }

        @inputs.each do |wire_list|
            wire_list.each { |w| @outbuf.write_input(w) }
        end
        @outbuf.write_one_input(@one_const)
        @nizk_inputs.each do |wire_list|
            wire_list.each { |w| @outbuf.write_nizk_input(w) }
        end
    end

    def input (idx : Int32) : WireList
        @inputs[idx]
    end

    def one_constant : Wire
        @one_const
    end

    def nizk_input (idx : Int32) : WireList
        @nizk_inputs[idx]
    end

    def and (w : Wire, x : Wire) : Wire
        result = allocate_wire!
        @outbuf.write_and(w, x, output: result)
        result
    end

    def or (w : Wire, x : Wire) : Wire
        result = allocate_wire!
        @outbuf.write_or(w, x, output: result)
        result
    end

    def xor (w : Wire, x : Wire) : Wire
        result = allocate_wire!
        @outbuf.write_xor(w, x, output: result)
        result
    end

    def nand (w : Wire, x : Wire) : Wire
        result = allocate_wire!
        @outbuf.write_nand(w, x, output: result)
        result
    end

    def make_zero_constant! : Wire
        @zero_const ||= xor(@one_const, @one_const)
    end

    def constant (c : Bool) : Wire
        c ? one_constant : make_zero_constant!
    end

    def add_output! (w : Wire) : Nil
        @outbuf.write_output w
    end

    def done! : Nil
        @outbuf.flush! total: @next_wire_index
    end
end

end
