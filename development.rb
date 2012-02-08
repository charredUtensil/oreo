# Development and beta stuff - not intended for normal use

puts "LOADING DEVELOPMENT TOOLS..."

#>--<{ DEBUGGING COMMANDS }>--<#

class ReloadCommand < OreoCommand
  HELP = '/reload - Reload Oreo dev copy from disk'
  bind :reload
  
  def execute
    devdir = MinecraftServer::OREO_DIRECTORY.sub(/[\\\/]?$/,'_dev')
    if File.directory? devdir
      system "cp -r #{devdir}/* #{MinecraftServer::OREO_DIRECTORY}"
    end
    return (@server.reload and "Oreo reloaded" or "Oreo reload failed")
  end
end

class ForceReloadCommand < StopCommand
  HELP = '/reload! <seconds> [message] - Restart the server and force a full reload of Oreo'
  bind 'reload!'
  
  def execute(*args)
    super
    @server.reload!
  end
end

class RubyCommand < OreoCommand
  HELP = '/ruby! <command> - execute raw ruby code and return its inspected value'
  bind 'ruby!'
  
  def execute(*args)
    begin
      return eval(args.join(' ')).inspect
    rescue Exception => e
      return "#{e.class}:#{e.message}\n#{e.backtrace.join("\n")}"
    end
  end
end

class SystemCommand < OreoCommand
  HELP = '/system! <command> - execute a raw command on the system and return what it prints'
  bind 'system!'
  
  def execute(*args)
    return `#{args.join ' '}`
  end
end

class UploadCommand < OreoCommand
  HELP = 'don\'t use'
  bind 'upload!'
  
  def execute(user, server)
    raise "Failed to tar" unless system("cd #{MinecraftServer::OREO_DIRECTORY}; tar -czf oreo.tgz * 2>&1")
    raise "Failed to upload" unless system("scp #{MinecraftServer::OREO_DIRECTORY}/oreo.tgz #{user}@#{server}:public_html/oreo/#{MinecraftServer::OREO_VERSION}.tgz")
    raise "Failed to symlink" unless system("ssh #{user}@#{server} 'cd public_html/oreo; rm current.tgz; ln -s #{MinecraftServer::OREO_VERSION}.tgz current.tgz'")
  end
end

#>--<{ BETA STUFF }>--<#

begin
  beta_file = File.expand_path(File.dirname(__FILE__)+'/beta.rb')
  require beta_file if File.exists? beta_file
rescue Exception => e
  puts "Error while loading beta code:\n  #{e.class}: #{e.message}\n#{e.backtrace.map{|x| '  '+x}.join("\n")}"
end

