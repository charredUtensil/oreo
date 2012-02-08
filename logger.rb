class MinecraftLogger
  # Escape codes for colors
  #TERMINAL_COLORS =
  #{
  #  'red' => 31,    'green' => 32,  'yellow' => 33, 'blue' => 34,
  #  'magenta' => 35, 'cyan' => 36,   'gray' => '0', 'grey' => '0'
  #}
  
  LEVELS = [:debug, :info, :talk, :servertalk, :login, :unknown, :warn, :error, :fatal]
  COLORS = [     0,    36,    34,          35,     32,        1,    33,     31, '31;1']
  
  LEVEL_NUMS = {}
  LEVELS.each.with_index{|x,i| LEVEL_NUMS[x] = i}
  
  def initialize(file = nil)
    @color_output = false
    @bell = false
    @output_level = 1
    if file.nil?
      nil
    elsif file.kind_of? IO
      @file = file
    else
      begin
        @file = File.open(file,'a')
      rescue IOError => e
        log "Couldn't open logfile: #{e.message}", :error
      end
    end
  end
  
  attr_writer :bell, :color_output
  
  def color_output?
    return @color_output
  end
  
  def output_level
    return LEVELS[@output_level]
  end
  
  def output_level=(level)
    level = LEVEL_NUMS[level] unless level.kind_of? Fixnum
    raise ArgumentError.new "Invalid log level" if level.nil?
    @output_level = level
  end
  
  def bell?
    return @bell
  end
  
  def log(logme, level)
    level = LEVEL_NUMS[level] unless level.kind_of? Fixnum
    raise ArgumentError.new "Invalid log level" if level.nil?
    
    return if level < @output_level
    
    prefix = Time.now.strftime '%b %e %H:%M:%S '
    s = nil
    if logme.kind_of? Exception
      s = "#{logme.class}: #{logme.message}\n#{logme.backtrace.join("\n")}"
    else
      s = logme.to_s
    end
    
    s.gsub!(/[^\n -~]+/,'')
    
    unless @file.nil?
      begin
        @file.puts("#{prefix}[#{LEVELS[level].to_s.upcase}] #{s}")
        @file.flush
      rescue IOError
        puts "Couldn't write to logfile"
      end
    end
    
    if color_output?
      s = "\e[#{COLORS[level]}m#{prefix}#{s}\e[m"
    else
      s = "#{prefix}[#{LEVELS[level].to_s.upcase}] #{s}"
    end
    s << "\a" if bell?
    
    puts s
  end
end
