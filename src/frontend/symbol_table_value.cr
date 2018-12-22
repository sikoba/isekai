module Isekai

# Defines an entry in the symbol table. The symbol table
# holds both types and expressions (under the different symbol name).
abstract class SymbolTableValue
    # Returns the size of the symbol. For the abstract entry,
    # the size is negative. For the concrete types this would be
    # number of bytes for the type.
    def sizeof
        return -1
    end
end

end
