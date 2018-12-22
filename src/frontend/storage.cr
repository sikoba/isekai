require "./symbol_table_value"

module Isekai

# Storage instance. Storage is analog to the memory
# location where the state of the given type is stored.
# Object of this class is unique and distinctive - the label
# is just a label and it doesn't makes the objects identity
class Storage < SymbolTableValue
    def initialize(@label : String, @size : Int32)
    end

    # Returns a null storage instance.
    def self.null
        if @@null == nil
            @@null = Null.new()
        end
        return @@null
    end
end

# Null storage
class Null < Storage
    def initialize()
        super("null", 0)
    end
end
end
