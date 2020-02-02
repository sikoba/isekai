require "spec"
require "../src/common/storage.cr"

describe Isekai do
    nul1 = Isekai::Storage.null()
    nul2 = Isekai::Storage.null()

    if !(nul1.is_a? Isekai::Null)
        raise "Null is not an instance of Null storage"
    end

    # make sure we have a single null storage
    nul1.should eq nul2

    storage1 = Isekai::Storage.new("x", 1)
    storage2 = Isekai::Storage.new("x", 1)
     
    # make sure the storage identity doesn't depend
    # on the label/size
    storage1.should_not eq storage2
    storage1.hash.should_not eq storage2.hash
end

