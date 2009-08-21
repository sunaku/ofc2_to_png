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
#   gem install sinatra haml
#
#--
# Copyright protects this work.
# See LICENSE file for details.
#++

require 'base64'
require 'rubygems'
require 'sinatra'
require 'haml'

ERRORS = []

raise 'not enough arguments' if ARGV.length < 4
BROWSER, WIDTH, HEIGHT, *FILES = ARGV

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
  send_file FILES[num.to_i]
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
          = "Chart #{num}: #{FILES[num]}"

    :javascript
      var chart = null;

      // instantiate the next flash chart
      function setup() {
        chart = $('.chart:first');

        if (chart.length) {
          var flash = $('.flash', chart);

          // instantiate the flash chart
          swfobject.embedSWF(
            'open-flash-chart.swf',
            flash.attr('id'),
            #{WIDTH}, #{HEIGHT},
            '9.0.0', false,
            {'data-file': chart.attr('url')}
          );
        }
        else {
          $('body').text('You may close this window now.');
          $.get('/end'); // end loop: notify server about completion
        }
      }

      // OFC2 callback for the flash chart instantiated in render()
      function ofc_ready() {
        var flash = $('[id^=chart_]', chart).get(0);

        flash.render = function() {
          try {
            return this.get_img_binary();
          }
          catch(error) {
            $.post('/error', {'error': error, 'num': chart.attr('num')});
            return null;
          }
        }

        //
        // wait until the chart animation settles
        //
        var SAMPLE_DELAY = 250, MIN_STABLE_SAMPLES = 3;
        var prev_sample = null, num_stable_samples = 0;

        function wait_for_stability() {
          var curr_sample = flash.render();

          if (prev_sample == curr_sample) {
            num_stable_samples++;

            if (num_stable_samples >= MIN_STABLE_SAMPLES) {
              num_stable_samples = 0;
              upload(curr_sample);
              return;
            }
          }
          else {
            num_stable_samples = 0;
          }

          prev_sample = curr_sample;
          setTimeout(wait_for_stability, SAMPLE_DELAY); // loop
        }

        wait_for_stability();
      }

      // uploads the given image data to the
      // server and proceeds to the next chart
      function upload(image_data) {
        $.ajax({
          type: 'POST',
          url: chart.attr('url'),
          data: {'image': image_data},
          complete: function() {
            chart.remove();
            setup(); // continue loop: render the next chart
          }
        });
      }

      $(setup); // begin loop: render the first chart

