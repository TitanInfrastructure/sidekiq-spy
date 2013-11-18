require 'sidekiq'


module SidekiqSpy
  class App
    
    attr_reader :running
    attr_reader :restarting
    
    def initialize
      @running    = false
      @restarting = false
      @threads    = {}
    end
    
    def config
      @config ||= Config.new
    end
    
    def configure
      yield config
      
      configure_sidekiq
    end
    
    def start
      begin
        @running = true
        
        setup
        
        @threads[:command] ||= Thread.new do
          command_loop # listen for commands
        end
        
        @threads[:refresh] ||= Thread.new do
          refresh_loop # refresh frequently
        end
        
        @threads.each { |tname, t| t.join }
      ensure
        cleanup
      end
    end
    
    def stop
      @running = false
      
      @threads.each { |tname, t| t.run if t.status == 'sleep' } # wakey, wakey
    end
    
    def restart
      @restarting = true
    end
    
    def do_command(key)
      case key
      when 'q' # quit
        stop
      end
    end
    
    private
    
    def configure_sidekiq
      Sidekiq.configure_client do |sidekiq_config|
        sidekiq_config.logger = nil
        sidekiq_config.redis = {
          :url       => config.url,
          :namespace => config.namespace,
        }
      end
    end
    
    def setup
      @screen = Display::Screen.new
    end
    
    def cleanup
      @screen.close if @screen
    end
    
    def command_loop
      while @running do
        next unless @screen # #refresh_loop might be reattaching screen
        
        key = @screen.next_key
        
        next unless key # keep listening if timeout
        
        do_command(key)
      end
    end
    
    def refresh_loop
      while @running do
        next unless @screen # HACK: only certain test scenarios?
        
        if @restarting || @screen.missized? # signal(s) or whilst still resizing
          cleanup
          
          setup
          
          @restarting = false
        end
        
        @screen.refresh
        
        sleep config.interval # go to sleep; could be rudely awoken on quit
      end
    end
    
  end
end
