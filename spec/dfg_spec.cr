require "spec"
require "../src/common/dfg.cr"
require "../src/common/storage.cr"
require "../src/common/types.cr"
require "../src/common/symbol_table_key.cr"

describe Isekai do
    it "storage key" do
        storage1 = Isekai::Storage.new("x", 1)

        storage_ref = Isekai::StorageRef.new(Isekai::IntType.new, storage1, 1)
        storage_ref.key.should eq Isekai::StorageKey.new(storage1, 1)

        ref = storage_ref.ref
        ref.deref.key.should eq Isekai::StorageKey.new(storage1, 1)
    end
end
