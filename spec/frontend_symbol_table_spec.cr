require "spec"
require "../src/common/storage.cr"
require "../src/common/symbol_table_key.cr"
require "../src/common/symbol_table_value.cr"
require "../src/common/types.cr"
require "../src/common/symbol_table.cr"

describe Isekai do
    it "symbol table" do
        storage1 = Isekai::Storage.new("x", 1)
        storage2 = Isekai::Storage.new("x", 1)
        storage3 = Isekai::Storage.new("x", 1)

        storage = Isekai::Storage.new("instance", 10)

        key1 = Isekai::StorageKey.new(storage, 1)
        key11 = Isekai::StorageKey.new(storage, 1)
        key2 = Isekai::StorageKey.new(storage, 2)
        key3 = Isekai::StorageKey.new(storage, 3)

        parent_symtable = Isekai::SymbolTable.new(nil, Set(Isekai::Key).new)
        symtable = Isekai::SymbolTable.new(parent_symtable, Set(Isekai::Key).new)

        symtable.is_declared?(key1).should eq false
        symtable.declare(key1, storage1)
        symtable.is_declared?(key1).should eq true

        symtable.lookup(key1).should eq storage1

        # Access the symbol from the parent scope
        parent_symtable.declare(key2, storage2)
        symtable.lookup(key2).should eq storage2

        # assign the key through the assign method, without declaring it
        symtable.assign(key2, storage3)
        scope = symtable.getScope()
        scope.includes?(key1).should eq false
        scope.includes?(key2).should eq true
    end
end

