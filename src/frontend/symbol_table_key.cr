require "./storage.cr"

module Isekai
    # Base class for keys for Symbol table entries.
    # Symbol table holds two classes of keys - symbols,
    # which refer to declaration of variables and StorageKeys - which
    # refer to the storage instances (for example, struct fields or
    # variable instances)
    class Key
    end

    # Entry in the symbol table for the symbols.
    class Symbol < Key

        # Constructs the symbol
        # Params:
        #     name = name of the symbol
        def initialize (@name : String)
        end

        # Symbols in the same scope are differentiated
        # only by the name
        def_hash @name
        def_equals @name

        # String representation of the symbol is nothing
        # but a name
        def to_s
            return @name
        end
    end

    # Entry in the symbol table for pseudosymbols (the hints
    # to the compiler, such as _unroll)
    class PseudoSymbol < Symbol
        def to_s
            "~" + super.to_s
        end
    end

    # Entry in the symbol table representing an instance
    class StorageKey < Key

        # Constructs the storage key - the combination
        # of the storage and the index in the storage
        # (for example using struct storage and the field index,
        # we can refer to a specific field in the struct's instance)
        #
        # Params:
        #     storage = storage instance
        #     idx = index in the storage instance
        def initialize(@storage : Storage, @idx : Int32)
        end

        # StorageKey's identity is a combination of the storage
        # instance and the index
        def_hash @storage, @idx
        def_equals @storage, @idx
    end
end
