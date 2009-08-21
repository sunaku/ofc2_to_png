#!/usr/bin/env ruby
#
# Renders OFC2 chart description files as PNG images.
#
# = Usage
#
#   ruby ofc2_to_png.rb <BROWSER> <WIDTH> <HEIGHT> <CHART...>
#
#   For each given <CHART>, a corresponding <CHART>.png file is written.
#
# = Arguments
#
#   BROWSER:: Shell command for launching a browser that supports Flash 9+
#             and whose process can be killed without external consequences.
#
#   WIDTH::   Width of a rendered PNG image (measured in pixels).
#
#   HEIGHT::  Height of a rendered PNG image (measured in pixels).
#
#   CHART::   An OFC2 chart description file (written in JSON format).
#
# = Requirements
#
#   gem install sinatra haml json
#
#--
# Copyright protects this work.
# See LICENSE file for details.
#++

require 'base64'
require 'rubygems'
require 'sinatra'
require 'haml'
require 'json'

ERRORS = []

raise 'not enough arguments' if ARGV.length < 4
BROWSER, WIDTH, HEIGHT, *FILES = ARGV

# load the OFC2 chart description files
JSONS = FILES.map do |file|
  json = File.read(file)

  begin
    data = JSON.parse(json)

    # disable all animation in the chart
    if elements = data['elements']
      elements.each do |elem|
        elem['animate'] = false
      end
    end

    data.to_json

  rescue JSON::ParserError, JSON::GeneratorError
    json # use the original JSON read from the file
  end
end

# launch the browser as a subprocess
BROWSER_PID = Thread.new do
  sleep 3 # wait for the web server to start
  IO.popen("#{BROWSER} http://127.0.0.1:4567/").pid
end.value

get '/' do
  haml :index
end

# send JSON chart description from filesystem to flash
get '/chart/:num' do |num|
  JSONS[num.to_i]
end

# save image data posted from flash to filesystem
post '/chart/:num' do |num|
  image_file = FILES[num.to_i] + '.png'
  image_data = Base64.decode64(params[:image])

  open(image_file, 'wb') {|f| f << image_data }
  puts "WROTE: #{image_file}"
  nil
end

# display flash errors and propagate exit status
post '/error' do
  file = FILES[params[:num].to_i]
  error = params[:error]
  ERRORS << error

  warn "ERROR in #{file}: #{error}"
  nil
end

# close the browser and terminate this program
get '/end' do
  begin
    Process.kill :SIGTERM, BROWSER_PID
  rescue => e
    warn "Could not kill the browser process (pid=#{BROWSER_PID}) with SIGTERM because #{e.inspect}; you must kill it by hand instead."
  end

  exit! [255, ERRORS.length].min
end

__END__

@@ index
!!!
%html
  %head
    %title= $0
    %script{:type => 'text/javascript', :src => 'swfobject-2.2.min.js'}
    %script{:type => 'text/javascript', :src => 'jquery-1.3.2.min.js'}
  %body
    - FILES.length.times do |num|
      - chart_id = "chart_#{num}"
      - chart_url = "/chart/#{num}"

      .chart{:url => chart_url, :num => num}
        .flash{:id => chart_id}
          :javascript
            swfobject.embedSWF(
              'open-flash-chart.swf',
              #{chart_id.inspect},
              #{WIDTH}, #{HEIGHT},
              '9.0.0', false,
              {'data-file': #{chart_url.inspect} }
            );

    :javascript
      function start() {
        // wait until all swfobject instances take effect
        if ($('.flash').length == 0) {
          setTimeout(function() {

            // rasterize and upload all charts
            $('.chart').each(function() {
              var chart = $(this);
              var image = null;

              try {
                var flash = $('object', chart).get(0);
                image = flash.get_img_binary();
              }
              catch(error) {
                $.post('/error', {'error': error, 'num': chart.attr('num')});
              }

              $.post(chart.attr('url'), {'image': image});
              chart.remove();
            });

            $('body').text('You may close this window now.');
            $.get('/end'); // notify server about completion

          }, 7000); // wait for chart animations to finish
        }
        else {
          setTimeout(start, 2500);
        }
      }

      $(start);

