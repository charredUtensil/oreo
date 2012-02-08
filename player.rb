require 'set'
require 'yaml'

class MinecraftPlayer
  def initialize(server, username)
    @server = server
    @username = username
    @online = false
    begin
      etc = YAML.load_file "#{@server.players_directory}/#{@username}.cfg"
      @permissions = Set.new(etc['permissions'].to_a)
      @ips = Set.new(etc['ips'].to_a)
      @last_command = etc['last_command']
    rescue Exception => e
      @server.log("Couldn't load file for #{@username}, creating default", :info)
      @permissions = Set.new
      @ips = Set.new
      @last_command = nil
      save
    end
  end
  
  attr_reader :username, :ips
  attr_accessor :last_command
  
#  def inspect
#    return "<MinecraftPlayer: @username=#{@username.inspect}, @online=#{@online.inspect}, @ips=#{@ips.inspect}, @permissions=#{@permissions.inspect}>"
#  end
  
  def login(ip)
    @ips << ip
    @online = true
  end
  
  def logout
    @online = false
  end
  
  def online?
    return @online
  end
  
  def allow(command)
    @permissions << command
  end
  
  def revoke(command)
    @permissions.delete command
  end
  
  def allowed?(command)
    return (@permissions.include? command or @permissions.include? '*')
  end
  
  def permissions
    return @permissions.dup
  end
  
  def save
    begin
      File.open "#{@server.players_directory}/#{username}.cfg", 'w' do |f|
        f.write({'ips' => @ips.to_a, 'permissions' => @permissions.to_a, 'last_command' => @last_command}.to_yaml)
      end
    rescue Exception => e
      @server.log("Couldn't save player file for #{@username}", :error, :red)
    end
  end
end
