# frozen_string_literal: true

env :PATH, ENV['PATH']

job_type :rake, 'cd :path && bundle exec rake :task'

# Every minute after 5am, until 3am
every '* 0-2,5-23 * * *' do
  rake 'announcer:run'
end
