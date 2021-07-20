# frozen_string_literal: true

require_relative 'announcer'

namespace :announcer do
  desc 'Announce all departures regardless of how far in advance'
  task :announce_all do
    announcer = Class.new { extend Announcer }
    begin
      announcer.announce_all
    ensure
      announcer.remove_temp_files!
    end
  end

  desc 'Announce any unannounced departures occurring in 5 minutes or fewer'
  task :run do
    announcer = Class.new { extend Announcer }
    begin
      announcer.run
    ensure
      announcer.remove_temp_files!
    end
  end
end
