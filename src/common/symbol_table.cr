require "./symbol_table_key.cr"
require "./symbol_table_value.cr"
require "./storage.cr"
require "./types.cr"

module Isekai

# Exception raised when trying to lookup
# not existing symbol
class UndefinedSymbolException < Exception
end

# Exception raised when trying to declare
# an already declared symbol
class DuplicateDeclarationException < Exception
end

# Symbol table.
# instance variables:
#   @ depth = depth of the current scope
#   @ decl_table = set of declared variable names
#   @ assign_table = maps string identifiers to List(DFGExpr)
#   @ scope = if present, collects assigned keys
#             that are declared/modified in this scope
#             (to track side-effects)
#
# class variables:
#   @@ max_depth = maximum encountered scope level
class SymbolTable
    @@max_depth = 0

    def initialize ()
        initialize(nil, nil)
    end

    # Constructs a symbol table.
    #
    #
    # Params:
    #     parent = parent symbol table (the enclosing scope)
    #     scope = set of the affected variables when applying expressions
    #             in this scope
    def initialize (@parent : (SymbolTable|Nil), @scope : (Set(Key)|Nil))
        @decl_table = Set(Key).new
        @assign_type_table = Hash(Key, SymbolTableValue).new

        if (@parent != nil)
            @depth = @parent.not_nil!.@depth + 1
            if (@depth > @@max_depth)
                @@max_depth += 1
                if @@max_depth > 100
                    raise "Too deep AST - symbol table is over 100 levels deep"
                end
            end
        else
            @depth = 0
        end
    end

    # Returns: 
    #     indicator if the symbol was already declared
    def is_declared? (key)
        @decl_table.includes? key
    end

    # Returns:
    #     list of the modified symbols
    def getScope : Set(Key)
        if scope = @scope
            return scope
        else
            raise "No scope was set"
        end
    end

    # declares a new symbol
    def declare (key, value)
        if is_declared? key
            raise DuplicateDeclarationException.new
        end

        # Declare symbol and add its value
        @decl_table.add(key.as(Key))
        @assign_type_table[key.as(Key)] = value.as(SymbolTableValue)
    end

    # Assigns the value with the key
    def assign (key, value)
        # This symbol's value is valid in this and all enclosing
        # scopes. Propagate this assignemnt.
        propagate(key)
        @assign_type_table[key.as(Key)] = value.as(SymbolTableValue)

        # Note the side-effect to @scope
        note_assignment(key)
    end

    # Look up the value for the key in this and
    # all parent scopes
    #
    # Params:
    #     key = key to lookup
    #
    # Returns:
    #     value of the symbol behind the key.
    def lookup (key) : SymbolTableValue
        raise "Passed not Key #{key.inspect}" unless key.is_a? Key
        return propagate(key)
    end

    # Look up the value for the key in this and
    # all parent scopes. If the found value is a storage reference,
    # it resolves that reference
    #
    # Params:
    #     key = key to lookup
    #
    # Returns:
    #     value of the symbol behind the key.
    def eager_lookup (key) : SymbolTableValue
        val = lookup(key)
        if val.is_a? StorageRef
            return lookup(val.as(StorageRef).key)
        end
        return val
    end

    # Finds the key in this or in parent's scope
    # and brings it to the current scope.
    #
    # Params:
    #     key = entry to look for
    #
    # Returns:
    #     value associated with key
    protected def propagate (key)
        if value = fetch(key)
            @assign_type_table[key.as(Key)] = value
            return value
        end
        raise "Unknown type"
    end

    # Fetches the key from this or any parent scopes.
    # Raises UndefinedSymbol exception if not found
    protected def fetch (key)
        val = @assign_type_table[key]?
        if val != nil
            return val
        end

        if parent = @parent
            return parent.fetch(key)
        else
            raise UndefinedSymbolException.new
        end
    end

    # Notes the side effect in the current scope.
    protected def note_assignment(key)
        if @decl_table.includes? key
            # It's already modified in this scope
            return
        else
            if scope = @scope
                scope.add(key)
            end
            if parent = @parent
                parent.note_assignment(key)
            end
        end
    end

    # builds string representation
    def to_s
        ding = "SCOPE" unless @scope == nil
        if @scope == nil
            ding = ""
        else
            ding = "(SCOPE)"
        end

        return @assign_table.to_s + ding
    end

    # Goes over the current scope, and for every
    # symbol in the current scope it copies the value
    # from the extract_symbtab and assigns it to the
    # apply_symtab - applying the changes done in the
    # side effects symbol table.
    def apply_changes (extract_symtab, apply_symtab)
        result_symtab = apply_symtab
        if scope = @scope
            scope.each do |key|
                value = extract_symtab.lookup(key)
                result_symtab.assign(key, value)
            end
        else
            raise "Symbol table is invalid - missing scope"
        end
        return result_symtab
    end
end
end
