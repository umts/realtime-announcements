job_type :ruby, "cd :path && bundle exec ruby :task.rb"

every '* 0-2,5-23 * * *' do
  ruby 'announcer'
end
