require "clang"
require "logger"

module Isekai
    VERSION = "0.1.0"

    # Class that parses and transforms C code into internal state
    class CParser
        # Initialization method.
        # Parameters:
        #   input_file = C file to read
        #   clang_args = arguments to pass to clang (e.g. include directories)
        #   loop_sanity_limit = sanity limit to stop unrolling loops
        #   bit_width = bit width
        #   progress = print progress during processing
        def initialize (@input_file : String, @clang_args : String, @loop_sanity_limit : Int32,
                        @bit_width : Int32, @progress = false)
        end
    end
end
