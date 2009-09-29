#!/usr/bin/env ruby
#
# Converts Open Flash Chart 2 <http://teethgrinder.co.uk/open-flash-chart-2/>
# chart description files (which are written in JSON format) into PNG images.
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

# show help information
if ARGV.any? {|a| a =~ /^-h|--help$/ } or ARGV.length < 5
  puts File.read(__FILE__).split(/^$/).first
  exit
end

require 'socket'
require 'base64'
require 'open-uri'
require 'rubygems'
require 'sinatra'
require 'haml'

ERRORS = []
BROWSER, THREADS, WIDTH, HEIGHT, *FILES = ARGV

# start server on random port number
host = '127.0.0.1'
port = TCPServer.open('') {|s| s.addr[1] }
set :port, port

# launch web browser in subprocess
browser_pid = nil
Thread.new do
  puts url = "http://#{host}:#{port}/"

  # wait for server to become ready
  begin
    open url
  rescue
    Thread.pass
    retry
  end

  browser_pid = IO.popen("#{BROWSER} #{url}").pid
end

# search relative to this file for static assets
set :root, File.dirname(__FILE__)

# send initial web page which bootstraps the flash to image conversion process
get '/' do
  haml :index # see bottom of this file, below __END__
end

# send JSON chart description from filesystem to flash
get '/chart/:id' do |id|
  send_file FILES[id.to_i]
end

# save image data posted from flash to filesystem
post '/chart/:id' do |id|
  image_file = FILES[id.to_i] + '.png'
  image_data = Base64.decode64(params[:image])

  open(image_file, 'wb') {|f| f << image_data }
  puts "WROTE: #{image_file}"
  nil
end

# display flash errors and propagate exit status
post '/error' do
  file = FILES[params[:id].to_i]
  error = params[:error]
  ERRORS << error

  warn "ERROR in #{file}: #{error}"
  nil
end

# close the browser and terminate this program
get '/end' do
  begin
    Process.kill :SIGTERM, browser_pid
  rescue => e
    warn "Could not kill the browser process (pid=#{browser_pid}) with SIGTERM because #{e.inspect}; you must kill it by hand instead."
  end

  status = [255, ERRORS.length].min
  puts "EXIT: #{status}"
  exit! status
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
    - FILES.each_with_index do |file, id|
      .chart{:id => id, :url => "/chart/#{id}", :pending => true}
        = "Chart #{id}: #{file}"

        .flash_placeholder{:id => "flash_placeholder_#{id}"}

    :javascript
      function process_chart(chart) {
        // visually indicate that this chart is being processed
        chart.css({'font-weight': 'bold', 'color': 'red'});

        //
        // instantiate the flash applet
        //
        var placeholder_id = $('.flash_placeholder', chart).attr('id');

        swfobject.embedSWF(
          'open-flash-chart.swf', placeholder_id, #{WIDTH}, #{HEIGHT},
          '9.0.0', false, {'data-file': chart.attr('url')}, false, false,
          function(event) {
            var flash = event.ref;

            //
            // move flash applet off-screen to improve browser performance
            //
            $(flash).css({
              position: 'absolute',
              left: '-#{WIDTH.to_i + 10}px',
              top: '-#{HEIGHT.to_i + 10}px'
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
                  $.post('/error', {'error': error, 'id': chart.attr('id')});
                }

                if (prev_sample == curr_sample) {
                  num_stable_samples++;

                  if (num_stable_samples >= MIN_STABLE_SAMPLES) {
                    //
                    // chart is stable now, we can render & upload
                    //
                    $.post(
                      chart.attr('url'), {'image': curr_sample},
                      function() {
                        chart.remove();
                        process_next_chart(); // continue this thread
                      }
                    );

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
          process_chart(next_chart.removeAttr('pending'));
        }
        else if ($('.chart').length == 0) {
          //
          // all charts have been processed now
          //
          $('body').text('You may close this window now.');
          $.get('/end'); // notify server about completion
        }
      }

      $(function() {
        //
        // bootstrap the processing threads
        //
        for (var i = 0; i < #{THREADS}; i++) {
          setTimeout(process_next_chart, i * 3); // stagger the threads in time
        }
      });

