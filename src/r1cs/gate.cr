require "big.cr"
require "json"
require "./r1cs.cr"
require "./circuit_parser.cr"


module Isekai


class LinearCombination
    def initialize
        @lc = Array(Tuple(UInt32,BigInt)).new
       
    end

    def initialize(lc : Array(Tuple(UInt32,BigInt)))
        @lc = lc;
    end

    def add(lc : LinearCombination, prime : BigInt)
        add(lc.@lc, prime)
    end

    def add(lc : Array(Tuple(UInt32,BigInt)), prime : BigInt)
        #WARNING - We suppose both are ordered!
        result = Array(Tuple(UInt32,BigInt)).new
        i1 = 0; 
        i2 = 0
        while (i1 < @lc.size && i2 < lc.size)
            if (@lc[i1][0] < lc[i2][0])
                result << @lc[i1]
                i1 +=1;
            elsif((@lc[i1][0] > lc[i2][0]))
                result << lc[i2]
                i2 +=1;
            else
                #addition
                @lc[i1] = {lc[i2][0], (lc[i2][1] + @lc[i1][1]).modulo(prime)};       ##I don't know how to update only lc[i2][1]..
                result << @lc[i1]
                i2 +=1;
                i1 +=1;
            end
        end
        while (i1 < @lc.size)
            result << @lc[i1]
            i1 +=1;
        end
        while (i2 < lc.size)
            result << lc[i2]
            i2 +=1;
        end
        @lc = result;
    end

    def multiply(scalar : BigInt, prime : BigInt)
        newlc = Array(Tuple(UInt32,BigInt)).new
        @lc.each do |item|
            newlc << {item[0], (item[1] * scalar).modulo(prime)}; #
        end
        @lc = newlc ##should update @lc in-place!
    end

    def multiply_lc(lc : Array(Tuple(UInt32,BigInt)), scalar : BigInt, prime : BigInt)
        lc.each do |item|
            @lc << {item[0], (item[1] * scalar).modulo(prime)};
        end
    end

end

class InternalVar
    @val : BigInt;
    @expression : LinearCombination;
    @witness_idx : UInt32 | Nil;
    property witness_idx : UInt32 | Nil;

    def initialize
        @val = BigInt.new(0);
        @expression = LinearCombination.new();
        @witness_idx = nil;
    end

    def initialize(expression, value, widx : UInt32| Nil)
        @val = value;
        @expression = expression;
        @witness_idx = widx;
    end

end


