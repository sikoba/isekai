module Isekai
class BitWidth
    @overflow_limit : Int32?

	def initialize(width : Int32, ignore_overflow)
		@width = width
		if (!ignore_overflow)
            @overflow_limit = 250
        end
    end

	def ignoring_overflow()
        return @overflow_limit.is_a? Nil
    end

	def get_width()
        return @width
    end

	def get_sign_bit()
        return @width - 1
    end

	def get_neg1()
        return (1 << @width) - 1
    end

	def leftshift(a, b)
        return (a<<b) & get_neg1()
    end

	def rightshift(a, b)
        return ((a & get_neg1()) >> b)
    end

	def truncate(bits)
		if (@overflow_limit && bits >= get_width())
			return get_width()
		else
            return bits
        end
    end
end
end
