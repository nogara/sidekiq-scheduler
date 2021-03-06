# SidekiqScheduler

# Warning!

The original function of this gem was to add delayed jobs for a fixed amount of time. 
This has been available directly within Sidekiq since Version 2.0. A lot of this code
should be considered redundant and might even conflict with the latest Sidekiq release.

Since I have upgraded my projects that made use of this gem to the core Sidekiq functions and
no longer make active use of this gem this project should be considered largely unmaintained.

## Description

sidekiq-scheduler is an extension to [Sidekiq](http://github.com/mperham/sidekiq)
that adds support for queueing jobs in the future.

This table explains the version requirements for redis

| sidekiq-scheduler version | required redis version|
|:--------------------------|----------------------:|
| >= 1.0.0                  | >= 2.2.0              |

Job scheduling is supported in two different way: Recurring (scheduled) and
Delayed.

Scheduled jobs are like cron jobs, recurring on a regular basis.  Delayed
jobs are resque jobs that you want to run at some point in the future.
The syntax is pretty explanatory:

    MyWorker.perform_in(5.days, 'arg1', 'arg2') # run a job in 5 days
    # or
    MyWorker.perform_at(5.days.from_now, 'arg1', 'arg2') # run job at a specific time

### Documentation

This README covers what most people need to know. If you're looking for
details on individual methods, you might want to try the [rdoc](http://rdoc.info/github/yabawock/sidekiq-scheduler/master/frames).


## Installation

    #To install:
    gem install sidekiq-scheduler

    #If you use a Gemfile:
    gem 'sidekiq-scheduler'

    #Starting the scheduler
    bundle exec sidekiq-scheduler

The scheduler will perform identically to a normal sidekiq worker with
an additional scheduler thread being run - in the default configuration
this will result in 25 worker threads being available on the scheduler
node but all normal configuration options apply.

NOTE: Since it's currently not possible to hook into the default option
parsing provided by sidekiq you will need to use a configuration file to
override the scheduler options.
Available options are:

    :resolution: <seconds between schedule runs>
    :schedule: <the schedule to be run>
    :dynamic: <if true the schedule can we modified in runtime>

The scheduling thread will sleep this many seconds between looking for
jobs that need moving to the worker queue. The default is 5 seconds
which should be fast enough for almost all uses.

NOTE: You DO NOT want to run more than one instance of the scheduler.  Doing
so will result in the same job being queued multiple times.  You only need one
instance of the scheduler running per application, regardless of number of servers.

NOTE: If the scheduler thread goes down for whatever reason, the delayed items
that should have fired during the outage will fire once the scheduler is
started back up again (even if it is on a new machine).

## Delayed jobs

Delayed jobs are one-off jobs that you want to be put into a queue at some point
in the future. The classic example is sending email:

    MyWorker.perform_in(5.days, current_user.id)

This will store the job for 5 days in the Sidekiq delayed queue at which time
the scheduler will pull it from the delayed queue and put it in the appropriate 
work queue for the given job. It will then be processed as soon as a worker is 
available (just like any other Sidekiq job).

The `5.days` syntax will only work if you are using ActiveSupport (Rails). If you
are not using Rails, just provide `perform_in` with the number of seconds.

NOTE: The job does not fire **exactly** at the time supplied. Rather, once that
time is in the past, the job moves from the delayed queue to the actual work
queue and will be completed as workers are free to process it.

Also supported is `MyWork.perform_at` which takes a timestamp to queue the job.

The delayed queue is stored in redis and is persisted in the same way the
standard Sidekiq jobs are persisted (redis writing to disk). Delayed jobs differ
from scheduled jobs in that if your scheduler process is down or workers are
down when a particular job is supposed to be processed, they will simply "catch up"
once they are started again.  Jobs are guaranteed to run (provided they make it
into the delayed queue) after their given queue_at time has passed.

One other thing to note is that insertion into the delayed queue is O(log(n))
since the jobs are stored in a redis sorted set (zset).  I can't imagine this
being an issue for someone since redis is stupidly fast even at log(n), but full
disclosure is always best.

### Removing Delayed jobs

If you have the need to cancel a delayed job, you can do it like this:

    # after you've enqueued a job like:
    MyWorker.perform_at(5.days.from_now, 'arg1', 'arg2')
    # remove the job with exactly the same parameters:
    MyWorker.remove_delayed(<timestamp>, 'arg1', 'arg2')

## Scheduled Jobs (Recurring Jobs)

Scheduled (or recurring) jobs are logically no different than a standard cron
job.  They are jobs that run based on a fixed schedule which is set at
startup.

The schedule is a list of Resque worker classes with arguments and a
schedule frequency (in crontab syntax).  The schedule is just a hash, but
is most likely stored in a YAML like so:

    CancelAbandonedOrders:
      cron: "*/5 * * * *"

    queue_documents_for_indexing:
      cron: "0 0 * * *"
      # you can use rufus-scheduler "every" syntax in place of cron if you prefer
      # every: 1hr
      # By default the job name (hash key) will be taken as worker class name.
      # If you want to have a different job name and class name, provide the 'class' option
      class: QueueDocuments
      queue: high
      args:
      description: "This job queues all content for indexing in solr"

    clear_leaderboards_contributors:
      cron: "30 6 * * 1"
      class: ClearLeaderboards
      queue: low
      args: contributors
      description: "This job resets the weekly leaderboard for contributions"

You can provide options to "every" or "cron" via Array:

    clear_leaderboards_moderator:
      every: ["30s", :first_in => '120s']
      class: CheckDaemon
      queue: daemons
      description: "This job will check Daemon every 30 seconds after 120 seconds after start"


NOTE: Six parameter cron's are also supported (as they supported by
rufus-scheduler which powers the sidekiq-scheduler process).  This allows you
to schedule jobs per second (ie: "30 * * * * *" would fire a job every 30
seconds past the minute).

A big shout out to [rufus-scheduler](http://github.com/jmettraux/rufus-scheduler)
for handling the heavy lifting of the actual scheduling engine.

### Time zones

Note that if you use the cron syntax, this will be interpreted as in the server time zone
rather than the `config.time_zone` specified in Rails.

You can explicitly specify the time zone that rufus-scheduler will use:

    cron: "30 6 * * 1 Europe/Stockholm"

Also note that `config.time_zone` in Rails allows for a shorthand (e.g. "Stockholm")
that rufus-scheduler does not accept. If you write code to set the scheduler time zone
from the `config.time_zone` value, make sure it's the right format, e.g. with:

    ActiveSupport::TimeZone.find_tzinfo(Rails.configuration.time_zone).name

A future version of sidekiq-scheduler may do this for you.

## Using with Testing

Sidekiq uses a jobs array on workers for testing, which is supported by sidekiq-scheduler when you require the test code:

    require 'sidekiq/testing'
    require 'sidekiq-scheduler/testing'
    
    MyWorker.perform_in 5, 'arg1'
    puts MyWorker.jobs.inspect

## Note on Patches / Pull Requests

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a future version unintentionally.
* Commit, do not mess with rakefile, version, or history.
  (if you want to have your own version, that is fine but bump version in a commit by itself I can ignore when I pull)
* Send me a pull request. Bonus points for topic branches.

## Credits

This work is a partial port of [resque-scheduler](https://github.com/bvandenbos/resque-scheduler) by Ben VandenBos.  
Modified to work with the Sidekiq queueing library by Morton Jonuschat.

Scheduling of recurring jobs has been addet to v0.4.0, thanks to [Adrian Gomez](https://github.com/adrian-gomez).

## Maintainers

* [Morton Jonuschat](https://github.com/yabawock)

## License

MIT License

## Copyright

Copyright 2012 Morton Jonuschat  
Some parts copyright 2010 Ben VandenBos  
