require "big"

module Isekai::Backend
    def self.ceillg2(val)
        result = -1
        (0..254-1).each do |i|
            if (val < (BigInt.new(1)<<i))
                result = i
                break
            end
        end

        if result != -1
            return result
        else
            raise "Overflow in ceillg2: #{val}"
        end
    end
end
