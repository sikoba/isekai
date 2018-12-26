require "clang"
require "logger"
require "./clangutils"

module Isekai
    VERSION = "0.1.0"

    # Simple wrapper around the logger's instance.
    # Takes care of the Logger's setup and holds Logger instance
    class Log
      @@log = Logger.new(STDOUT)

      # Setup the logger
      # Parameters:
      #     verbose = be verbose at the output
      def self.setup (verbose = false)
          if verbose
              @@log.level = Logger::DEBUG
          else
              @@log.level = Logger::WARN
          end
      end

      # Returns:
      #     the logger instance
      def self.log
          @@log
      end
    end

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
