#!/usr/bin/env ruby -w
# A Web Thingy to show you weather data in an interesting way

require 'rubygems'
require 'open-uri'
require 'date'
require 'csv'
require 'json'
require 'rack/cache'
require 'rack/contrib'

# Return JSON weather data
weather_json = Proc.new {|env|

  datauri = "http://www.climate.weatheroffice.ec.gc.ca/climateData/" <<
            "bulkdata_e.html?timeframe=1&format=csv&type=hly" 

  req = Rack::Request.new(env)

  if req.params["fyear"] and req.params["fmonth"]
    from = Date.new(y=req.params["fyear"].to_i,
                    m=req.params["fmonth"].to_i, d=1)
  #TODO: parse epoch dates
  #elsif req.params["from"]
    #from = Date.new(
  else
    from = Date.today
  end

  if req.params["tyear"] and req.params["tmonth"]
    to = Date.new(y=req.params["tyear"].to_i,
                  m=req.params["tmonth"].to_i, d=1)
  else
    to = Date.today
  end

  # Make sure our date range is sane
  if from > to 
    ret = [400, { 'Content-Type' => 'text/plain' },
            "Bad date range (from is biger than to). " <<
            "Maybe you should have gone somewhere nicer?"  ]
  end

  if req.params["station"]
    station = req.params["station"]
  else
    station = 1
  end


  # Grab all of our weather data in CSV, return as JSON
  weather_in_csv = ""
  from.year.upto(to.year) {|this_year|

    if from.year == this_year then
      from_month = from.month
    else
      from_month = 1
    end

    if to.year == this_year then
      to_month = to.month
    else
      to_month = 12
    end

    puts "DEBUG - Getting data from %s to %s" % [from.to_s, to.to_s]
    from_month.upto(to_month) { |this_month|
      
      this_uri = datauri + "&Year=%d&Month=%d&Day=%d&StationID=%d" %
                            [this_year, this_month, 0, station]
      # Grab weather and remove headers in CSV that we don't need.
      weather_in_csv << URI.parse(this_uri).read.gsub(/.*"Weather"\n(.*)/m, '\1')
    }
  }
  parsed_weather = CSV.parse(weather_in_csv)

  t_at_time = {}

  parsed_weather.each{|row|
    if row[5] != "" then
      time = DateTime.parse(row[0]).strftime(fmt="%s")
      t_at_time[time] = row[5]
    end
  }

  if ret # has already been defined above
    ret
  else
    json = JSON.generate t_at_time
    # Cache always expires at 1 am next day
    [200, { 'Content-Type' => 'text/plain', 
            'Expires' => (Time.now + 86_400).strftime("%a, %d %b %Y 01:00:00 %Z"),
            'Cache-Control' => 'max-age=86400, must-revalidate'}, json]
  end
}

# Stolen from Rack::Cache
class Rewriter < Struct.new(:app)
  def call(env)
    if env['PATH_INFO'] =~ /\/$/
      env['PATH_INFO'] += 'index.html'
    end
    app.call(env)
  end
end


builder = Rack::Builder.new do

  use Rack::Lint
  use Rewriter
  #use Rack::ETag
  use Rack::Cache, :verbose     => true, :metastore   => 'file:./tmp/rack/meta', :entitystore => 'file:./tmp/rack/body'

  map '/' do
    run Rack::File.new('public/')
  end

  # Give us some weather data
  map '/weatherdata' do
    run weather_json
  end
end

run builder
