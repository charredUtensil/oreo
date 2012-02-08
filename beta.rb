class MinecraftServer
end

class VersionCommand < OreoCommand
  HELP = '/version - print version numbers'
  bind :version
  
  def execute()
    return "Ruby #{RUBY_VERSION}\nOreo #{MinecraftServer::OREO_VERSION}" #TODO: Save Minecraft version
  end
end

class WhitelistCommand < OreoCommand
  HELP = '/whitelist <player> - add player to the whitelist'
  bind :whitelist
  
  def execute(player)
    player = autocomplete_player(player) #TODO: Does it make sense to autocomplete?
    @server.execute "whitelist add #{player}"
  end
end

class UnWhitelistCommand < OreoCommand
  HELP = '/unwhitelist <player> - remove player from the whitelist'
  bind :unwhitelist
  
  def execute(player)
    player = autocomplete_player(player) #TODO: Does it make sense to autocomplete?
    @server.execute "whitelist remove #{player}"
  end
end

class RepeatCommand < OreoCommand
  HELP = '/r - repeat previous command'
  #bind :r
  
  def execute
    #TODO: Check if user can execute command
    OreoCommand.execute(@server, @user, command, args)
  end
end

#Er... how do I display the recipes, and can I load them from Minecraft's jar?
#require 'yaml'
#class RecipeCommand < OreoCommand
#  RECIPES = YAML.load_file(OREO_DIRECTORY + '/recipes.yml')
#  
#  HELP = '/recipe <item> - gives the recipe for that item'
#  bind :recipe
#  
#  def execute()
#    dv = @server.items[match[:item].downcase]
#    dv = @server.items[OreoCommand.autocomplete(match[:item],@server.items.keys)] if dv.nil?
#    
#  end
#end

#To implement this, I need to kick the player and edit the nbt
#class MoveCommand < OreoCommand
#  HELP = '/move <player> <x> <y> <z> - kicks player from the server and teleport to the specified (x,y,z) co-ordinates'
#  bind :move
#end
