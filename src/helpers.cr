require "big"

module Isekai
    def self.ceillg2(val)
        if (val < 0)
            return ceillg2(-val)    #TODO handle negative numbers
        end
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