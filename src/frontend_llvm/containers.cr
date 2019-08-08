module Isekai::LLVMFrontend::Containers

class Multiset(T)
    def initialize ()
        @hash = Hash(T, Int32).new(default_value: 0)
    end

    def includes? (x)
        @hash.has_key? x
    end

    def add (x)
        @hash[x] += 1
        self
    end

    def delete (x)
        if (@hash[x] -= 1) == 0
            @hash.delete x
        end
        self
    end
end

end
