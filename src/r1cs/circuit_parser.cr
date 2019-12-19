

module Isekai


  # initialise logger
  #@@sl = SimpleLog.new({
  #  :caller => "#{__FILE__}",
  #  :flogs => "./cir1cs.log",
  #  :fwarn => "./cir1cs.warn.log",
  #  :verbose => "1"
  #})

  class SimpleLog ##TODO
    def p(str)     
    end
    def abort(err)     
    end
  end

  class CheckCircuit
    
  # initialise circuit variables

  @inputs = Array(Int32).new
  @nizkinputs = Array(Int32).new
  @ops = Array( Array(Int32 | Array(Int32) | Symbol) ).new
  output = 0
  
  @wires = Array(Int32).new
  
  # wires tracking

  def add_input_wires(inputs : Array(Int32))
    @inputs.each do |iw|
	  @@sl.abort "input wire #{iw} already present" if @@wires.includes?(iw)
	  @wires << iw
	end
  end
  
  def add_wires(inputs : Array(Int32), outputs : Array(Int32))
      @inputs.each do |iw|
        @@sl.abort "input wire #{iw} not found" unless @@wires.includes?(iw)
      end
      outputs.sort.each do |ow|
        @@sl.abort "output wire #{ow} already present" if @@wires.includes?(ow)
        @@sl.abort "a new wire number (#{ow}) should be exactly one more than the previous highest wire number (#{@@wires[-1]})" if @@wires[-1] + 1 != ow
        @wires << ow
      end
  end

  #callback for a new input wire from the circuit
  def input_cb(i)
    @inputs << i
    add_input_wires([i]) 
  end
  
    #callback for a new input wire from the circuit
    def nzikinput_cb(i)
      @nizkinputs << i
      add_input_wires([i])
    end

    def output_wire(stage, o)
      
      output = o
      
      add_wires([] of Int32, [$1.to_i])
    end
    #TODO some array to int conversion in the following functions; e.g i[0] instead of i
    def add(s,a,i)
      @ops << [ :add, a, i ]
    end

    def mul(s,a,i)
      ops << [ :mul, a, i ]
    end
    def const_mul_neg(s,a,b,c)
      ops << [ :const_mul_neg, a,b,c ]
    end
    def const_mul(s,c,a,b)
      ops << [ :const_mul, c, a, b ]
    end
    def split(s,i,a)
      ops << [ :split,i, a ]
    end
    def zerop(s,i,a)
      ops << [ :zerop, i, a ]
    end
end


