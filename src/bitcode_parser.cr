require "./dfg"
require "./frontend/symbol_table_key"

module Isekai
    class BitcodeParser
        def initialize(@input_file : String, @loop_sanity_limit : Int32, @bit_width : Int32)
        end

        def parse()
            nizk_inputs = Array(DFGExpr).new
            inputs = Array(DFGExpr).new
            output = Array(Tuple(StorageKey, DFGExpr)).new
            return {inputs, nizk_inputs, output}
        end
    end
end
