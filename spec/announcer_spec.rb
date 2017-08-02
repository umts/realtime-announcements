# frozen_string_literal: true

require 'spec_helper'

include Announcer

describe Announcer do
  describe 'run' do
    before :each do
      expect_any_instance_of(Announcer).to receive(:set_query_stops)
      expect_any_instance_of(Announcer).to receive(:set_interval)
      expect_any_instance_of(Announcer).to receive(:new_departures)
        .and_return :departures
      expect_any_instance_of(Announcer).to receive(:cached_departures)
        .and_return :cached_departures
      expect_any_instance_of(Announcer)
        .to receive(:departures_crossed_interval)
        .with(:departures, :cached_departures)
        .and_return departures_to_announce
      expect_any_instance_of(Announcer).to receive(:cache_departures)
        .with :departures
    end
    context 'with departures to announce' do
      let(:departures_to_announce) { [:departure_to_announce] }
      it 'makes announcements' do
        expect_any_instance_of(Announcer).to receive(:make_announcement)
          .with(:departure_to_announce)
        run
      end
    end
    context 'with no departures to announce' do
      let(:departures_to_announce){ [] }
      it 'makes no announcements' do
        expect_any_instance_of(Announcer).not_to receive(:make_announcement)
        run
      end
    end
  end

  describe 'set_query_stops' do
    before :each do
      stub_const 'Announcer::QUERY_STOPS_FILE', :stops_file
      expect(File).to receive(:file?).with(:stops_file).and_return file_present
      @query_stops = :default_stops
    end
    context 'with no query stops file' do
      let(:file_present) { false }
      it 'keeps the default query stops' do
        set_query_stops
        expect(@query_stops).to be :default_stops
      end
    end
    context 'with a query stops file' do
      let(:file_present) { true }
      let(:lines) { ['STOP_ID     '] }
      before :each do
        expect(File).to receive(:read).with(:stops_file)
          .and_return double lines: lines
      end
      it 'reads the lines from the file to set the query stops' do
        set_query_stops
        expect(@query_stops).to include 'STOP_ID'
      end
    end
  end
end
