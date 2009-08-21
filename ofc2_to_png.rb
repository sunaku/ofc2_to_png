#!/usr/bin/env ruby
#
# Renders OFC2 chart description files as PNG images.
#
# = Usage
#
#   ruby ofc2_to_png.rb <BROWSER> <THREADS> <WIDTH> <HEIGHT> <CHART...>
#
#   For each given <CHART>, a corresponding <CHART>.png file is written.
#
# = Arguments
#
#   BROWSER:: Shell command for launching a browser that supports Flash 9+
#             and whose process can be killed without external consequences.
#
#   THREADS:: Number of Flash applets the browser can tolerate at a time.
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

require 'socket'
require 'base64'
require 'rubygems'
require 'sinatra'
require 'haml'

ERRORS = []

raise 'not enough arguments' if ARGV.length < 5
BROWSER, THREADS, WIDTH, HEIGHT, *FILES = ARGV

# start server on random port number
host, port = TCPServer.open('') {|s| s.addr.values_at(3, 1) }
set :port, port

# launch the browser in subprocess
BROWSER_PID = Thread.new do
  sleep 3 # wait for the web server to start
  IO.popen("#{BROWSER} http://#{host}:#{port}/").pid
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

      .chart{:url => chart_url, :num => num, :pending => true}
        = "Chart #{num}: #{FILES[num]}"

        - # placeholder for the flash applet
        .flash{:id => chart_id}

    :javascript
      function process_chart(chart) {
        chart.removeAttr('pending').css('font-weight', 'bold');

        //
        // instantiate the flash applet
        //
        var flash = $('.flash', chart);

        swfobject.embedSWF(
          'open-flash-chart.swf', flash.attr('id'), #{WIDTH}, #{HEIGHT},
          '9.0.0', false, {'data-file': chart.attr('url')}, false, false,
          function(event) {
            var flash = event.ref;

            //
            // move flash applet off-screen to improve browser performance
            //
            $(flash).css({
              position: 'absolute',
              top: -#{HEIGHT.to_i + 10},
              left: -#{WIDTH.to_i + 10}
            });

            //
            // wait until the chart animation settles before rendering image
            //
            var SAMPLE_DELAY = 200, MIN_STABLE_SAMPLES = 3;
            var prev_sample = null, num_stable_samples = 0;

            function wait_for_stability() {
              if (flash.get_img_binary) {
                var curr_sample = null;

                try {
                  curr_sample = flash.get_img_binary();
                }
                catch(error) {
                  $.post('/error', {'error': error, 'num': chart.attr('num')});
                }

                if (prev_sample == curr_sample) {
                  num_stable_samples++;

                  if (num_stable_samples >= MIN_STABLE_SAMPLES) {
                    //
                    // chart is stable now, we can render & upload
                    //
                    $.post(chart.attr('url'), {'image': curr_sample});

                    chart.remove();
                    process_next_chart();

                    return;
                  }
                }
                else {
                  num_stable_samples = 0;
                }

                prev_sample = curr_sample;
              }

              setTimeout(wait_for_stability, SAMPLE_DELAY); // loop
            }

            wait_for_stability();
          }
        );
      }

      function process_next_chart() {
        var next_chart = $('.chart[pending]:first');
        if (next_chart.length) {
          process_chart(next_chart);
        }
        else {
          $('body').text('You may close this window now.');
          $.get('/end'); // notify server about completion
        }
      }

      $(function() {
        for (var i = 0; i < #{THREADS}; i++) {
          setTimeout(process_next_chart, i * 3); // stagger the threads in time
        }
      });

