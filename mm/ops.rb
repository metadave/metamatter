#
#    MetaMatter
#    Copyright (C) 2009 Dave Parfitt
# 
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
# 
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
# 
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require 'rubygems'
gem 'dbi'
require 'dbi'


module MM
###############################################################################
#
# OPS
#
###############################################################################
# need to iterate over these and try to come up with a small set that makes sense!


# might want to rethink this class
class Init < Op
  input :initin, :echo
  output :initout
  config :message

  def initialize
    super
    @message = "Foo"	
  end
  
  def starting
    initout.out(@message)
  end
  
  def echo(value)
    initout.out(value)
  end
end

class DummyTable < Op
  input :dummyin, :din
  output :dummyout
  
  def starting    
    data = []
    1.upto(10) do |i|      
      row = []
      1.upto(10) do |j|
        row << j
      end
      data << row      
    end
       
    @dummyout.out(data)
  end
      
  def din    
  end
end

class Print < Op
  input :printin, :print
  output :printout 
  config :fd
  config :prefix # couldn't resist even though
  # there should really be an op like "prepend"
  
  def initialize
    super
    @prefix = ""   
    @fd = STDOUT
  end
  
  def print(value)
    @fd.puts "#{prefix}#{value}"   
    printout.out(value)
  end
  
  def stopping
    # hmmmm ... what to do about closing FDs?
    #if @fd != STDOUT then
    #@fd.close
    #end
  end
end


class Gate < Op
  input :gatein, :valuein
  output :gateout
  
  def initialize
    super()
    @queues = {}   
    @queueorder = []
    @windowsize = 0
  end
  
  def valuein(value)
    #nop-> it's all done in receivedpacket
  end
  
  def receivedpacket(packet)
    if packet.destinput == "valuein"    
      #puts "Gate received a packet from #{packet.sourceoutput}"
      @queues[packet.sourceoutput].push packet.value
      while windowfull
        gatefull
      end
    end
  end
  
  def windowfull
    count = 0
    @queues.each_pair do |conn,q|
      if q.size > 0
        count += 1
      end
    end
    if count == @windowsize
      true
    else
      false
    end
  end
  
  def gatefull
    values = []
    @queueorder.each do |key|   
      list = @queues[key]
      values << list.shift
    end
    #puts "Gate is releasing a packet: #{values}"
    gateout.out values   
  end
  
  def connectedto(output)   
    @queueorder << output
    @queues[output] = Array.new
    @windowsize += 1
    #puts "Added gate queue"
  end
end



class If < Op
  config :predicate
  input :ifin, :doif
  output :ifouttrue
  output :ifoutfalse
  
  def initialize
    super
    @predicate = 'not value.nil?'
  end
  
  def doif(value)   
    s = "#{predicate}"           
    result = instance_eval(s)
    
    if result == true           
      ifouttrue.out value
    else     
      ifoutfalse.out value
    end
  end
end


class TextTemplate < Op
  config :template
  input :valuesin, :rendertemplate
  input :templatein, :template
  output :templateout
  
  def initialize
    super
    @template = '#{value}'
  end
  
  def rendertemplate(value)       
    s = instance_eval('"' + @template + '"')
    templateout.out(s) 
  end
  
end

class Join < Op
  input :joinin, :dojoin
  output :joinout
  config :joinchar
  
  def initialize
    super
    @joinchar = ","
  end
  
  def dojoin(value)  
    joinout.out value.to_a.join(@joinchar)
  end
end

class Split < Op
  input :splitin, :dosplit
  output :splitout
  config :splitchar
  
  def initialize
    super
    @splitchar = ","
  end
  
  def dosplit(value)    
    splitout.out value.to_s.split(@splitchar)
  end
end

# swiss army knife type op
class Mod < Op
  input :modin, :mod
  output :modout
  config :code
  
  def initialize
    super
    @code = ""
  end
  
  def mod(value)
    modout.out(instance_eval(@code))
  end
end


class Each < Op
  input :eachin, :doeach
  output :eachout
  output :eof

  def doeach(value)
    puts "EACH: #{value}"

    value.to_a.each do |item|
      eachout.out(item)
    end
    eof.out("eof")
  end
end


class EachPair < Op
  input :eachin, :doeach
  output :eachout
  output :eof

  def doeach(value)
    puts "EACH: #{value}"
    
    value.each_pair do |k,v|
      eachout.out(item)
    end
    eof.out("eof")
  end
end

class Buffer < Op
  input :bufferin, :doin
  input :trigger, :dotrigger
  output :bufferout
    
  def initialize
    super
    @buf = Array.new
  end
  
  def doin(value)
    @buf << value
  end
  
  def dotrigger(value)    
    bufferout.out(@buf.clone)
    @buf.clear
  end

end


# probably not going to use this
# class PipeOut < Op
#   input :datain, :dodatain
  
#   def starting    
#     @network.pipesout[self.opid] = Array.new()
#   end
  
#   def dodatain(value)
#     @network.pipesout[self.opid] << value
#   end
# end



# need to spit out db metadata also!
# should probably pass around the db connection?
# need a way to manage resources (open + close things like files, db connections etc)
class DBQuery < Op
  input :sql, :runsql
  output :rowout

  output :metadataout
  output :rowcountout
  output :colcountout #redundant
  output :columnnames 
  output :eof
  
  config :username
  config :password
  config :connstr

  def initialize
    super
    @username="root"
    @password=""
    @connstr="DBI:Mysql:ub"
  end

  def starting
    puts "DB connect"
    puts "connstr = [#{@connstr}"
    @dbh=DBI.connect(@connstr,@username,@password)
  end

  def stopping
    puts "DB disconnect"
    @dbh.disconnect
  end

  def runsql(value)   
    results = @dbh.execute(value)
    rowcount = 0
    results.each do |row|
      rowout.out(row)
      rowcount += 1
    end
    rowcountout.out(rowcount)
    colcountout.out(results.column_names.size)
    metadataout.out(results.column_info)
    columnnames.out(results.column_names)
    eof.out("eof")
  end
end


end #module
