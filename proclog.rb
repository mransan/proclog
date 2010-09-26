#!/usr/bin/ruby  -w

require 'yaml'
  
class ProcLog
    
  PIPE_DIR  = "/tmp/" 
  PIPE_EXT  = ".fifo"
    
  def self.pipe_name_for child_name
    pipe_name = PIPE_DIR + child_name + PIPE_EXT 
  end 
  
  def self.pipe_exist? child_name
    return File::pipe? pipe_name_for child_name
  end
  
  def self.create_pipe child_name 
      
    pipe_name = pipe_name_for child_name  
    if not pipe_exist? child_name
      mk_pipe = "mkfifo #{pipe_name}" 
      
      unless Kernel.system(mk_pipe)
        throw "Error creating pipe #{pipe_name}"
      end
    end
            
    return File::open(pipe_name, "r+")
  end 
  
  def initialize 
    @children = []
  end
   
  def add_child child_name, &code
    @children.push({:name    => child_name, 
                    :run     => code, 
                    :pipe_io => ProcLog::create_pipe(child_name)}) 
  end 
  
  def run 
    run_children 0 
  end 
  
  def run_children children_index
      
    child = @children[children_index] 
      
    puts "Starting task #{child[:name]}"
          
    IO.popen("-") do |child_io|
      if child_io.nil?
        child[:run].call child[:name]
        exit
      else
        child[:io] = child_io
        last = (children_index == (@children.size-1))
        if last           
          return run_as_parent
        else
          run_children(children_index+1)
        end
      end
    end
      
  end

  def run_as_parent 
    puts "Starting to listen on incoming logs..."
    writes = []
    errors = []
    reads  = []
    
    @children.each {|child| reads.push child[:pipe_io], child[:io] }
    
    while true
      r, w, e = IO.select reads, writes, errors, nil 
      
      break if r.nil?
      
      r.each do |io|
        return if io.closed? or io.eof? 
        @children.each do |child|
          if io == child[:io]
            puts "(#{child[:name]}) (out) : #{io.gets}"
            break;
          end

          if io == child[:pipe_io]
            puts "(#{child[:name]}) (log) : #{io.gets}"
            break;
          end
        end 
      end # each file descriptor 
    end # infinite loop 
  end

end 

def run_as_test_child child_name
  pipe_io = File::open ProcLog::pipe_name_for(child_name), "w"
  while true
    puts "I am process #{Process.pid}"
    pipe_io.puts "To pipe from process #{Process.pid}"
    pipe_io.flush
    Kernel.sleep(1)
  end 
end


proclog.run

