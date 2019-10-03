require "../common/bitwidth"

module Isekai::AltBackend

private class InputWriter
    @file : File
    @next_index : Int32 = 0

    def initialize (@file)
    end

    def write (value)
        @file << @next_index << " "
        value.to_s(base: 16, io: @file)
        @file << "\n"
        @next_index += 1
        self
    end

    def self.generate (filename) : Nil
        File.open(filename, "w") { |file| yield self.new(file) }
    end
end

private def self.each_logical_input (
        values,
        inputs : Array(BitWidth),
        nizk_inputs : Array(BitWidth))

    n_inputs = inputs.size
    n_nizk_inputs = nizk_inputs.size
    n_total = n_inputs + 1 + n_nizk_inputs
    (0...n_total).each do |i|
        case i <=> n_inputs
        when .< 0
            value = values[i]? || 0
            bitwidth = inputs[i]
        when .== 0
            value = 1
            bitwidth = BitWidth.new(1)
        else
            value = values[i - 1]? || 0
            bitwidth = nizk_inputs[i - 1 - n_inputs]
        end
        unsigned_value = bitwidth.truncate(value.to_u64!)
        yield unsigned_value, bitwidth
    end
end

def self.arith_write_inputs (circuit_filename, values, inputs, nizk_inputs)
    InputWriter.generate("#{circuit_filename}.in") do |writer|
        each_logical_input(values, inputs, nizk_inputs) do |value, _|
            writer.write(value)
        end
    end
end

def self.boolean_write_inputs (circuit_filename, values, inputs, nizk_inputs)
    InputWriter.generate("#{circuit_filename}.in") do |writer|
        each_logical_input(values, inputs, nizk_inputs) do |value, bitwidth|
            (0...bitwidth.@width).each do |i|
                writer.write((value >> i) & 1)
            end
        end
    end
end

end
