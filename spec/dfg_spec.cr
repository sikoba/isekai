require "spec"
require "../src/dfg.cr"
require "../src/frontend/storage.cr"
require "../src/frontend/types.cr"
require "../src/frontend/symbol_table_key.cr"

describe Isekai do
    storage1 = Isekai::Storage.new("x", 1)

    storage_ref = Isekai::StorageRef.new(Isekai::IntType.new, storage1, 1)
    storage_ref.key.should eq Isekai::StorageKey.new(storage1, 1)

    ref = storage_ref.ref
    ref.deref.key.should eq Isekai::StorageKey.new(storage1, 1)
end
