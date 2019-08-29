require "logger"

module Isekai

VERSION = "0.1.0"

# Raised when trying to statically evaluate nonconstant
# expression (for example, when lowering for loop)
class NonconstantExpression < Exception
end

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

end