class CircuitParser


  @slo : SimpleLog?;  

  def initialize ()
    @log = false;
    @callbacks = Hash(::Symbol, (->) | ((Int32)->) | Proc(Int32, UInt32, Nil) | ((Int32, Array(UInt32), Array(UInt32))->) | ((Int32, BigInt, Array(UInt32), Array(UInt32))->) | ((Int32, UInt32, Array(UInt32), Array(UInt32))->)).new;
  end

  def enable_log(l)
    @slo = l;
    @log = true;
  end
  
  def set_callback(op : ::Symbol, cb )#:  (->) |  (Int32, UInt32)->) 
    @callbacks[op] = cb;
  end

 # def set_callback(op : Symbol, cb :  Proc(Int32, UInt32, UInt32))
 #   @callbacks[op] = cb;
 # end

  def callback(op : ::Symbol) #: (->) |  ((Int32, UInt32)->) 
    cb = @callbacks[op]?
    if cb
      return cb.as(->).call();
    end
    return nil;
  end

  def callback(op : ::Symbol, s : Int32)
    cb = @callbacks[op]?
    if cb
      return cb.as((Int32)->).call(s)
    end
  end

  def callback(op : ::Symbol, s : Int32, i : UInt32)
    cb = @callbacks[op]?
    if cb
      return cb.as((Int32, UInt32)->).call(s,i)
    end
  end

  def callback(op : ::Symbol, s : Int32, in : Array(UInt32), ou : Array(UInt32))
    cb = @callbacks[op]?
    if cb
      return cb.as((Int32, Array(UInt32), Array(UInt32))->).call(s, in, ou)
    end
  end

  def callback(op : ::Symbol, s : Int32, a : UInt32, in : Array(UInt32), ou : Array(UInt32))
    cb = @callbacks[op]?
    if cb
      return cb.as((Int32, UInt32, Array(UInt32), Array(UInt32))->).call(s, a, in, ou)
    end
  end

  def callback(op : ::Symbol, s : Int32, a : BigInt, in : Array(UInt32), ou : Array(UInt32))
    cb = @callbacks[op]?
    if cb
      return cb.as((Int32, BigInt, Array(UInt32), Array(UInt32))->).call(s, a, in, ou)
    end
  end


  def log_line(logline)
    if (@log && (sl = @slo) )
      sl.p logline
    end
  end

  def log_abort(err)
    if (@log && (sl = @slo) )
      sl.abort err
    end
  end

  #############################################################################
  #
  # parse input file
  #
  
  # this input file has the structure
  #
  # total (1 line)
  # input
  # nizkinput
  # operations (currently: add mul const-mul-xx const-mul-neg-xx zerop split)
  # output (1 line)
  
  def parse_arithmetic_circuit(file_path)
    stage = 0
    line_count = 0 # count of line_count in input file
    circuit_line_count = 0 # declared line count in first line
    
    ########TOTO plug the input parsing to the gates
    ########### + also generate the r1cs.in and compute the assignements
    File.each_line file_path do |line|
      
    line_count += 1
     log_line "\n** processing line #{line_count} [#{line}]\n"
    line = line.gsub(/\s*#.*$/, "")
      
     ### total
      
    if line =~ /^total (\d+)$/
        
      log_abort "expecting total on first line" if stage > 0
      stage = 1
        
      circuit_line_count = $1.to_i
  
      log_line "   total circuit line_count expected: #{circuit_line_count}"    #TODO is it the number of lines (gates) or the number of wires?
      
      ### input
  
    elsif line =~ /^input (\d+)$/
  
      log_abort "Unexpected input on this line" if stage != 1
      callback(:input_wire, stage, $1.to_u32)

      log_line "   added input wire #{$1.to_i}"
      
  
      ### nizkinputs
      
    elsif line =~ /^nizkinput (\d+)$/
        
      log_abort "Unexpected nizkinput on this line" if stage != 1
      callback(:nzikinput_wire, stage, $1.to_u32)
      log_line "   added nizkinput wire #{$1.to_i}"
  
      ### output
        
    elsif line =~ /^output (\d+)$/
  
      abort "Unexpected output on this line" unless [2, 3].includes?(stage)

      stage = 3
      callback(:out_wire, stage, $1.to_u32)
      log_line "   added output wire #{$1.to_i}"
      
    else    
  
      ### gates
      
      log_abort "Unexpected gate on this line" unless [1, 2].includes?(stage)
  
      if (stage == 1 )
        stage = 2
        callback(:input_done, stage)
      end
  
      stage = 2    
  
      # add
  
      if line =~ /^add in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
    
        ua = Array(UInt32).new
        ua = $2.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of inputs:  #{line} " if ua.size != $1.to_i
        callback(:add, stage, ua, [$3.to_u32]);
  
        log_line "   add #{ua} = #{$3.to_i}"
  
        # mul
        
      elsif line =~ /^mul in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
        
        ua = Array(UInt32).new
        ua = $2.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of inputs:  #{line} " if ua.size != $1.to_i      
        callback(:mul, stage, ua, [$3.to_u32]);
      
        log_line "   mul #{ua} = #{$3.to_i}"
        
        # const-mul-neg-xx
      elsif line =~ /^const-mul-neg-([\dA-Fa-f]+) in 1 <(\d+)> out 1 <(\d+)>$/
        c = $1.to_u64(16) # $1.to_u32
     
        log_line "   const_mul_neg -#{c}_C x #{$2.to_i} = #{$3.to_i}"
        callback(:const_mul_neg, stage, BigInt.new(c), [$2.to_u32], [$3.to_u32])
    
        # const-mul-xx
      elsif line =~ /^const-mul-([\dA-Fa-f]+) in 1 <(\d+)> out 1 <(\d+)>$/
        c = $1.to_u64(16)
    
        log_line "   const_mul #{c}_C x #{$2.to_i} = #{$3.to_i}"
        callback(:const_mul, stage, BigInt.new(c), [$2.to_u32], [$3.to_u32])

        # split
      elsif line =~ /^split in 1 <(\d+)> out (\d+) <([\s\d]+)>$/
        ua = Array(UInt32).new
        ua = $3.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != $2.to_i
     
      
        log_line "   split #{$1.to_i} => #{ua}"
        callback(:split, stage, [$1.to_u32], ua)
  
        # zerop
        
      elsif line =~ /^zerop in 1 <(\d+)> out (\d+) <([\s\d]+)>$/
        a = Array(UInt32).new
        a = $3.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of outputs:  #{line} " if a.size != $2.to_i
      
        log_line "   zerop #{$1.to_i} => #{a}"
        callback(:zerop, stage, [$1.to_u32], a)

        # dload
      elsif line =~ /^dload in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
        ua = Array(UInt32).new
        ua = $2.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != $1.to_i

        log_line "  dload #{$1.to_i} => #{ua}"
        callback(:dload, stage, ua, [$3.to_u32]);    
        
        # divide
      elsif line =~ /^div_(\d+) in (\d+) <([\s\d]+)> out 2 <([\s\d]+)>$/
        ua = Array(UInt32).new
        ua = $3.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != $2.to_i
        ua << $1.to_u32
        uo = Array(UInt32).new
        uo = $4.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != 2
       ## uo << $1.to_u32  ##TODO TEMP HACK
        log_line "  divide #{$2.to_i} => #{ua}"
        callback(:divide, stage, ua, uo); 

        # div
      elsif line =~ /^div in 2 <([\s\d]+)> out 1 <([\s\d]+)>$/
        ua = Array(UInt32).new
        ua = $1.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != 2
        uo = Array(UInt32).new
        uo = $2.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if uo.size != 1
        log_line "  div #{ua} => #{uo}"

        callback(:div, stage, ua, uo); 

        # asplit
      elsif line =~ /^asplit in (\d+) <([\s\d]+)> out (\d+) <([\s\d]+)>$/
        ua = Array(UInt32).new
        ua = $2.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != $1.to_i
        uo = Array(UInt32).new
        uo = $4.split.map{ |x| x.to_u32 }
        log_abort "Inconsistent number of wires:  #{line} " if ua.size != $3.to_i
        log_line "  asplit #{$2.to_i} => #{ua}"
        callback(:asplit, stage, ua, uo); 

        # unknown gate #
      else
        #ops << [ :imlost ] #TODO add a unknown operation callback to the circuit checker
    
        log_line "unknown operation"
      
      end
    
    end
        
  end   ##file.each
    

    ## total is nulber of lines or number of wires?? @@sl.abort "Line number panic. Expected #{circuit_line_count}, found #{line_count - 1} " if circuit_line_count != line_count - 1
    callback(:done)
    

  end

  
end
  
 
  
  
end