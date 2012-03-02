class OreoCommand
  NOISY = false
  
  COMMANDS = {}
  
  def initialize(server, user)
    @server = server
    @user = user
  end
  
  def self.execute(server, user, command, args)
    begin
      cmd = COMMANDS[command.downcase]
      raise ArgumentError.new("Unrecognized command: #{command}") if cmd.nil?
      if user.nil? or server.players['all'].allowed?(command) or server.players[user].allowed?(command)
        server.log "#{user or 'CONSOLE'} used command #{command} #{args.join(' ')}", :info
        result = cmd.new(server,user).execute(*args)
      else
        server.log "#{user} tried command #{command} #{args.join(' ')}", :warn
        result = "You are not allowed to use the #{command} command"
      end
      if not result.nil?
        if cmd.noisy?
          server.say("#{user or 'CONSOLE'} #{result}")
        else
          server.tell(user,result)
        end
      end
    rescue StandardError => e
      begin
        server.tell(user, 'Error: ' + e.message)
        server.tell(user, 'Type /help <command> for help') if e.kind_of? ArgumentError
      rescue Exception
        nil
      end
      if e.kind_of? ArgumentError
        server.log "#{e.class}: #{e.message}", :info
        server.log e, :debug
      else
        server.log e, :error
      end
    end
  end
  
  def self.noisy?
    return self::NOISY
  end
  
  def self.autocomplete(string,list)
    raise ArgumentError.new("Argument is nil") if string.nil?
    return string if list.include? string
    len = string.length
    result = list.select{|x| x[0...len].downcase == string.downcase}.shuffle
    return nil if result.empty?
    return result[0] if result.length == 1
    raise ArgumentError.new("Ambiguous reference. Could refer to any of: #{result[0...10].sort.join(', ')}#{result.size > 10 and ", (#{result.size - 10} others)" or ''}")
  end
  
  def autocomplete_player(player)
    return @user if (player == 'me' and not @user.nil?)
    result = OreoCommand.autocomplete(player, @server.player_names)
    raise ArgumentError.new("#{player} does not exist") if result.nil?
    return result
  end
  
  def autocomplete_online(player)
    return @user if (player == 'me' and not @user.nil?)
    result = OreoCommand.autocomplete(player, @server.player_names_online)
    raise ArgumentError.new("#{player} is not online or does not exist") if result.nil?
    return result
  end
  
  def self.bind(name)
    OreoCommand::COMMANDS[name.to_s.downcase] = self
  end
  
  #def self.bind(*args)
  #  args.each{|name| OreoCommand::COMMANDS[name.to_s.downcase] = self}
  #end
end

class AllowCommand < OreoCommand
  HELP = '/allow <player or all> <commands> - Allow player to use command(s)'
  bind :allow
  
  def execute(player,*cmds)
    raise ArgumentError.new("Please supply one or more commands") if cmds.empty?
    player = autocomplete_player player unless player == 'all'
    cmds.each{|cmd| raise ArgumentError.new("Invalid command #{cmd}") unless cmd == '*' or COMMANDS.keys.include? cmd}
    p = @server.players[player]
    cmds.each{|cmd| p.allow(cmd)}
    p.save
    message = nil
    if cmds.length == 1
      message = "may now use the #{cmds[0]} command"
    else
      message = "may now use the #{cmds[0...cmds.length-1].join(', ')} and #{cmds[cmds.length-1]} commands"
    end
    if player == 'all'
      @server.say "Everyone #{message}"
    else
      @server.tell player, "You #{message}"
    end
    return "allowed #{player} to use #{cmds.inspect}"
  end
end

class AnnoyCommand < OreoCommand
  HELP = '/annoy <player> - Annoy a player by spamming their inventory with dirt'
  bind :annoy
  
  def execute(player)
    player = autocomplete_online player
    20.times do
      @server.execute "give #{player} 3 64"
    end
    "annoyed #{player}"
  end
end

class BanCommand < OreoCommand
  HELP = '/ban <player> - Ban player from the server'
  NOISY = true
  bind :ban
  
  def execute(player)
    player = autocomplete_player player
    @server.execute('ban ' + player)
    @server.players[player].logout
    return "banned #{player}"
  end
end

class BackupCommand < OreoCommand
  HELP = '/backup [comment] - Force a full backup of the world'
  bind :backup
  
  def execute(*args)
    begin
      @server.say "The server is backing up. Please wait."
      @server.execute 'save-off'
      @server.execute 'save-all'
      @server.save_config
      sleep 4
      comment = args.join('_').gsub(/^W/,'')
      comment = '_' + comment unless comment == ''
      filename = "#{@server.properties['level-name']}_#{Time.now.strftime('%Y%m%d%H%M%S_%A_%B_%d')}#{comment}.tar.gz"
      @server.log "writing file #{filename}", :debug
      result = `cd #{@server.minecraft_directory}; tar -czf #{@server.backup_directory}/#{filename} #{@server.properties['level-name']} 2>&1`
      raise result if $?.to_i != 0
    ensure
      @server.execute 'save-on'
    end
    @server.log "Created backup #{filename}", :info
    return "backed up world successfully to #{filename}"
  end
end

class BellCommand < OreoCommand
  HELP = '/bell - Toggle adding an ASCII bell character to every line of terminal output'
  bind :bell
  
  def execute
    @server.logger.bell = !@server.logger.bell?
    return "Bell is now #{@server.logger.bell? and 'on' or 'off'}"
  end
end

class DayCommand < OreoCommand
  HELP = '/day - Make it daytime'
  NOISY = true
  bind :day
  
  def execute
    @server.execute 'time set 0'
    return 'set time to dawn'
  end
end

class DeopCommand < OreoCommand
  HELP = '/deop <player> - Remove op status from player'
  bind :deop
  
  def execute(player)
    @server.execute('deop ' + autocomplete_player(player))
    return "revoked op from #{player}"
  end
end

class DoRawCommand < OreoCommand
  HELP = '/doraw! <command> - Runs <command> directly on the server like an op. Use with caution!'
  bind 'doraw!'
  
  def execute(*args)
    @server.log("#{@user} executed raw command #{args.join(' ')}", :warn)
    @server.execute args.join(' ')
    return "done"
  end
end

class ExitCommand < OreoCommand
  HELP = "/exit - exit"
  bind 'exit'
  
  def execute
    if @user.nil?
      return "This ain't a UNIX shell. Use stop to stop the server or press ctrl+a d to disconnect the screen session you ran this in. You DID run this in a screen session, didn't you?"
      #if ENV['STY'].nil?
      #  return 'The server does not appear to be running in a screen session'
      #else
      #  begin
      #    system('screen', '-d', ENV['STY'])
      #    return 'disconnected screen'
      #  rescue Exception => e
      #    return 'A screen session was detected, but could not be disconnected'
      #  end
      #end
    else
      @server.tell(@user,"Well... Ok. You asked for it!")
      sleep 1
      @server.execute('kick ' + @user)
      @server.players[@user].logout
      return "exited"
    end
  end
end

class GiveCommand < OreoCommand
  HELP = '/give <player> [quantity] <item name> - Give player a quantity of item. Example: /give me 64 cobblestone'
  bind :give
  
  ARG_REGEX = /^(?<qty>\d+\s+)?(?:(?<dv>\d+(?:\.\d+)?)|(?<item>\w[\w\s]*))$/

  def execute(player,*args)
    player = autocomplete_online player
    raise ArgumentError.new "Expected item" if args.empty?
    match = args.join(' ').downcase.match(ARG_REGEX)
    raise "Regex didn't match input" if match.nil?
    qty = (match[:qty] or 1).to_i
    raise ArgumentError.new "Quantity cannot be more than 10 stacks" if qty > 640
    dv = nil
    if match[:dv].nil?
      dv = MinecraftServer::ITEMS[match[:item].downcase]
      dv = MinecraftServer::ITEMS[OreoCommand.autocomplete(match[:item],MinecraftServer::ITEMS.keys)] if dv.nil?
    else
      dv = match[:dv] if self.kind_of?(ForceGiveCommand) or MinecraftServer::ITEM_NAMES.keys.include?(match[:dv])
    end
    raise ArgumentError.new("Unknown item: #{match[:dv] or match[:item]}") if dv.nil?
    a, b = dv.split('.')
    n = qty
    while n > 64
      @server.execute "give #{player} #{a} 64 #{b}"
      n -= 64
    end
    @server.execute "give #{player} #{a} #{n} #{b}"
    return "gave #{player} #{qty}x #{MinecraftServer::ITEM_NAMES[dv]} (##{dv})"
=begin
    qty = 1
    item = nil
    if args[0].to_s =~ /\A\d+\Z/ and args.length > 1
      qty = args.shift.to_i
      raise ArgumentError.new "Quantity cannot be more than 10 stacks" if qty > 640
    end
    item = args.join(' ')
    n = qty
    dv = nil
    dv = @server.items[item.downcase]
    dv = @server.items[OreoCommand.autocomplete(item,@server.items.keys)] if dv.nil?
    dv = item.to_i if dv.nil? and @server.items.values.include?(item.to_i)
    dv = item.to_i if dv.nil? and self.kind_of?(ForceGiveCommand) and item =~ /\A\d+\Z/ and item.to_i > 0
    raise ArgumentError.new "Unknown item: #{item}" if dv.nil?
    while n > 64
      @server.execute "give #{player} #{dv} 64"
      n -= 64
    end
    @server.execute "give #{player} #{dv} #{n}"
    return "gave #{player} #{qty}x #{@server.item_names[dv]} (##{dv})"
=end
  end
end

class GotoCommand < OreoCommand
  HELP = '/goto <player> - teleport to another player'
  bind :goto
  
  def execute(player)
    return "You are not playing this game and therefore cannot teleport to anyone." if @user.nil?
    player = autocomplete_online player
    @server.execute("tp #{@user} #{player}")
    @server.tell(player,"#{@user} teleported to you")
    return "teleported to #{player}"
  end
end

class HelpCommand < OreoCommand
  HELP = '/help [command] - Print help info. Supply a command for help on that command.'
  bind :help
  
  def execute(command=nil)
    if command == 'all' and @user.nil?
      COMMANDS.values.map{|cmd| cmd::HELP}.sort.each{|x| puts x}
      return ''
    elsif command.nil? or COMMANDS[command].nil?
      result = nil
      if @user.nil? or @server.players[@user].allowed? '*'
        result = COMMANDS.keys.sort
      else
        result = @server.permissions(@user).sort
      end
      result.unshift "Available commands (/help [COMMAND] for more info):"
      return result.join(' ')
    else
      return COMMANDS[command]::HELP
    end
  end
end

class IPCommand < OreoCommand
  HELP = '/ip <player> - List IP addresses used by player'
  bind :ip
  
  def execute(player)
    if player == 'all'
      return "IP addresses for all: #{@server.players.values.inject(Set.new){|ips,ply| ips | ply.ips}.to_a.join ' '}"
    else
      player = autocomplete_player player
      return "IP addresses for #{player}: #{@server.players[player].ips.to_a.join ' '}"
    end
  end
end

class KickCommand < OreoCommand
  HELP = '/kick <player> - Kick player from the server'
  NOISY = true
  bind :kick
  
  def execute(player)
    player = autocomplete_player player
    @server.execute('kick ' + player)
    @server.players[player].logout
    return "kicked #{player}"
  end
end

class ListCommand < OreoCommand
  HELP = '/list - List all players currently on the server'
  bind :list
  
  def execute
    return "Connected players: #{@server.player_names_online.sort.join(', ')}"
  end
end

class ModeCommand < OreoCommand
  HELP = '/mode <player> <mode> - Change player\'s gamemode. Valid options are c (creative) and s (survival).'
  bind :mode
  
  def execute(player, mode)
    player = autocomplete_player(player)
    mode = mode.downcase[0]
    rawmode = nil
    case mode
      when 'c' then
        mode = 'creative'
        rawmode = 1
      when 's' then
        mode = 'survival'
        rawmode = 0
      else
        raise ArgumentError.new("Invalid gamemode. Valid modes are c and s.")
    end
    @server.execute "gamemode #{player} #{rawmode}"
    @server.tell player, "You are now in #{mode} gamemode"
    return "put #{player} in #{mode} gamemode"
  end
end

class NightCommand < OreoCommand
  HELP = '/night - Fill \'em with midnight'
  NOISY = true
  bind :night
  
  def execute
    @server.execute 'time set 12000'
    return 'set time to dusk'
  end
end

class OpCommand < OreoCommand
  HELP = '/op <player> - Give player full admin access, bypassing Oreo'
  bind :op
  
  def execute(player)
    player = autocomplete_player(player)
    @server.execute('op ' + player)
    return "made #{player} op"
  end
end

class PotionCommand < OreoCommand
  POTION_EFFECTS = {
    'regeneration' => 1,
    'swiftness' => 2,
    'fire resistance' => 3,
    'poison' => 4,
    'healing' => 5,
    'weakness' => 8,
    'strength' => 9,
    'slowness' => 10,
    'harming' => 12
  }

  POTION_TIERS = {
    'ii' => 2
  }

  ARG_REGEX = /^(?<extended>extended)?\s*(?<splash>splash)?\s*(?<effect>#{POTION_EFFECTS.keys.sort.join('|')})\s*(?<tier>#{POTION_TIERS.keys.sort.join('|')})?$/
  
  HELP = "/potion <player> [extended] [splash] <#{POTION_EFFECTS.keys.sort.join(' | ')}> [#{POTION_TIERS.keys.join(' | ')}] - gives player that potion"
  bind :potion
  
  def execute(player,*args)
    player = autocomplete_online player
    raise ArgumentError.new "Expected potion" if args.empty?
    match = args.join(' ').downcase.match(ARG_REGEX)
    raise ArgumentError.new "Invalid potion" if match.nil?
    effect = POTION_EFFECTS[match[:effect]]
    tier = (POTION_TIERS[match[:tier]] or 0)
    extended = (match[:extended] and 1 or 0)
    splash = (match[:splash] and 1 or 0)
    dv = splash*16384 + extended*64 + tier*32 + effect
    @server.execute "give #{player} 373 1 #{dv}"
    return "gave #{player} 1 #{match[:extended]} #{match[:splash]} potion of #{match[:effect]} #{match[:tier].upcase} (373.#{dv})".gsub(/\s+/,' ')
  end
end

class PrecipCommand < OreoCommand
  HELP = '/precip - toggle rain and snow'
  bind :precip
  
  def execute
    @server.execute "toggledownfall"
    return "changed weather"
  end
end

class RevokeCommand < OreoCommand
  HELP = '/revoke <player> <command> - Deny player access to command'
  bind :revoke
  
  def execute(player,*cmds)
    raise ArgumentError.new("Please supply one or more commands") if cmds.empty?
    player = autocomplete_player player unless player == 'all'
    cmds.each{|cmd| raise ArgumentError.new("Invalid command #{cmd}") unless cmd == '*' or COMMANDS.keys.include? cmd}
    p = @server.players[player]
    cmds.each{|cmd| p.revoke(cmd)}
    p.save
    "revoked #{cmds.inspect} from #{player}"
  end
end

class RollCommand < OreoCommand
  HELP = '/roll #d## [message] - Roll dice and broadcast the results. /roll 2d6 rolls 2 6 sided dice. Include a message to say what the roll is for'
  NOISY = true
  bind :roll
  
  def execute(dicespec, *msg)
    # /roll 1d20
    m = /^(\d+)d(\d+)$/.match(dicespec)
    raise ArgumentError.new "Invalid die: #{dicespec}" if m.nil?
    qty = m[1].to_i
    raise ArgumentError.new "You may not roll more than 20 dice" if qty > 20
    sides = m[2].to_i
    raise ArgumentError.new "You may not roll a die with more than 4,294,967,296 sides" if sides > 4294967296
    rolls = (0...qty).map{|i| (rand*sides).to_i+1}
    #sum = 0
    #rolls.each{|x| sum += x}
    "rolled #{qty} #{sides} sided #{qty == 1 and 'die' or 'dice'}#{msg.empty? and '' or ' '}#{msg.join(' ')}: #{rolls.join(' ')}"
  end
end

class SarcasmCommand < OreoCommand
  HELP = '/sarcasm - Be sarcastic'
  NOISY = true
  bind :sarcasm
  
  def execute()
    return 'is being sarcastic.'
  end
end

class SayCommand < OreoCommand
  HELP = '/say message - Speak with the big god voice'
  bind :say
  
  def execute(*args)
    @server.say(args.join(' '))
    return nil
  end
end

class StopCommand < OreoCommand
  HELP = '/stop <seconds> [message] - Shut down the server'
  NOISY = true
  bind :stop
  
  def execute(seconds, *message)
    @server.stop(seconds, message.join(' '))
    return nil
  end
end

class TeleportCommand < OreoCommand
  HELP = '/tp <player1> <player2> - Teleport player1 to player2'
  bind :tp
  
  def execute(player1,player2)
    player1 = autocomplete_online player1
    player2 = autocomplete_online player2
    @server.execute("tp #{player1} #{player2}")
    @server.tell(player1,"#{@user} teleported you to #{player2}") if @user != player1
    return "teleported #{player1} to #{player2}"
  end
end

class UnbanCommand < OreoCommand
  HELP = '/unban <player> - Unban player from the server'
  NOISY = true
  bind :unban
  
  def execute(player)
    player = autocomplete_player player
    @server.execute('pardon ' + player)
    return "unbanned #{player}"
  end
end

class VerboseCommand < OreoCommand
  HELP = '/verbose [level] - Change the verbosity level'
  bind :verbose
  
  def execute(level=nil)
    level = (@server.logger.output_level == :debug and :info or :debug) if level.nil?
    @server.logger.output_level = level.to_sym
    return "Now logging #{@server.logger.output_level}"
  end
end

class WhatcanCommand < OreoCommand
  HELP = '/whatcan <player> - See what commands player can use'
  bind :whatcan
  
  def execute(player)
    player = autocomplete_player player unless player == 'all'
    allowed = @server.permissions(player)
    return "#{player} can use #{(allowed.include? '*' and 'any command' or allowed.sort.join(', '))}"
  end
end

class WhisperCommand < OreoCommand
  HELP = '/w <player> <message> - whisper to a player'
  bind :w
  
  def execute(player,*args)
    player = autocomplete_online player
    @server.tell(player,"#{@user or 'CONSOLE'}: #{args.join(' ')}")
    return "@#{player}: #{args.join(' ')}"
  end
end

class WhocanCommand < OreoCommand
  HELP = '/whocan <command> - See who can use the given command'
  bind :whocan
  
  def execute(command)
    raise ArgumentError.new("Unrecognized command: #{command}") unless COMMANDS.keys.include? command
    return "#{command} can be used by: #{@server.players.values.select{|p| p.allowed? command}.map{|p| p.username}.sort.join(', ')}"
  end
end

class XPCommand < OreoCommand
  HELP = '/xp <player> <amount> - give a player XP'
  bind :xp
  
  def execute(player, amount)
    player = autocomplete_online player
    raise ArgumentError.new "Amount must be a number" unless amount =~ /\A\d+\Z/
    amount = amount.to_i
    raise ArgumentError.new "Amount must be between 1 and 5000" unless (1..5000).include? amount
    @server.execute "xp #{player} #{amount}"
    return "gave #{player} #{amount} xp"
  end
end

# Compound commands

class ForceGiveCommand < GiveCommand
  HELP = '/give! - Same as /give, but allows invalid item ID numbers'
  bind 'give!'
end

class ForceQuitCommand < StopCommand
  HELP = '/stop! - Force-quit the server'
  bind 'stop!'
  
  def execute
    begin
      @server.log "Forcing shutdown", :info
      begin
        require 'timeout'
        Timeout::timeout(20){super(0)}
      rescue Exception => e
        @server.log "Shutdown failure: #{e.message}", :error
        begin
          @io.close
        rescue Exception => e
          @server.log "Couldn't close pipe: #{e.message}"
        end
      end
      @server.log "Exiting...", :info
    ensure
      sleep 2
      exit(1)
    end
  end
end

class RestartCommand < StopCommand
  HELP = '/restart <seconds> [message] - Shut down the server and bring it back up again. See the stop command for more info.'
  bind :restart
  
  def execute(*args)
    super
    @server.start
    return nil
  end
end

class UpdateCommand < StopCommand
  HELP = '/update <oreo or minecraft> <seconds> [version] - Update the server. The server will be restarted if necessary.'
  NOISY = false
  bind :update
  
  def execute(kind,seconds,version=nil)
    case kind
      when 'minecraft'
        if version.nil?
          super(seconds, "Updating Minecraft to latest version")
          return (@server.update_minecraft and "updated Minecraft successfully" or "Minecraft failed to update")
        else
          super(seconds, "Updating Minecraft to version #{version}")
          return (@server.update_minecraft("http://assets.minecraft.net/#{version.gsub(/[^ -~]+/,'_')}/minecraft_server.jar") and "updated Minecraft successfully to version #{version}" or "Minecraft failed to update.")
        end
      when 'oreo'
        return "Oreo failed to update" unless @server.update_oreo
        return "updated Oreo successfully" if @server.reload
        super(seconds, "Completing Updates...")
        @server.log "Executing full reload...", :warn
        @server.reload!
      else
        raise ArugmentError.new('First argument must be "minecraft" or "oreo"')
    end
  end
end

# Special commands

if File.exists? '/usr/games/fortune'
  class FortuneCommand < OreoCommand
    HELP = '/fortune - receive a fortune'
    bind :fortune
    
    def execute()
      begin
        return `/usr/games/fortune -s`
      rescue Exception => e
        raise e if e.kind_of? StandardError
        log e, :error
        raise "Error retrieving fortune"
      end
    end
  end
end
