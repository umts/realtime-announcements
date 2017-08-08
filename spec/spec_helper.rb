# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  add_filter '/config/'
  add_filter '/spec/'
end

require 'rspec'
require 'timecop'
require 'webmock/rspec'

require_relative '../announcer'
