# frozen_string_literal: true

env :PATH, ENV['PATH']

job_type :command, 'cd :path && :task'
job_type :rake, 'cd :path && bundle exec rake :task'

# Every minute after 5am, until 3am
every '* 0-2,5-23 * * *' do
  rake 'announcer:run'
end

# Every day at 4am, git pull
every :day, at: '4:00 am' do
  command 'git pull; bundle exec whenever -w'
end
