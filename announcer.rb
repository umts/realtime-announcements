# frozen_string_literal: true

require 'json'
require 'net/http'
require 'octokit'
require 'pry-byebug'

module Announcer
  PVTA_API_URL = 'http://bustracker.pvta.com/InfoPoint/rest'

  CONFIG_FILE = 'config.json'
  MISSING_TEXT_FILE = 'missing_messages.tmp'
  PRESENT_TEXT_FILE = 'present_messages.tmp'
  QUERY_STOPS_FILE = 'stop_ids.txt'
  DEPARTURES_CACHE_FILE = 'cached_departures.json'
  AUDIO_COMMAND = File.read('audio_command.txt').strip
  SPEECH_COMMAND = File.read('speech_command.txt').strip
  GITHUB_TOKEN = File.read('github_token.txt').strip

  @interval = 5
  @query_stops = %w[71 72 73]

  def announce_all
    set_query_stops
    soonest_departures(new_departures).each do |announcement|
      make_announcement announcement.merge(options: { exclude_stop_name: true })
    end
    update_github_issues!
    remove_temp_files!
  end

  def announcements_in_progress?
    File.file?(MISSING_TEXT_FILE) || File.file?(PRESENT_TEXT_FILE)
  end

  def cache_departures(departures)
    File.open DEPARTURES_CACHE_FILE, 'w' do |file|
      file.puts departures.to_json
    end
  end

  def cached_departures
    if File.file? DEPARTURES_CACHE_FILE
      JSON.parse File.read(DEPARTURES_CACHE_FILE)
    else {}
    end
  end

  def departures_crossed_interval(new_departures, old_departures)
    departures = []
    old_departures.each_pair do |stop_id, route_directions|
      route_directions.each_pair do |route_dir_data, trips|
        route_id, sign = route_dir_data.match(/\A\["(.*)", "(.*)"\]\z/).captures
        trips.each_pair do |trip_id, old_interval|
          stop_departures = new_departures[stop_id]
          if stop_departures
            route_dir_departures = stop_departures[[route_id, sign]]
          end
          if route_dir_departures
            new_interval = new_departures[stop_id][[route_id, sign]][trip_id]
          end
          if new_interval && old_interval > @interval && new_interval <= @interval
            departures << { route_id: route_id, headsign: sign,
                            stop_id: stop_id, interval: new_interval }
          end
        end
      end
    end
    departures
  end

  def issue_body
    "Reported on #{Time.now.strftime '%A, %B %-e, %Y at %-l:%m %P'}."
  end

  def issue_title(message_data)
    "Missing announcement #{message_data}"
  end

  def log_entries(log_file)
    if File.file? log_file
      File.read(log_file).lines.map(&:strip)
    else []
    end
  end

  def make_announcement(route_id:, headsign:, stop_id:, interval:, options: {})
    play route:    route_id
    play fragment: 'toward'
    play headsign: headsign, route_id: route_id
    if options[:exclude_stop_name]
      play fragment: 'will be leaving'
    else
      play fragment: 'will be leaving from'
      play stop:     stop_id
    end
    if interval < 1
      play fragment: 'now'
    elsif interval == 1
      play fragment: 'in 1 minute'
    elsif interval < 60
      play fragment: "in #{interval} minutes"
    else
      hour, minute = interval.divmod 60
      if hour == 1
        play fragment: 'in 1 hour'
      else play fragment: "in #{hour} hours"
      end
      unless minute == 0
        play fragment: 'and'
        play fragment: "#{minute} minutes"
      end
    end
    sleep 0.5
  end

  def new_departures
    departures = {}
    @query_stops.each do |stop_id|
      departures[stop_id] = {}
      departure_uri = URI("#{PVTA_API_URL}/stopdepartures/get/#{stop_id}")
      departure_data = JSON.parse Net::HTTP.get(departure_uri)
      route_directions = departure_data.first.fetch 'RouteDirections'
      route_directions.each do |route_dir|
        route_id = route_dir.fetch('RouteId').to_s
        route_dir_data = route_dir.fetch 'Departures'
        route_dir_data.each do |departure|
          trip = departure.fetch 'Trip'
          headsign = trip.fetch 'InternetServiceDesc'
          trip_id = trip.fetch('TripId').to_s
          timestamp = departure.fetch 'EDT'
          match_data = timestamp.match %r{/Date\((\d+)000-0[45]00\)/}
          timestamp_minutes = match_data.captures.first.to_i / 60
          minutes_now = Time.now.to_i / 60
          interval = timestamp_minutes - minutes_now
          departures[stop_id][[route_id, headsign]] ||= {}
          departures[stop_id][[route_id, headsign]][trip_id] = interval
        end
      end
    end
    departures
  end

  def play(file_data)
    dir, name = file_data.to_a[0]
    file_path = "voice/#{dir}s/#{name}.wav"
    if File.file? file_path
      # system AUDIO_COMMAND, file_path
      record_log_entry(PRESENT_TEXT_FILE, name, dir)
    elsif file_data.to_a[1]
      _, route_id = file_data.to_a[1]
      file_path = "voice/#{dir}s/#{route_id}/#{name.tr '/', '-'}.wav"
      if File.file? file_path
        # system AUDIO_COMMAND, file_path
        record_log_entry(PRESENT_TEXT_FILE, name, "route #{route_id}")
      else say(name, "route #{route_id}")
      end
    else say(name, dir)
    end
  end

  def record_log_entry(log_file, message, context)
    messages = log_entries(log_file)
    log_entry = message
    log_entry += " (#{context})" if context
    return if messages.include? log_entry
    messages << log_entry
    File.open log_file, 'w' do |file|
      file.puts messages.sort
    end
  end

  def remove_temp_files!
    FileUtils.rm MISSING_TEXT_FILE if File.file? MISSING_TEXT_FILE
    FileUtils.rm PRESENT_TEXT_FILE if File.file? PRESENT_TEXT_FILE
  end

  def run
    set_query_stops
    set_interval
    departures = new_departures
    announcements = departures_crossed_interval(departures, cached_departures)
    cache_departures(departures)
    unless announcements.empty? || announcements_in_progress?
      announcements.each(&method(:make_announcement))
      update_github_issues!
      remove_temp_files!
    end
  end

  def say(text, context)
    # system SPEECH_COMMAND, text
    record_log_entry(PRESENT_TEXT_FILE, text, context)
  end

  def set_interval
    return unless File.file? CONFIG_FILE
    config = JSON.parse File.read(CONFIG_FILE)
    @interval = config.fetch('interval') if config.key? 'interval'
  end

  def set_query_stops
    return unless File.file? QUERY_STOPS_FILE
    @query_stops = File.read(QUERY_STOPS_FILE).lines.map(&:strip)
  end

  def soonest_departures(departures)
    departure_attrs = []
    departures.each_pair do |stop_id, route_directions|
      route_directions.each_pair do |(route_id, sign), trips|
        departure_attrs << { route_id: route_id, headsign: sign,
                             stop_id: stop_id, interval: trips.values.min }
      end
    end
    departure_attrs
  end

  def update_github_issues!
    missing_messages = log_entries(MISSING_TEXT_FILE).map(&method(:issue_title))
    present_messages = log_entries(PRESENT_TEXT_FILE).map(&method(:issue_title))
    client = Octokit::Client.new access_token: GITHUB_TOKEN
    open_issues = client.list_issues 'umts/realtime-announcements', labels: 'automated'
    open_issues.each do |issue|
      if missing_messages.include? issue.title
        # We already know it's missing.
        missing_messages.delete issue.title
      end
      if present_messages.include? issue.title
        # It's present now! We can close the issue.
        client.close_issue 'umts/realtime-announcements', issue.number
        client.add_comment 'umts/realtime-announcements', issue.number, issue_body
      end
    end
    # If any missing messages are left, they're new, and should be reported.
    missing_messages.each do |title|
      client.create_issue 'umts/realtime-announcements', title, issue_body, labels: 'automated'
    end
  end
end
