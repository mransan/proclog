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

#def run_as_test_child child_name
#    pipe_io = File::open ProcLog::pipe_name_for(child_name), "w"
#    while true
#        puts "I am process #{Process.pid}"
#        pipe_io.puts "To pipe from process #{Process.pid}"
#        pipe_io.flush
#        Kernel.sleep(1)
#    end 
#end

class MbigCfg
    MBIG_TSK = "mbig.tsk"

    attr_reader :name
    attr_reader :cmd
    attr_reader :working_dir
    
    def initialize yaml
        @name = "mbig"
        @mbig_number = yaml['mbig_number']
        throw "Invalid MBIG" if @mbig_number.nil?

        @working_dir = IO.popen("pwd").gets.chomp!
        @cmd = [MBIG_TSK,  @mbig_number]
    end
end

class ServiceCfg
    TASK_EXT = 'tsk'
    CFG_EXT  = 'cfg'
    BB_DIR   = '/bb/bin/'        
    
    attr_reader :name
    attr_reader :task
    attr_reader :cfg
    attr_reader :working_dir

    def initialize name, yaml_obj
        @name     = name
        cfg_dir   = yaml_obj['cfg_dir']
        build_dir = yaml_obj['build_dir']  
 
        @local = !yaml_obj['run_on']['local'].nil? and 
                  yaml_obj['run_on']['local']
        if @local
            @working_dir = build_dir
            
            @task = "./#{@name}.sundev1.#{TASK_EXT}" 
            @cfg  = "./#{@name}.#{CFG_EXT}"
        else
            version = yaml_obj['run_on']['version']
            version = "" if version == 1
            @workin_dir = IO.popen("pwd").gets.chomp! 
            @task   = "#{BB_DIR}/#{@name}.#{TASK_EXT}"
            @cfg    = "#{BB_DIR}/#{@name}.#{CFG_EXT}"
        end
    end

    def cmd
        [task, cfg, "-l", ProcLog::pipe_name_for(name)]
    end
end

class Config
    CFG_FILE = "proclog.cfg"
    
    attr_reader :processes 
    def initialize
        @processes =  []
        File::open(CFG_FILE) do |cfg_file|
            yaml = YAML::load(cfg_file)
            
            if not yaml['services'].nil?
                yaml['services'].each_pair do |service_name, service_cfg|
                    @processes.push ServiceCfg.new(service_name, service_cfg)
                end 
            end 
            
            if not yaml['mbig'].nil?
                @processes.push  MbigCfg.new(yaml['mbig'])
            end
        end 
    end
end
        
config  = Config.new
proclog = ProcLog.new

config.processes.each do |proc| 
    
    proclog.add_child proc.name do |child_name|
        puts "Changing to dir:#{proc.working_dir}"
        Dir.chdir proc.working_dir
        Kernel.exec(*proc.cmd)
    end
end

proclog.run