class GateKeeper

    @prime_field : BigInt;

    def initialize(@arithName : String, @arithInputs : String, @j1csName : String, internals : Hash(UInt32,InternalVar), @zkp = ZKP::Snark)
        @r1csFile =  File.new(j1csName, "w");
        @internalCache = internals;
        @witness_idx = Array(UInt32).new();     ##TODO this structure will become too big, but we probably can keep only the last elements, as with internalCache.    witness_idx[i] = w means that wire w has index i (correspond to variable xi in the r1cs)
        @inputs_nb = 0_u32;
        @nzik_nb = 0_u32;
        @output_nb = 0_u32;
        @constraint_nb = 0;
        @witness_nb = 0;
        @invalid_wire = UInt32::MAX;
        case @zkp
        when .dalek?
            @prime_field  = BigInt.new(2)**252 + BigInt.new("27742317777372353535851937790883648493")  ##Bullet proof
    #    when .aurora?
    #        @prime_field = BigInt.new("1552511030102430251236801561344621993261920897571225601");       ##edwards curve
        else ##when .snark? , .libsnark?
            @prime_field  = BigInt.new("21888242871839275222246405745257275088548364400416034343698204186575808495617")  ##libsnark bn128
        end

        @cur_idx = 0_u32;
        
        @j1cs = nil;
        @previous_stage = 0;        ##Stage of the circuit parsing
    end

    #def log_me(l : SimpleLog)
    #    @log = l;
    #end


    def writeToJ1CS(str : String)
        @r1csFile.print("#{str}\n")
    end

    def write_assignements
        str = inputs_to_json();
        ff = File.new("#{@j1csName}.in", "w");   
        ff.print("#{str}")
        ff.close();
    end

    #Overwrite the header. To be called after the second pass when the header has already been written once to the file
    def update_header
        s = j1cs_helper().json_header(@constraint_nb, @prime_field, @inputs_nb-1+ @output_nb, @witness_nb + @nzik_nb)    
        io = IO::Memory.new s
        slice = Bytes.new(s.size)
        io.read(slice)
        f = File.open(@j1csName, mode = "r+")
            f.write slice
        f.close
    end

    def read_ari_input_values (source_filename) : Array(BigInt)
        #filename = "#{source_filename}.in"
        values = [] of BigInt
        if File.exists?(source_filename)
            File.each_line(source_filename) do |line|
                str_val = line.split
                if str_val.size() != 2
                    pp "Error reading input values"
                end
                values << str_val[1].to_u64(16).to_big_i 
            end
        end
        return values
    end

    def process_circuit
        first_pass();
        main_pass();
    end

    def first_pass
        cp = CircuitParser.new();
        #if (@log)
        #    cp.enable_log(@log); #TODO
        #end

        in_values = read_ari_input_values(@arithInputs) #load inputs from .ari.in file

        cp.set_callback(:input_wire, ->(s : Int32, w : UInt32) 
        {
            @internalCache[w] = InternalVar.new(LinearCombination.new([{w, BigInt.new(1)}]), in_values[w],(w+1).to_u32);  
            @inputs_nb += 1
            return
        })
        cp.set_callback(:nzikinput_wire, ->(s : Int32, w : UInt32)  
        {
        
            @nzik_nb += 1
            return
        })
        cp.set_callback(:out_wire, ->(s : Int32, w : UInt32) 
        {
            #map output wire and its r1cs index
            @internalCache[w] = InternalVar.new(LinearCombination.new([{w, BigInt.new(1)}]), BigInt.new(0), @inputs_nb + @output_nb);
            @output_nb += 1;
            return
        })


        cp.set_callback(:mul, ->(s : Int32, i : Array(UInt32), o : Array(UInt32))
        {
            ## mul gate can now be optimized, somtimes there will not be new constraints. These numbers will be updated after the second pass.
            @constraint_nb += 1;
            @witness_nb += 1;
            return;
        });

        cp.set_callback(:split, ->(s : Int32, i:  Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += o.size() + 1;
            @witness_nb += o.size();
            return;
        });

        cp.set_callback(:dload, ->(s : Int32, i:  Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += i.size() *2 + 1;
            @witness_nb += (i.size()-1) *2 + o.size();
            return;
        });

        cp.set_callback(:divide, ->(s : Int32, i:  Array(UInt32), o : Array(UInt32))
        {
            bitwidth = i[2].to_i32
            @constraint_nb += 2 + bitwidth
            @witness_nb += 2+ bitwidth    
            return;
        });

        cp.set_callback(:div, ->(s : Int32, i:  Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += 1
            @witness_nb += 1   
            return;
        });

        cp.set_callback(:zerop, ->(s : Int32, i : Array(UInt32), o : Array(UInt32))
        {
            @constraint_nb += 2;
            @witness_nb += 2;
            return;
        });
    
        cp.parse_arithmetic_circuit(@arithName)
        @internalCache[@inputs_nb-1] = InternalVar.new(LinearCombination.new([{@inputs_nb-1, BigInt.new(1)}]), BigInt.new(1), 0_u32);       #One Constant

        #nzik inputs must be set after the ouputs
        (@inputs_nb..@inputs_nb+@nzik_nb-1).each do |i|
            @internalCache[i] = InternalVar.new(LinearCombination.new([{i.to_u32, BigInt.new(1)}]), in_values[i],(i+@output_nb).to_u32);     
        end
        @witness_nb = @witness_nb - @output_nb;     #outputs are always multiplied by 1 during the output-cat at the end (dummy multiplication by1)
        @cur_idx = @inputs_nb+@nzik_nb+@output_nb;          
    end

    def main_pass
        pp "translating constraints"
        @stage = 0;
        ##load_inputs(@arithName);
        header = j1cs_helper().json_header(@constraint_nb, @prime_field, @inputs_nb-1+ @output_nb, @witness_nb + @nzik_nb)    
        writeToJ1CS(header)    #Write the r1cs header in the file
        @constraint_nb = 0; #We are counting again, but with correct number for mul gate this time
        @witness_nb = 0;
        cp = CircuitParser.new();
        #cp.enable_log(@log);       #TODO 

        cp.set_callback(:add, ->add(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:mul, ->mul(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:const_mul, ->constMul(Int32, BigInt, Array(UInt32),  Array(UInt32)));
        cp.set_callback(:const_mul_neg, ->constMulNeg(Int32,  BigInt, Array(UInt32),  Array(UInt32)));
        cp.set_callback(:split, ->split(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:dload, ->dload(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:asplit, ->asplit(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:divide, ->divide(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:div, ->div(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:zerop, ->zerop(Int32,  Array(UInt32),  Array(UInt32)));
        cp.set_callback(:done, ->
        {
            @r1csFile.close();
            write_assignements();
            return;
        })
        cp.parse_arithmetic_circuit(@arithName)
        @witness_nb = @witness_nb - @output_nb;     #outputs are always multiplied by 1 during the output-cat at the end (dummy multiplication by 1)
        update_header();
        if @cur_idx-@inputs_nb-@output_nb != @witness_nb + @nzik_nb
            pp "WARNING - inconsistent witness value #{@cur_idx-@inputs_nb-@output_nb}"
        end
    end



    def set_witness(val : BigInt) : UInt32
        wire = @invalid_wire
        set_witness(wire, val, false);
        @invalid_wire = @invalid_wire -1
        return wire
    end

    def set_witness(wire : UInt32, val : BigInt, check = false)
        #we check for an existing wire only when 'check' is true, may be this optimization is not worth, the idea is only outputs should already be in the cache and outputs should come from a mul gate
        #it would be also better to check only when the wire is greater than the first output...TODO
        if (check)
            v = @internalCache[wire]?
            if (v)
                var_idx = @internalCache[wire].@witness_idx
                @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, var_idx);       #why can't we simply update elements of an hash_map?
                return;
            end
        end
        @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, @cur_idx);
        @cur_idx += 1;
    
       # if wire < @out_wire    
       #     @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, @cur_idx);
       #     @cur_idx += 1;
       # else
       #     var_idx = @internalCache[wire].@witness_idx
       #     @internalCache[wire] = InternalVar.new(LinearCombination.new([{wire, BigInt.new(1)}]), val, var_idx);
       # end
    end

    def j1cs_helper
        if (!@j1cs)
            @j1cs = R1CS.new(32)  #it is not the value defined in isekai.cr, but I don't think we need it there   
            @j1cs.not_nil!.set_gate(self);
        end
        return @j1cs.not_nil!
    end

    def resetIdx
        @cur_idx = @inputs_nb
    end

    #TODO to change if we support negative indexes
    #This function returns the witness index (in the R1CS) corresponding to the wire (in the circuit)
    #Cf. wire mappings in the documentation -TODO
    def getWireIdx(wire : UInt32) : UInt32  
        if @internalCache.has_key? wire
            if w = @internalCache[wire].@witness_idx
                return w
            end
        end
        ##UInt32::MAX is used for internal witness variables having NO wire. THEY should be never retrieved!!!
        raise Exception.new("wire #{wire} not found"); 
    end

    #When a gate does not generate a multiplication, the output wires of the gate can be expressed as a linear combination of the inputs. In that case, each time such wire will be used, we can subtitute it with the linear combination.
    #This function stores the substitution in the cache
    def substitute(wire : UInt32)
        if @internalCache.has_key? wire
            return @internalCache[wire];
        end
        pp "n.b: wire #{wire} not found in the cache"
        lc = LinearCombination.new([{wire, BigInt.new(1)}]);
        return InternalVar.new(lc, BigInt.new(0), nil);
    end

    #Returns the wire representing the one-constant (for Pinocchio circuits). It should be mapped to variable x0
    def one_constant
        return  [{@inputs_nb-1, BigInt.new(1)}]
    end

    def is_const(expr : LinearCombination)
        if (expr.@lc.size == 1 && expr.@lc[0][0] == @inputs_nb-1)
            return true;
        end
        return false;
    end

    def scalar(c : Int32)
        return {@inputs_nb-1, BigInt.new(c).modulo(@prime_field)}
    end

    ## construct the json string of the R1CS inputs and witnesses, from the cache
    def inputs_to_json()
        
        inputs = Array(String).new
        witnesses = Array(String).new
        @internalCache.each_value do |var|
            if (w = var.@witness_idx) 
                if w>0
                    if (w< @inputs_nb+@output_nb )
                        inputs << var.@val.to_s
                        #DEBUG pp "input_#{w} idx:#{var.@witness_idx} value: #{var.@val}"
                    else
                        witnesses << var.@val.to_s
                        #DEBUG pp "witnesses_#{w} idx:#{var.@witness_idx} value: #{var.@val}"
                    end
                end
            end
        end
    
        str_res =  @j1cs.not_nil!.inputs_to_json(inputs,witnesses);
        return str_res + "\n" + @j1cs.not_nil!.decomplement_json(inputs, @inputs_nb-1)
    end


    #Addition gate
    def add(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        lc = LinearCombination.new();
        val = BigInt.new(0);
        in_wires.each do |wire|
            cache = substitute(wire)
           
            lc.add(cache.@expression, @prime_field);
    
            val = (val+cache.@val).modulo(@prime_field);
        end
        @internalCache[out_wires[0]] =  InternalVar.new(lc, val.modulo(@prime_field), nil); 
        #DEBUG:
        #if (evaluate(lc.@lc) != val)
        #    pp "addition error for wirea #{in_wires} - found #{evaluate(lc.@lc)} but computed #{val}"
        #end
        return;
    end



    ## Multiplication gate
    def mul(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        #We suppose there are only 2 input wires
        cache1 = substitute(in_wires[0])
        cache2 = substitute(in_wires[1])
        val = cache1.@val * cache2.@val; 

        if (is_const([] of InternalVar, out_wires))
            lc = LinearCombination.new();
            #we optimize constant inputs
            if (is_const(cache1.@expression))
                lc.multiply_lc(cache2.@expression.@lc, cache1.@expression.@lc[0][1], @prime_field);
                @internalCache[out_wires[0]] =  InternalVar.new(lc, val.modulo(@prime_field), nil); 
                return;
            else
                if (is_const(cache2.@expression))
                    lc.multiply_lc(cache1.@expression.@lc, cache2.@expression.@lc[0][1], @prime_field);
                    @internalCache[out_wires[0]] =  InternalVar.new(lc, val.modulo(@prime_field), nil); 
                    return;
                end
            end
        end

        @constraint_nb += 1;
        @witness_nb += 1;     
        set_witness(out_wires[0], val.modulo(@prime_field), true)
        str_res = @j1cs.not_nil!.to_json_str(cache1.@expression.@lc, cache2.@expression.@lc,  [{out_wires[0], BigInt.new(1)}])
        #DEBUG:  satisfy(cache1.@expression.@lc, cache2.@expression.@lc,  [{out_wires[0], BigInt.new(1)}])
        writeToJ1CS(str_res);   
        return;
    end

    def constMul(s : Int32, scalar : BigInt, in_wires : Array, out_wires : Array)
        @stage = s;
        cache = substitute(in_wires[0]);
        llc = LinearCombination.new();
        llc.multiply_lc(cache.@expression.@lc, scalar, @prime_field);
      
        @internalCache[out_wires[0]] = InternalVar.new(llc,  (scalar*cache.@val).modulo(@prime_field), nil);
        #DEBUG
        #if (evaluate(llc.@lc) != (scalar*cache.@val).modulo(@prime_field))
        #    pp "const-mul-.. error for wire #{in_wires}"
        #end
        return;
    end

    def constMulNeg(s : Int32, scalar : BigInt, in_wires : Array, out_wires : Array)
        return constMul(s, -scalar, in_wires, out_wires)
    end

    def zerop(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        cache = substitute(in_wires[0]);
        @constraint_nb += 2;
        @witness_nb += 2;
        ##compute outputs
        val0, val1 =  BigInt.new(0),  BigInt.new(0);
        if (cache.@val != BigInt.new(0))
            val1 = BigInt.new(1);     
            val0 = Maths.new().modulo_inverse(cache.@val, @prime_field);     #TODO   #static method??
        end
        set_witness(out_wires[0], val0);
        set_witness(out_wires[1], val1);

        str_res = j1cs_helper().to_json_str(cache.@expression.@lc, [{ out_wires[0], BigInt.new(1)}], [{ out_wires[1], BigInt.new(1)}])
        #DEBUG:  satisfy(cache.@expression.@lc, [{ out_wires[0], BigInt.new(1)}], [{ out_wires[1], BigInt.new(1)}])
        writeToJ1CS(str_res);  

        str_res = j1cs_helper().to_json_str(cache.@expression.@lc, [{ out_wires[1], BigInt.new(1)}], cache.@expression.@lc)
        writeToJ1CS(str_res);  
        return;
    end

    def is_const( in_lc : Array, out_wires : Array)
        out_wires.each do |o|
            v = @internalCache[o]?
            if (v)
               return false; #if the wire is already in the cache, it must be an output
            end
        end
        in_lc.each do |i_lc|
            if !(is_const(i_lc.@expression))
                return false;
            end
        end
        return true;
    end


    def div(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        cache_a = substitute(in_wires[0]);
        cache_b = substitute(in_wires[1]);
        #TODO: should we ensure b is not null with an additional constraint?
        if (cache_b.@val == BigInt.new(0))
            raise "Invalid value divide by zero @wire #{in_wires[1]}"
        end
        # compute out = a*b^-1
        inv_b =  Maths.new().modulo_inverse(cache_b.@val, @prime_field);
        val = cache_a.@val * inv_b;
        val = val.modulo(@prime_field);

        ##optimize division by constant
        if (is_const([cache_b], out_wires))
            pp "const optim"
            lc = LinearCombination.new();
            #we optimize constant inputs
            lc.multiply_lc(cache_a.@expression.@lc, inv_b, @prime_field);
            @internalCache[out_wires[0]] =  InternalVar.new(lc, val.modulo(@prime_field), nil); 
            return;
        end

        #constrain out*b = a
        @constraint_nb += 1;
        @witness_nb += 1;    
        set_witness(out_wires[0], val);
        str_res = j1cs_helper().to_json_str([{out_wires[0], BigInt.new(1)}], cache_b.@expression.@lc, cache_a.@expression.@lc)
        writeToJ1CS(str_res); 
    end

    def divide(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        bitwidth = in_wires[2].to_i32           ##it is not nice to use the list of wires to pass the bits width... 
        cache_a = substitute(in_wires[0]);
        cache_b = substitute(in_wires[1]);
        @constraint_nb += 1;
        @witness_nb += 2;
        val_q = cache_a.@val // cache_b.@val;   ##TODO should we check divide by 0?
        val_r = cache_a.@val - val_q*cache_b.@val;
        set_witness(out_wires[0], val_q);
        set_witness(out_wires[1], val_r);
        #a-r = q*b                              ##TODO if b is const, we can save one constraint
        lc = LinearCombination.new();
        lc.add(cache_a.@expression.@lc, @prime_field);
        lc.add([{out_wires[1], @prime_field + BigInt.new(-1)}], @prime_field)
        str_res = j1cs_helper().to_json_str([{out_wires[0], BigInt.new(1)}], cache_b.@expression.@lc, lc.@lc)
        writeToJ1CS(str_res); 
        #q is 32 bits
        new_split(out_wires[0], bitwidth)
        #b-r > 0
        if (val_r > cache_b.@val)
            raise "invalid remainder for wire #{out_wires[1]}"
        end
        var_r = InternalVar.new(LinearCombination.new([{out_wires[1], BigInt.new(1)}]), val_r, nil)
        compare(var_r, cache_b, bitwidth, false);
        return;
    end

    #a<b or b>=a
    def compare(a : InternalVar, b : InternalVar, width : Int32, signed : Bool)
        bitwidth = width
        if (!signed)
            bitwidth = bitwidth + 1
        end
        cmp_lc = LinearCombination.new();
        cmp_lc.add(a.@expression, @prime_field);
        minus = BigInt.new(1)**(bitwidth) - BigInt.new(1);
        b_lc = LinearCombination.new();
        b_lc.multiply_lc(b.@expression.@lc, minus, @prime_field);
        cmp_lc.add(b_lc, @prime_field);
        val = (a.@val  + minus*b.@val).modulo(@prime_field);
        a_lc = split_compare(val, width, signed)
        str_res = j1cs_helper().to_json_str(a_lc, one_constant, cmp_lc.@lc)
        writeToJ1CS(str_res); 
        @constraint_nb = @constraint_nb + 1
 
    end


    #prepare constraints that state a<b or a>=b
    def split_compare( val : BigInt, width : Int32, signed : Bool)
        bitwidth = 2 * width
        bitset = width
        if (signed)
            bitwidth = bitwidth -1
            bitset = bitset -1
        end
        @constraint_nb = @constraint_nb + bitwidth-1
        @witness_nb = @witness_nb +  bitwidth -1
        a_lc = Array(Tuple(UInt32, BigInt)).new;
        e = BigInt.new(1);      
        w : UInt32 = 0_u32
        (0..bitwidth-1).each do |i|
            w_val = val.bit(i).to_big_i;
            if (i != bitset)
                w = set_witness(w_val)
                a_lc << {w, e}
                str_res = j1cs_helper().to_json_str([{w, BigInt.new(1)}], [{w, BigInt.new(1)}], [{w, BigInt.new(1)}])
                writeToJ1CS(str_res);
            else
                a_lc << {@inputs_nb-1,e*w_val}
            end
            e = e * 2;
        end
        return a_lc;
    end
    
    def new_split(in_wire : UInt32, bitwidth : Int32)
        cache = substitute(in_wire)
        new_split(cache.@val, cache.@expression, bitwidth)
    end

    def pre_split(val : BigInt, bitwidth : Int32) : Array(Tuple(UInt32, BigInt))
        a_lc = Array(Tuple(UInt32, BigInt)).new;
        e = BigInt.new(1);      
        w : UInt32 = 0_u32
        (0..bitwidth-1).each do |i|
            w_val = val.bit(i).to_big_i;
            w = set_witness(w_val)
            a_lc << {w, e}
            e = e * 2;
            str_res = j1cs_helper().to_json_str([{w, BigInt.new(1)}], [{w, BigInt.new(1)}], [{w, BigInt.new(1)}])
            writeToJ1CS(str_res);
        end
        return a_lc;
    end


    def new_split(val : BigInt, expr : LinearCombination, bitwidth : Int32)
        a_lc = Array(Tuple(UInt32, BigInt)).new;
        e = BigInt.new(1);
       
        s_value = BigInt.new(0);
        w : UInt32 = 0_u32
        (0..bitwidth-1).each do |i|
            w_val = val.bit(i).to_big_i;
            w = set_witness(w_val)
            s_value = s_value + w_val * e;
            a_lc << {w, e}
            e = e * 2;
            str_res = j1cs_helper().to_json_str([{w, BigInt.new(1)}], [{w, BigInt.new(1)}], [{w, BigInt.new(1)}])
            writeToJ1CS(str_res);
        end
        str_res = j1cs_helper().to_json_str(a_lc, one_constant, expr.@lc)
        writeToJ1CS(str_res); 
        @constraint_nb = @constraint_nb + bitwidth+1
        @witness_nb = @witness_nb +  bitwidth 
    end

    def not_null(in_val : BigInt, expr : Array(Tuple(UInt32, BigInt)))
        if (in_val == BigInt.new(0))
            raise "Error - value should not be null"
        end   
        m_val = Maths.new().modulo_inverse(in_val, @prime_field); 
        m = set_witness(m_val)
        str_res = j1cs_helper().to_json_str(expr, [{m, BigInt.new(1)}], one_constant)
        writeToJ1CS(str_res);
    end


    def asplit(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        cache_b = substitute(in_wires[0]);
        n = out_wires.size();
        @constraint_nb += n + 2;
        @witness_nb += n;
        if (cache_b.@val >= n)
            raise "ERROR - index too big (#{cache_b.@val} > #{n-1})"
        end
        #dirac constraints: d1...dn
        var0 = Array(Tuple(UInt32, BigInt)).new;
        var1 = Array(Tuple(UInt32, BigInt)).new;
        (0..n-1).each do |i|
            if (cache_b.@val != i)
                set_witness(out_wires[i], BigInt.new(0));
            else
                set_witness(out_wires[i], BigInt.new(1));
            end
            str_res = j1cs_helper().to_json_str([{out_wires[i], BigInt.new(1)}], [{out_wires[i], BigInt.new(1)}], [{out_wires[i], BigInt.new(1)}])
            var0 << { out_wires[i],  BigInt.new(1) }
            var1 << { out_wires[i],  BigInt.new(i) }
            writeToJ1CS(str_res);  
        end
        
        # sum di = 1
        str_res = j1cs_helper().to_json_str(one_constant, var0, one_constant)
        writeToJ1CS(str_res); 
        # b = sum i*di
        str_res = j1cs_helper().to_json_str(one_constant, var1, cache_b.@expression.@lc)
        writeToJ1CS(str_res); 
    end

    def dload(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        cache_b = substitute(in_wires[0]);
        n = in_wires.size();
        @constraint_nb += n*2 + 1;
        @witness_nb += (n-1) *2 + out_wires.size();
        if (cache_b.@val >= n-1)
            raise "ERROR - index too big (#{cache_b.@val} > #{n-2})"
        end
        #dirac constraints
        #dirac variables have no wire, they should come an asplit gate instead..
        #but it's ok as they are not re-used after.
        #d1...dn
        d_idx = @invalid_wire;
        var0 = Array(Tuple(UInt32, BigInt)).new;
        var1 = Array(Tuple(UInt32, BigInt)).new;
        (1..n-1).each do |i|
            if (cache_b.@val != i-1)
                set_witness(BigInt.new(0));
            else
                set_witness(BigInt.new(1));
            end
            str_res = j1cs_helper().to_json_str_raw([{@cur_idx-1, BigInt.new(1)}], [{@cur_idx-1, BigInt.new(1)}], [{@cur_idx-1, BigInt.new(1)}])
            var0 << { @cur_idx -1,  BigInt.new(1) }
            var1 << { @invalid_wire +1,  BigInt.new(i-1) }
            writeToJ1CS(str_res);  
        end
        
        # sum di = 1
        str_res = j1cs_helper().to_json_str_raw([{0_u32, BigInt.new(1)}], var0, [{0_u32, BigInt.new(1)}])
        writeToJ1CS(str_res); 
        # b = sum i*di
        str_res = j1cs_helper().to_json_str(one_constant, var1, cache_b.@expression.@lc)
        writeToJ1CS(str_res); 
        # ci = ai*di
        var2 = Array(Tuple(UInt32, BigInt)).new;
        out_val = BigInt.new(0);
        (1..n-1).each do |i|
            cache_i = substitute(in_wires[i]);
            if (cache_b.@val != i-1)
                set_witness(BigInt.new(0));
            else
                set_witness(cache_i.@val);
                out_val = cache_i.@val
            end
            str_res = j1cs_helper().to_json_str(cache_i.@expression.@lc, [{d_idx-i+1, BigInt.new(1)}], [{@invalid_wire+1, BigInt.new(1)}])
            var2 << { @cur_idx-1 ,  BigInt.new(1) }
            writeToJ1CS(str_res);
        end
        # out = sum ci
        set_witness(out_wires[0], out_val); 
        str_res = j1cs_helper().to_json_str_raw([{0_u32, BigInt.new(1)}], var2, [{ @cur_idx-1, BigInt.new(1)}])
        writeToJ1CS(str_res); 
        #.todo we can probably reduce the nb of constraints
        return;
    end

    
    def split(s : Int32, in_wires : Array, out_wires : Array)
        @stage = s;
        @constraint_nb += out_wires.size() + 1;
        @witness_nb += out_wires.size();
        a_lc = Array(Tuple(UInt32, BigInt)).new;
        s = out_wires.size;
        e = BigInt.new(1);
        (0..s-1).each do |i|
            a_lc << {out_wires[i], e}
            e = e * 2;
        end
        cache = substitute(in_wires[0])
        #compute outputs
         (0..s-1).each do |i|
            set_witness(out_wires[i], cache.@val.bit(i).to_big_i)
         end       
        
        (0..s-1).each do |i| 
            if @zkp.libsnark?
                str_res = j1cs_helper().to_json_str([{out_wires[i], BigInt.new(1)}], [ scalar(-1), {out_wires[i], BigInt.new(1)}], [scalar(0)])        ##libsnark style
            else
                str_res = j1cs_helper().to_json_str([{out_wires[i], BigInt.new(1)}], [{out_wires[i], BigInt.new(1)}], [{out_wires[i], BigInt.new(1)}])
            end
            #DEBUG satisfy([{out_wires[i], BigInt.new(1)}], [ scalar(-1), {out_wires[i], BigInt.new(1)}], [scalar(0)])   
            writeToJ1CS(str_res);
        end
        if @zkp.libsnark?
            str_res = j1cs_helper().to_json_str(cache.@expression.@lc, one_constant, a_lc)                       ##libsnark style
        else
            str_res = j1cs_helper().to_json_str(a_lc, one_constant, cache.@expression.@lc)
        end
        #DEBUG satisfy(cache.@expression.@lc, one_constant, a_lc))
        writeToJ1CS(str_res);  
        
        return;
    end

    def join(in_wires : Array, out_wires : Array)
        a_lc = LinearCombination.new;
        s = in_wires.size;
        e = BigInt.new(1);
        val = BigInt.new(0);
        (0..s-1).each do |i|
            cache = substitute(in_wires[i])
            a_lc.add(cache.@expression.multiply(e));
            val += e*cache.@val
            e = e * 2;
        end
        set_witness(out_wires[0], val.modulo(@prime_field))
        str_res = j1cs_helper().to_json_str(a_lc.@lc, [{@inputs_nb-1, BigInt.new(1)}], [{out_wires[0],  BigInt.new(1)}])
        writeToJ1CS(str_res);
    end

    ########################################
    ### DEBUG helpers ######################
    def evaluate(lc : Array(Tuple(UInt32,BigInt)))
        result = BigInt.new(0);
        lc.each do |item|
            result += substitute(item[0]).@val * item[1];
        end
        return result.modulo(@prime_field);
    end

    def satisfy(a : Array(Tuple(UInt32,BigInt)), b : Array(Tuple(UInt32,BigInt)),  c : Array(Tuple(UInt32,BigInt)))
        if ( (evaluate(a)*evaluate(b)-evaluate(c)).modulo(@prime_field) == BigInt.new(0) )
            return true
        end
        pp "NOT SATIISFIED!!"
        return false;
    end
end


end