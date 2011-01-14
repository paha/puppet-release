#!/usr/bin/env ruby
#

require 'rubygems'
require 'daemons'

# sinatra app root:
www_path = '/var/www/puppet-release'

Daemons.run_proc('release.rb', {:dir_mode => :normal, :dir => www_path}) do
    Dir.chdir(www_path)
    exec "ruby release.rb"
end
