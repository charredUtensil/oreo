require 'thread'
require 'fileutils'
require 'yaml'
require 'set'
require 'open-uri'

require File.expand_path(File.dirname(__FILE__) + '/logger.rb')

class MinecraftServer
  # Version constants
  OREO_VERSION = '0.12.2'
  SUPPORTED_MINECRAFT_VERSIONS = ['Beta 1.7.3', 'Beta 1.8.1', '1.0.0', '1.0.1', '1.1']
  
  # Numeric constants
  CHARS_PER_SAY = 40
  CHARS_PER_TELL = 32
  
  # Directories & files
  OREO_DIRECTORY = File.dirname(__FILE__)
  ITEMS_FILE = OREO_DIRECTORY + '/items'
  OREO_ZIP_URL = 'https://github.com/charredUtensil/oreo/zipball/master'
  
  # Executables
  SERVER_SHELL_COMMAND_DUMMY = OREO_DIRECTORY+'/dummy_server'
  
  # Misc. stuff
  COLOR_ESCAPE = File.read(OREO_DIRECTORY+'/colorescape').chomp
  
  # Misc. regex
  PROPERTY_REGEX = /^(?<key>\S+)=(?<value>.*)$/ # key value
  COMMENT_REGEX = /^\s*(?:#.*)?$/
  ITEM_REGEX = /^\s*(?<id>\d+)(?:\.(?<sub>\d+))?\s+(?<names>[a-z0-9 ,']+)$/
  SAY_SANITIZE_REGEX = /[^ -~\n]+/
  
  # Regular expressions to parse output
    # Parts of regexes
    PREFIX_REGEX_PART = "^(?<date>\\d+-\\d+-\\d+)\\s+(?<time>\\d+:\\d+:\\d+)\\s+\\[(?<level>\\w+)\\]\\s+"
    IP_REGEX_PART = "\\[(?<ip>.+?):(?<port>\\d+)\\]"
    PLAYER_REGEX_PART = "(?<player>\\S+)"
    
    PREFIX_REGEX = /#{PREFIX_REGEX_PART}/o
    
    # Server problems
    SERVER_LAG_REGEX = /#{PREFIX_REGEX_PART}Can't keep up.*$/o
    OUTDATED_REGEX = /#{PREFIX_REGEX_PART}Disconnecting #{PLAYER_REGEX_PART} #{IP_REGEX_PART}: Outdated server!$/o
    
    # Startup messages
    # These don't check prefixes in case of fire.
    VERSION_CHECK_REGEX = /Starting minecraft server version (?<version>.+)$/o
    MINECRAFT_READY_REGEX = /Done/o
    
    # Miscellania
    COMMAND_REGEX = /#{PREFIX_REGEX_PART}#{PLAYER_REGEX_PART} tried command: (?<command>.+)$/o
    PLAYER_LOGGED_IN_REGEX = /#{PREFIX_REGEX_PART}#{PLAYER_REGEX_PART} #{IP_REGEX_PART} logged in.*$/o
    PLAYER_LOGGED_OUT_REGEX = /#{PREFIX_REGEX_PART}#{PLAYER_REGEX_PART} (?<reason>lost connection|was kicked).*$/o
    CHAT_REGEX = /#{PREFIX_REGEX_PART}<#{PLAYER_REGEX_PART}> (?<message>.*)$/o
    EMOTE_REGEX = /#{PREFIX_REGEX_PART}\* #{PLAYER_REGEX_PART} (?<message>.*)$/o
    SAVE_COMPLETE_REGEX = /#{PREFIX_REGEX_PART}CONSOLE: Save complete.\s*$/o
    
    # This is used to filter out known messages that can be ignored after filtering out the others
    LINE_IGNORE_REGEX =
    /^(?:
        \s*at\s.*                         # Java stack traces
      | \s*New max size:\s\d+             # This started appearing in 1.8pre2
      | \s*\d+\.\d+(?:E[+\-]\d+)?\s*      # Random floating point numbers
      | \s*java.net.SocketException:.*    # Mojang doesn't handle SocketExceptions
      | #{PREFIX_REGEX_PART}(?:           # Messages with prefixes
          \[?CONSOLE.*                    # Console Speaks
        | \S+\s+whispers.*                # Generic whisper
        | Toggling rain and snow, hold on\.\.\.
        )
    )$/ox
  
  # Items
  ITEMS = {}
  ITEM_NAMES = {}
  File.open(ITEMS_FILE) do |f|
    f.each_line do |line|
      next if COMMENT_REGEX.match(line)
      m = ITEM_REGEX.match(line)
      raise IOError.new("Invalid line `#{line}'") if m.nil?
      names = m[:names].split(/,\s+/)
      dv = m[:id]
      dv += ".#{m[:sub]}" unless m[:sub].nil?
      ITEM_NAMES[dv] = names[0]
      names.each{|n| ITEMS[n] = dv}
    end
  end
  
  def initialize(minecraft_directory = OREO_DIRECTORY + '/../')
    @running = false
    @ready = false
    @io = nil
    @daemon = nil
    
    @players = {}
    @properties = {}
    
    @minecraft_directory = File.expand_path(minecraft_directory)
    @backup_directory = minecraft_directory + '/backups'
    @players_directory = nil
    @server_properties_file = @minecraft_directory + '/server.properties'
    
    @shell_command = "cd #{@minecraft_directory}; exec java -Xmx1024M -Xms1024M -jar minecraft_server.jar nogui 2>&1"
    
    @minecraft_jar_url = 'http://www.minecraft.net/download/minecraft_server.jar'
    
    @logger = MinecraftLogger.new(@minecraft_directory + '/oreo.log')
    
    begin
      load_config
    rescue Exception => e
      log "Couldn't load config", :error
      log e, :error
    end
    begin
      load_properties
      load_players
    rescue Exception => e
      log "Couldn't load properties", :error
      log e, :error
    end
  end
  
  attr_accessor :shell_command
  attr_reader :items, :item_names, :players, :properties, :minecraft_directory, :backup_directory, :players_directory, :server_properties_file, :logger
  
  def running?
    return @running
  end
  
  def ready?
    return @ready
  end
  
  def save_config
    #File.open(SERVER_PERMISSION_FILE,'w'){|f| f.write(@allowed.to_yaml)}
  end
  
  def load_config
    #@allowed=YAML.load(File.read(SERVER_PERMISSION_FILE))
  end
  
  def load_properties
    @properties = {}
    File.open(@server_properties_file) do |f|
      f.each_line do |line|
        next if COMMENT_REGEX.match(line)
        m = PROPERTY_REGEX.match(line)
        raise IOError.new("Invalid line `#{line}'") if m.nil?
        @properties[m[:key]]=m[:value]
      end
    end
  end
  
  def load_players
    @players = {}
    @players_directory = "#{@minecraft_directory}/#{@properties['level-name']}/players/"
    Dir.glob("#{@players_directory}/*.dat").map{|p| /[\\\/]([^\\\/]+)\.dat$/.match(p)[1]}.each{|x| @players[x] = MinecraftPlayer.new(self,x)}
    @players['all'] = MinecraftPlayer.new(self,'all')
  end
  
  def players_online?
    return @players.values.any?{|p| p.online?}
  end
  
  def player_names
    return @players.keys - ['all']
  end
  
  def player_names_online
    return @players.values.select{|p| p.online?}.map{|p| p.username}
  end
  
  # opens a console
  def console
    #log "Starting minecraft server `#{@properties['level-name']}'", :info
    while running?
      begin
        process_console_line
#      rescue Interrupt => e
#        puts 'exit'
#        OreoCommand.execute(this,nil,'exit',[])
#      rescue SignalException => e
#        log "Recieved shutdown signal. Stopping server.", :warn
#        stop 2, "recieved signal #{e.signo}"
      rescue StandardError => e
        log e, :error
      end
    end
  end
  
  def start
    raise "Server is still running!" if @running
    @running = true
    @ready = false
    @io = IO.popen(@shell_command,'r+')
    start_daemon
  end
  
  def stop(seconds=DEFAULT_STOP_TIME, message=nil)
    seconds = 0 if seconds.downcase == 'now'
    raise ArgumentError.new("Seconds must be an integer") unless seconds.to_s =~ /\A\d+\Z/
    seconds = seconds.to_i
    while seconds > 0
      say "The server is shutting down in #{seconds} seconds. #{message}"
      sleep(1)
      seconds -= 1
    end
    @running = false
    @ready = false
    say "The server is shutting down NOW. #{message}"
    say "Goodbye."
    player_names_online.each do |player|
      execute "kick #{player}"
      player.logout
    end
    @daemon.join if @daemon and @daemon != Thread.current
    @daemon = nil
    execute 'save-all'
    nil while not @io.readline =~ SAVE_COMPLETE_REGEX # Wait for save to complete
    execute 'stop'
    @io.close
    begin
      save_config
      return 'stopped server and saved configuration.'
    rescue IOError
      return 'stopped server.'
    end
  end
  
  # Reload oreo files from disk. Returns true on success
  def reload
    ov = $VERBOSE
    success = true
    $VERBOSE = nil unless @logger.output_level == :debug
    $LOADED_FEATURES.each do |file|
      begin
        if file.include? OREO_DIRECTORY
          log "Reloading #{file}", :debug
          load file
        end
        success=true
      rescue Exception => e
        log e, :error
        success=false
      end
    end
    $VERBOSE = ov
    return success
  end
  
  # Force a full reload. Server must be stopped first
  def reload!
    raise "Server is still running!" if @running
    exec($0, *ARGV)
  end
  
  def update_oreo
    #cookietar = "#{OREO_DIRECTORY}/oreo.tgz"
    #cookietar_old = "#{OREO_DIRECTORY}/oreo-old.tgz"
    begin
      #log "Updating Oreo from #{OREO_URL}", :info
      #File.delete cookietar if File.exist? cookietar
      #wget OREO_URL, cookietar
      #raise "File failed to download" unless File.exist? cookietar
      #File.delete cookietar_old if File.exist? cookietar_old
      #unless system("cd #{OREO_DIRECTORY}; tar -czf #{cookietar_old} * 2>&1")
      #  File.delete cookietar
      #  raise "Failed to backup old installation"
      #end
      #result = system("cd #{OREO_DIRECTORY}; tar -xzf #{cookietar} 2>&1")
      #File.delete cookietar
      #return result
      if File.directory? "#{OREO_DIRECTORY}/.git"
        log "Updating Oreo from Git repository", :info
        return system "cd #{OREO_DIRECTORY}; git pull 2>&1"
      else
        log "Oreo must be installed with git to self-update", :error
        return false
      end
    rescue Exception => e
      log "Update failed", :error
      log e, :error
      return false
    ensure
    end
  end
  
  # Update Minecraft. Server must be stopped first. Returns true on success.
  def update_minecraft(url = @minecraft_jar_url)
    raise "Server is still running!" if @running
    serverjar = @minecraft_directory + '/minecraft_server.jar'
    oldserverjar = serverjar + '.old'
    begin
      log "Updating minecraft_server.jar from #{url}", :info
      File.delete oldserverjar if File.exist? oldserverjar
      FileUtils.mv serverjar, oldserverjar
      wget url, serverjar
      raise "File failed to download" unless File.exist? serverjar
      start
      startwait = Time.now
      while not ready?
        sleep 2
        raise "Oreo daemon failed to start" if @daemon.nil?
        raise "Server took too long to start" if (Time.now - startwait) > 60
      end
      return true
    rescue Exception => e
      log "Update failed", :error
      log e, :error
      log "Rolling back minecraft server", :info
      FileUtils.mv oldserverjar, serverjar if File.exist? oldserverjar
      sleep 2
      start
      return false
    end
  end
  
  def say(message)
    message.gsub!(SAY_SANITIZE_REGEX,'')
    message.split("\n").each do |line|
      wordwrap(line,CHARS_PER_SAY).each do |talkline|
        execute "say #{talkline}"
        log "Server: #{talkline}", :servertalk
      end
    end
  end
  
  def tell(player, message)
    message.gsub!(SAY_SANITIZE_REGEX,'')
    if player.nil?
      puts message
    else
      message.split("\n").each do |line|
        wordwrap(line,CHARS_PER_TELL).each do |talkline|
          execute "tell #{player} #{color(talkline,3)}"
        end
      end
    end
  end
  
  def permissions(player)
    return @players['all'].permissions | @players[player].permissions
  end
  
  #def allowed?(player,cmd)
  #  return (@players['all'].allowed? cmd or @players[player].allowed? cmd)
  #end
  
  def execute(string)
    @io.puts(string)
      log "> #{string}", :debug
    return string
  end
  
  def log(logme,level)
    @logger.log(logme,level)
  end
  
private
  # Convert a string to a list of lines, each with length <= margin if at all possible
  def wordwrap(string, margin)
    li = string.split
    result = []
    line = []
    c = 0
    while not li.empty?
      s = li.shift
      if c + s.length > margin
        result << line.join(' ')
        line = [s]
        c = s.length
      else
        c += s.length
        line << s
      end
    end
    result << line.join(' ') unless line.empty?
    return result
  end
  
  def start_daemon
    Thread.new do
      begin
        @daemon = Thread.current
        while @running and @daemon == Thread.current
          process_line
        end
      rescue Exception => e
        begin
          say "Error: Oreo daemon crashed. Please notify the server administrator. See log for details."
        rescue Exception
          nil
        end
        log e, :fatal
      end
      @daemon = nil if @daemon == Thread.current
    end
  end
  
  def wget(url,filename)
    begin
      open(url, 'rb', :proxy => nil) do |r|
        open(filename,'wb') do |w|
          w.write(r.read)
        end
      end
    rescue RuntimeError => e
      m = /redirection forbidden: (.*) -> https:\/\/(.*)$/.match(e.message)
      raise e if m.nil?
      log "redirected to https://#{m[2]}", :info
      log 'Overriding open-uri to redirect from http to https', :info
      open("https://#{m[2]}", 'rb', :proxy => nil) do |r|
        open(filename,'wb') do |w|
          w.write(r.read)
        end
      end
    end
  end
  
  def process_line
    line = @io.readline
    log line.chomp, :debug
    if SERVER_LAG_REGEX.match(line)
      log 'Server is lagging', :info
      #say 'Server is lagging'
    elsif match = CHAT_REGEX.match(line)
      log "#{match[:player]}: #{match[:message]}", :talk
    elsif match = EMOTE_REGEX.match(line)
      log "* #{match[:player]} #{match[:message]}", :talk
    elsif match = COMMAND_REGEX.match(line)
      args = match[:command].split
      cmd = args.shift
      player = match[:player]
      OreoCommand.execute(self,player,cmd,args)
    elsif match = PLAYER_LOGGED_IN_REGEX.match(line)
      name = match[:player]
      player = (@players[name] or MinecraftPlayer.new(self,name))
      player.login(match[:ip])
      @players[name] = player
      log "#{match[:player]} logged in from #{match[:ip]}", :login
    elsif match = PLAYER_LOGGED_OUT_REGEX.match(line)
      if @players.key? match[:player]
        @players[match[:player]].logout 
        log "#{match[:player]} logged out", :login
      else
        log "#{match[:player]} failed to connect", :login
      end
    elsif match = OUTDATED_REGEX.match(line)
      log "Server is outdated! Disconnected #{match[:player]}!", :warn
    elsif not ready?
      if match = VERSION_CHECK_REGEX.match(line)
        log "Oreo      v#{OREO_VERSION}",:info
        log "Ruby      v#{RUBY_VERSION}", :info
        if SUPPORTED_MINECRAFT_VERSIONS.include? match[:version]
          log "Minecraft v#{match[:version]}", :info
        else
          log "Minecraft v#{match[:version]} (untested with this version of Oreo)", :warn
          logger.output_level = :debug
          log "Debug mode automatically enabled. You may turn it off by typing the verbose command.", :debug
        end
      elsif match = MINECRAFT_READY_REGEX.match(line)
        log "Server started successfully", :info
        @ready = true
      elsif line =~ /\[WARNING\]/
        log line.sub(PREFIX_REGEX,''), :warn
      elsif line =~ /\[(ERROR|SEVERE|FATAL)\]/
        log line.sub(PREFIX_REGEX,''), :error
        log "Debug mode automatically enabled", :warn
        logger.output_level = :debug
      end
    elsif not LINE_IGNORE_REGEX =~ line
      log line.chomp.gsub(PREFIX_REGEX,''), :unknown
    #else
      #ignore line
    end
  end
  
  def process_console_line
    args = $stdin.readline.split
    return if args.empty?
    cmd = args.shift.sub(/^\//,'')
    OreoCommand.execute(self, nil, cmd, args)
  end
  
  def color(string,color)
    return "#{COLOR_ESCAPE}#{color.to_s(16)}#{string}"
  end
end

require File.expand_path(File.dirname(__FILE__) + '/command.rb')
require File.expand_path(File.dirname(__FILE__) + '/player.rb')
