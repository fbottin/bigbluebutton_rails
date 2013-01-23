require 'forgery'

namespace :db do

  desc "Populate the DB with random test data."
  task :populate => :environment do

    puts "- Destroying all old data"
    BigbluebuttonServer.destroy_all
    BigbluebuttonRoom.destroy_all
    BigbluebuttonRecording.destroy_all
    BigbluebuttonMetadata.destroy_all
    BigbluebuttonPlaybackFormat.destroy_all

    # Servers
    2.times do |n1|
      params = {
        :name => "Server #{n1}",
        :url => "http://bigbluebutton#{n1}.test.com/bigbluebutton/api",
        :salt => Forgery(:basic).password(:at_least => 30, :at_most => 40),
        :version => '0.8',
        :param => "server-#{n1}"
      }
      puts "- Creating server #{params[:name]}"
      server = BigbluebuttonServer.create!(params)

      # Rooms
      2.times do |n2|
        params = {
          :meetingid => "meeting-#{n1}-#{n2}-" + SecureRandom.hex(4),
          :server => server,
          :name => "Name-#{n1}-#{n2}",
          :attendee_password => Forgery(:basic).password(:at_least => 10, :at_most => 16),
          :moderator_password => Forgery(:basic).password(:at_least => 10, :at_most => 16),
          :welcome_msg => Forgery(:lorem_ipsum).sentences(2),
          :private => false,
          :randomize_meetingid => false,
          :param => "meeting-#{n1}-#{n2}",
          :external => false,
          :record => false,
          :duration => 0
        }
        puts "  - Creating room #{params[:name]}"
        room = BigbluebuttonRoom.create!(params)

        # Room metadata
        3.times do
          params = {
            :name => Forgery(:name).first_name.downcase,
            :content => Forgery(:name).full_name,
            :owner => room
          }
          puts "    - Creating room metadata #{params[:name]}"
          metadata = BigbluebuttonMetadata.create(params)
          metadata.save!
        end

        # Recordings
        2.times do |n3|
          params = {
            :recordid => "rec-#{n1}-#{n2}-#{n3}-" + SecureRandom.hex(26),
            :meetingid => room.meetingid,
            :name => "Rec-#{n1}-#{n2}-#{n3}",
            :published => true,
            :start_time => Time.now - rand(5).hours,
            :end_time => Time.now + rand(5).hours
          }
          puts "    - Creating recording #{params[:name]}"
          recording = BigbluebuttonRecording.create(params)
          recording.server = server
          recording.room = room
          recording.save!

          # Recording metadata
          3.times do
            params = {
              :name => Forgery(:name).first_name.downcase,
              :content => Forgery(:name).full_name,
              :owner => recording
            }
            puts "      - Creating recording metadata #{params[:name]}"
            metadata = BigbluebuttonMetadata.create(params)
            metadata.save!
          end

          # Recording playback formats
          2.times do |n4|
            params = {
              :format_type => "#{n4}-#{Forgery(:name).first_name.downcase}",
              :url => "http://" + Forgery(:internet).domain_name + "/playback",
              :length => Forgery(:basic).number
            }
            puts "      - Creating playback format #{params[:format_type]}"
            format = BigbluebuttonPlaybackFormat.create(params)
            format.recording = recording
            format.save!
          end

        end
      end
    end
  end
end
