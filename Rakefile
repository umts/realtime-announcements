# frozen_string_literal: true

require_relative 'announcer'
include Announcer

namespace :announcer do
  desc 'Announce all departures regardless of how far in advance'
  task :announce_all do
    Announcer.announce_all
  end

  desc 'Announce any unannounced departures occurring in 5 minutes or fewer'
  task :run do
    Announcer.run
  end
end
