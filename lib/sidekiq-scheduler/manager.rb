require 'celluloid'
require 'redis'
require 'multi_json'

require 'sidekiq/util'

require 'sidekiq/scheduler'
require 'sidekiq-scheduler/schedule'

module SidekiqScheduler

  ##
  # The delayed job router in the system.  This
  # manages the scheduled jobs pushed messages
  # from Redis onto the work queues
  #
  class Manager
    include Sidekiq::Util
    include Celluloid

    def initialize(options={})
      @enabled = options[:scheduler]
      @resolution = options[:resolution] || 5

      Sidekiq::Scheduler.dynamic = options[:dynamic] || false
      Sidekiq.schedule = options[:schedule] if options[:schedule]
    end

    def stop
      @enabled = false
    end

    def start
      #Load the schedule into rufus
      #If dynamic is set, load that schedule otherwise use normal load
      if @enabled && Sidekiq::Scheduler.dynamic
        Sidekiq::Scheduler.reload_schedule!
      elsif @enabled
        Sidekiq::Scheduler.load_schedule!
      end

      schedule(true)
    end

    def reset
      clear_scheduled_work
    end

    private

    def clear_scheduled_work
      redis do |conn|
        queues = conn.zrange('delayed_queue_schedule', 0, -1).to_a
        conn.del(*queues.map { |t| "delayed:#{t}" }) unless queues.empty?
        conn.del('delayed_queue_schedule')
      end
    end

    def find_scheduled_work(timestamp)
      loop do
        break logger.debug("Finished processing queue for timestamp #{timestamp}") unless msg = redis { |r| r.lpop("delayed:#{timestamp}") }
        item = MultiJson.decode(msg)
        item['class'] = constantize(item['class']) # Sidekiq expects the class to be constantized.
        Sidekiq::Client.push(item)
      end
      Sidekiq::Client.remove_scheduler_queue(timestamp)
    end

    def find_next_timestamp
      timestamp = redis { |r| r.zrangebyscore('delayed_queue_schedule', '-inf', Time.now.to_i, :limit => [0, 1]) }
      if timestamp.is_a?(Array)
        timestamp = timestamp.first
      end
      timestamp.to_i unless timestamp.nil?
    end

    def schedule(run_loop = false)
      watchdog("Fatal error in sidekiq, scheduler loop died") do
        return if stopped?

        # Dispatch loop
        loop do
          Sidekiq::Scheduler.update_schedule if Sidekiq::Scheduler.dynamic
          break unless timestamp = find_next_timestamp
          find_scheduled_work(timestamp)
        end

        # This is the polling loop that ensures we check Redis every
        # second for work, even if there was nothing to do this time
        # around.
        after(@resolution) do
          schedule(run_loop)
        end if run_loop
      end
    end

    def stopped?
      !@enabled
    end
  end
end
