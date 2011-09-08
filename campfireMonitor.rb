#!/usr/bin/env ruby

# == Synopsis
#      Program to monitor a campfire chat room
#      Modified from code provided at: http://www.snailbyte.com/2007/09/13/campfire-activity-notifier-for-kde/
#
# == Usage
#      campfireMonitor [roomName] [roomName] ...
#
# == Author
#      Steven Pothoven and Snailbyte Ltd.

require 'rubygems'
require 'tinder'
require "cgi"

class App
  VERSION = '0.1.1'

  def initialize arguments, stdin
    # default settings
    campfireSubdomain = 'mySubdomain'
    campfireUsername = 'user@email.com'
    campfirePassword = 'password'
    roomNames = ['Room1', 'Room2']
    if arguments.length > 0
      roomNames = arguments
    end



    # define platform specific noficiation values such as icon path and
    # your favorite audio player and audio file here for audio notifications

    if RUBY_PLATFORM =~ /darwin/
      # for OSX setup Growl
      require 'growl'
      @ui = 'mac'
      @campfireIconPath = 'campfireMonitor.icns'
      @growl = Growl::Notifier.sharedInstance
      @growl.delegate = self
      @growl.register('CampfireMonitor', ['Foo'], nil, OSX::NSImage.alloc.initByReferencingFile(@campfireIconPath))
    elsif RUBY_PLATFORM =~ /linux/
      # for Linux default to Gnome and use MPlayer for audio
      @ui = 'gnome'
      @campfireIconPath = '~/Sites/campfireMonitor/campfire-logo.png'
      @soundCommand = 'mplayer /usr/share/sounds/pop.wav'
    elsif RUBY_PLATFORM =~ /mswin/
      @ui = 'windows'
    end


    @campfire = Tinder::Campfire.new campfireSubdomain
    if @campfire.login campfireUsername, campfirePassword
      alert nil, "CampfireMonitor", "Successfully logged in #{campfireUsername}"
      @rooms = roomNames.collect { |roomName| @campfire.find_room_by_name roomName }
      # remove any invalid rooms
      @rooms.delete(nil);
      @rooms.each do |room|
        notify room, "CampfireMonitor", "Entered room."
        notify room, "CampfireMonitor", "Topic is: #{room.topic}.".gsub("'","")
        notify room, "CampfireMonitor", "Current users are:  #{room.users}.".gsub("'","")
      end
    else
      alert nil, "CampfireMonitor", "Failed to log in #{campfireUsername}"
    end
  end

  # display notifcation message
  def notify room, user, msg
    if msg and msg.size > 0
      msg = CGI.unescapeHTML(msg);
      if @ui == 'kde'
        system "dcop knotify default notify eventname \'#{user}\' \'#{'<a href="'+@campfire.uri.to_s+'/room/'+room.id+'">'+room.name+'</a>: ' unless room.nil?} #{msg}\' '' '' 16 2"
      elsif @ui == 'gnome'
        system "notify-send -i #{@campfireIconPath} '#{user}' '#{'<a href="'+@campfire.uri.to_s+'/room/'+room.id+'">'+room.name+'</a>: ' unless room.nil?} #{msg}'"
      elsif @ui == 'mac'
        @growl.notify('Foo', "#{room.name+':' unless room.nil?}#{user}", msg, :icon => OSX::NSImage.imageNamed(@campfireIconPath) )
      else
        puts "#{room.name+':' unless room.nil?}#{user} - #{msg}"
      end
    end
  end

  # notify with sound
  def alert room, user, msg
    notify room, user, msg
    if @soundCommand and @soundCommand.length > 0
      system @soundCommand
    end
  end

  def run
    # first get any missed messages for today
    threads = []
    @rooms.each do |room|
      thread = Thread.new do
        begin
          room.transcript(Date.today).last(3).each do |m|
            if !m.nil? and m[:message] and m[:message].size > 1
              notify room, m[:person], m[:message].gsub("'","")
            end
          end
        rescue
          notify room, "CampfireMonitor", "Could not process transcript"
        end
      end
      threads << thread
    end
    threads.each { |thread| thread.join}

    # listen for more messages
    threads = []
    @rooms.each do |room|
      thread = Thread.new(room) do |room|
        begin
          notify room, "CampfireMonitor", "Waiting for messages..."
          room.listen do |m|
            if !m.nil? and m[:message].size > 1
              unless m[:person] == "Ad"
                alert room, m[:person], m[:message].gsub("'","")
              end
            end
          end
        rescue
          notify room, "CampfireMonitor", "Problem starting monitor: " + $!
        end
      end
      threads << thread
    end
    threads.each { |thread| thread.join}

  end
end

app = App.new(ARGV, STDIN)
app.run
