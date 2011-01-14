#!/usr/bin/env ruby

# A sinatra application to provide web GUI to make puppet code releases

require 'svn/client'
# source /usr/lib/ruby/1.8/svn/client.rb
require 'yaml'

require 'rubygems'
require 'sinatra'
require 'nokogiri'


SVN_URL = "https://puppetrepo.sea5.speakeasy.priv/puppet"
WC_PATH = Dir.pwd + "/svn_conf"
# secrets are stored in a yaml file
creds_file = "/root/svn_creds"
# CREDS = YAML.load_file creds_file

# a class to store revision metadata (we get xml) for easier manipulation later.
class RevData
  attr_reader :rev, :author, :date, :msg 
  
  def initialize(rev_num, author, date, msg)
    @rev = rev_num
    @author = author
    @date = Time.parse(date).strftime("%k:%M on %B %e, %Y")
    @msg = msg
  end
end

helpers do

  # Returns an array of routes, ignoring exceptions
  def my_routes
    my_routes = []
    exceptions = [["signin"], ["login"], [], ["error"]]
    self.class.routes['GET'].each do |r|
      next if r.first.to_s == "(?-mix:^\/$)"
      # route is an array of objects
      route = r.first.to_s.gsub(/\(\?-mix:\^\\\/|\\|\$|\)/,'').split('/')
      my_routes << route unless exceptions.include?(route) or route.empty?
    end
    return my_routes
  end

  # returns production branch by default or one that is specified
  def get_branch(pop="sea5")
    # obtained everytime to insure it picks up any changes. It is parsing a local copy.
    return get_config[pop]
  end
  
  # returns last changed revition for prod tag
  def last_rev
    last_tag_rev = (`svn info "#{SVN_URL}/#{get_branch}" | awk '/Last Changed Rev:/ {print $NF}'`).chomp
    return last_tag_rev
  end
  
  # Returns last n(10 default) tags by date
  def last_tags(num =10)
    # svn list -r {2010-06-01} isn't doing what I expect
    # a tail could be used, but we make an array, and we could use it later
    tags = `svn list "#{SVN_URL}"/tags | egrep "^[0-9]01"`
    tags_sorted = tags.split.map {|n| n.gsub(/\//,'').to_i}.sort.reverse
    # TODO: return a hash with tag=>date 
    return tags_sorted[0,num]
  end
  
  # determine what the next tag should be, we can take a custom index
  def gen_tag_name( index = "00" )
    date_tag = Time.now.strftime("%Y%m%d")
    last_tag = last_tags(1).to_s
    return date_tag + index if !last_tag.match(/^#{date_tag}/)
    # we need to increment the last tag.
    return (last_tag.to_i + 1).to_s
  end
  
  # poorly named method. To make a ctx object with whitch we will operate
  def connect_repo
    @context = Svn::Client::Context.new
    @context.add_ssl_server_trust_file_provider
  end
  
	# checks out conf branch, returns last revision
  def checkout_repo
    connect_repo unless @context
    # FIXME: another thread..?
    @context.checkout("#{SVN_URL}/conf",WC_PATH) unless File.exists?(WC_PATH + "/branch.conf") 
    return @last_rev = (@context.update(WC_PATH)).to_s
  end
  
	# 
  def auth_repo(msg)
    connect_repo unless @context
    @context.add_simple_prompt_provider(0) do |cred, realm, username|
			begin
				CREDS = YAML.load_file creds_file
			rescue 
				raise "ERROR reading parameters from #{creds_file}"
			end
			cred.username = CREDS.username
      cred.password = CREDS.passwd
    end    
    @context.set_log_msg_func do |items|
      [true, msg]
    end
  end

  # parsing local checked out copy of branch.conf, which later will be used to commiting changes
  def get_config
    checkout_repo unless @last_rev    
    branch_conf = Hash.new
    File.readlines(WC_PATH + "/branch.conf").each do |line|
      next unless line.match(/^\w/)
      a = line.split
      branch_conf[a.first] = a.last
    end
    return branch_conf
    # another aproach is to use inject:
    # inject({}) {|hash, i| hash[i[0]] = i[1]; hash}
  end

  # Getting comit log since last release
  def get_commit_log
    # log_str = `svn log -r"#{last_tag_rev}":HEAD "#{SVN_URL}" | egrep "^[a-zA-Z]"`
    # later we might want to get a path. or make it as additional info with merg history and stuff.
    svn_log_xml = Nokogiri::XML(`svn log --xml -r"#{last_rev}":HEAD "#{SVN_URL}"`)
    
    # array to store RevData class objects 
    rev_objs = Array.new
    (svn_log_xml/"//logentry").each do |rev|
      rev_num = rev.values.to_s
      author = (rev/"author").text
      date = (rev/"date").text
      msg = (rev/"msg").text 
      
      rev_objs << RevData.new(rev_num, author, date, msg)
    end
    
    return rev_objs
  end
  
  def make_new_tag
    tag = gen_tag_name
    msg = params["commit_msg"]
    auth_repo(msg)
    return @context.copy("#{SVN_URL}/trunk", "#{SVN_URL}/tags/#{tag}")
  end
  
  # Returns an array of active branches in puppet repo
  def available_branches
    # will start with 4 last tags:
    tags = last_tags(4).map {|t| "tags/" + t.to_s}
    br = (`svn list #{SVN_URL}/branches | egrep -v "lab"`).split
    br.map! {|b| "branches/" + b.gsub(/\//,'')}
    lab = (`svn list #{SVN_URL}/branches/lab | egrep -v "retire"`).split
    lab.map! {|l| "branches/lab/" + l.gsub(/\//,'')}
    return (tags + lab + br).insert(0,"trunk")
  end
  
  # the function will generate a new branch.conf file overwriting existing one
  def new_release
    write_branch_config
    # committing the changes
    msg = "New release by release app on #{Time.now.strftime("%k:%M on %B %e, %Y")}"
    auth_repo(msg)
    # TODO: check if there is a change before committing.
    @context.commit(File.join(WC_PATH, "branch.conf"))
  end
    
  def write_branch_config
    # The existing file will be overwritten.
    conf_file = File.open(WC_PATH + '/branch.conf', 'w')
    conf_file.puts <<-HEAD
# Branch configuration generated by "Release application" 
# at #{Time.now.strftime("%k:%M on %B %e, %Y")}
#
    HEAD
    params.keys.sort.each do |pop|
      # case pop
      # when /^qa/
        # conf_file.puts "#{pop}\t\t#{params[pop]}"
      # else
        conf_file.puts "#{pop}\t#{params[pop]}"
      #end
    end
    conf_file.close
  end

end # end of helpers

load "routes.rb"
