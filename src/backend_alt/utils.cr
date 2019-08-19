module Isekai::AltBackend::Utils

def self.write_input_values (circuit_filename, values, inputs_bitwidths, nizk_inputs_bitwidths)
    n_inputs = inputs_bitwidths.size
    n_nizk_inputs = nizk_inputs_bitwidths.size
    File.open("#{circuit_filename}.in", "w") do |file|
        n_total = n_inputs + 1 + n_nizk_inputs
        (0...n_total).each do |i|
            case i <=> n_inputs
            when .< 0
                value = values[i]? || 0
                bitwidth = inputs_bitwidths[i]
            when .== 0
                value = 1
                bitwidth = BitWidth.new(1)
            else
                value = values[i - 1]? || 0
                bitwidth = nizk_inputs_bitwidths[i - 1 - n_inputs]
            end

            file << i << " "
            unsigned_value = bitwidth.truncate(value.to_u64)
            unsigned_value.to_s(base: 16, io: file)
            file << "\n"
        end
    end
end

end
