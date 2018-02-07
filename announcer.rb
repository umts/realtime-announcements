# frozen_string_literal: true

require 'json'
require 'net/http'
require 'optparse'
require 'pry-byebug'

module Announcer
  PVTA_API_URL = 'http://bustracker.pvta.com/InfoPoint/rest'

  CONFIG_FILE = 'config.json'
  MISSING_TEXT_FILE = 'missing_messages.log'
  QUERY_STOPS_FILE = 'stop_ids.txt'
  DEPARTURES_CACHE_FILE = 'cached_departures.json'
  AUDIO_COMMAND = File.read('audio_command.txt').strip
  SPEECH_COMMAND = File.read('speech_command.txt').strip

  @interval = 5
  @query_stops = %w[71 72 73]

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

  def set_interval
    return unless File.file? CONFIG_FILE
    config = JSON.parse File.read(CONFIG_FILE)
    @interval = config.fetch('interval') if config.key? 'interval'
  end

  def set_query_stops
    return unless File.file? QUERY_STOPS_FILE
    @query_stops = File.read(QUERY_STOPS_FILE).lines.map(&:strip)
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
      system AUDIO_COMMAND, file_path
    elsif file_data.to_a[1]
      _, route_id = file_data.to_a[1]
      file_path = "voice/#{dir}s/#{route_id}/#{name.tr '/', '-'}.wav"
      if File.file? file_path
        system AUDIO_COMMAND, file_path
      else say(name, route_id)
      end
    else say(name, route_id)
    end
  end

  def run
    set_query_stops
    set_interval
    departures = new_departures
    announcements = departures_crossed_interval(departures, cached_departures)
    cache_departures(departures)
    unless announcements.empty?
      play fragment: 'ding'
      announcements.each(&method(:make_announcement))
    end
  end

  def announce_all
    set_query_stops
    soonest_departures(new_departures).each do |announcement|
      make_announcement announcement.merge(options: { exclude_stop_name: true })
    end
  end

  def say(text, context)
    system SPEECH_COMMAND, text
    missing_messages = if File.file? MISSING_TEXT_FILE
                         File.read(MISSING_TEXT_FILE).lines.map(&:strip)
                       else []
                       end
    log_entry = text
    log_entry << " (#{context})" if context
    return if missing_messages.include? log_entry
    missing_messages << log_entry
    File.open MISSING_TEXT_FILE, 'w' do |file|
      file.puts missing_messages.sort
    end
  end
end
