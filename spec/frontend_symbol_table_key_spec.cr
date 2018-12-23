require "spec"
require "../src/frontend/storage.cr"
require "../src/frontend/symbol_table_key.cr"

describe Isekai do
    storage = Isekai::Storage.new("instance", 10)

    key1 = Isekai::StorageKey.new(storage, 1)
    key11 = Isekai::StorageKey.new(storage, 1)
    key2 = Isekai::StorageKey.new(storage, 2)

    key1.should eq key11
    key1.should_not eq key2
    key1.hash.should eq key11.hash
    key1.hash.should_not eq key2.hash
end

