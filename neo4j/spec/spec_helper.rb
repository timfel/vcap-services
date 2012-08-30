# Copyright (c) 2009-2011 VMware, Inc.
$:.unshift File.join(File.dirname(__FILE__), '..')
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

$LOAD_PATH.unshift(File.expand_path("../../../", __FILE__))
$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

require "rubygems"
require "rspec"
require 'bundler/setup'
require 'vcap_services_base'
require "socket"
require "timeout"

HTTP_PORT = 9865

def is_port_open?(host, port)
  begin
    Timeout::timeout(1) do
      begin
        s = TCPSocket.new(host, port)
        s.close
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        $stderr.puts "Trying to connect to #{host}:#{port} #{e.inspect}"
        return false
      end
    end
  rescue Timeout::Error => e
        $stderr.puts "Trying to connect to #{host}:#{port} #{e.inspect}"
  end
  false
end

def symbolize_keys(hash)
  if hash.is_a? Hash
    new_hash = {}
    hash.each do |k, v|
      new_hash[k.to_sym] = symbolize_keys(v)
    end
    new_hash
  else
    hash
  end
end

def parse_property(hash, key, type, options = {})
  obj = hash[key]
  if obj.nil?
    raise "Missing required option: #{key}" unless options[:optional]
    nil
  elsif type == Range
    raise "Invalid Range object: #{obj}" unless obj.kind_of?(Hash)
    first, last = obj["first"], obj["last"]
    raise "Invalid Range object: #{obj}" unless first.kind_of?(Integer) and last.kind_of?(Integer)
    Range.new(first, last)
  else
    raise "Invalid #{type} object: #{obj}" unless obj.kind_of?(type)
    obj
  end
end

def get_logger_level(logging)
  unless logging.has_key? "level"
    raise "Missing required option: level"
    Logger::FATAL
  else
    value = logging["level"].downcase
    logger_level = case value
      when "debug" then Logger::DEBUG
      when "info" then Logger::INFO
      when "warn" then Logger::WARN
      when "error" then Logger::ERROR
      when "fatal" then Logger::FATAL
      else
        raise "Invalid logger level: please choose one from debug, info, warn, error, fatal"
        Logger::FATAL
    end
  end
end

def config_base_dir
  ENV["CLOUD_FOUNDRY_CONFIG_PATH"] || File.join(File.dirname(__FILE__), '..', 'config')
end

def get_node_config()
  config_file = File.join(config_base_dir, "neo4j_node.yml")
  config = YAML.load_file(config_file)
  neo4j_server_conf_template = File.join(File.dirname(__FILE__), "../resources/neo4j-server.properties.erb")
  neo4j_conf_template = File.join(File.dirname(__FILE__), "../resources/neo4j.properties.erb")
  log4j_conf_template = File.join(File.dirname(__FILE__), "../resources/log4j.properties.erb")
  options = {
    :capacity => parse_property(config, "capacity", Integer),
    :plan => parse_property(config, "plan", String),
    :logger => Logger.new(parse_property(config, "log_file", String, :optional => true) || STDOUT, "daily"),
    :neo4j_path => parse_property(config, "neo4j_path", String),
    :node_id => parse_property(config, "node_id", String),
    :mbus => parse_property(config, "mbus", String),
    :config_template => neo4j_server_conf_template,
    :neo4j_template => neo4j_conf_template,
    :log4j_template => log4j_conf_template,
    :port_range => parse_property(config, "port_range", Range),
    :max_memory => parse_property(config, "max_memory", Integer),
    :base_dir => '/tmp/neo4j/instances',
    :local_db => 'sqlite3:/tmp/neo4j/neo4j_node.db'
  }
  options[:logger].level = get_logger_level(parse_property(config, "logging", Hash))
  puts options[:logger].level
  options[:port_range] = (options[:port_range].last+1)..(options[:port_range].last+10)
  options
end

def neo4j_url(user=@bind_resp['username'],password=@bind_resp['password'],port=@resp['port'])
  auth = ""
  auth = "#{user}:#{password}@" if user
  "http://#{auth}#{@bind_resp['host']}:#{port}/db/data/"
end

def neo4j_connect(user=@bind_resp['username'],password=@bind_resp['password'],port=@resp['port'])
  RestClient.get neo4j_url(user,password,port)
end

def get_provisioner_config()
  config_file = File.join(File.dirname(__FILE__), "../config/neo4j_gateway.yml")
  config = YAML.load_file(config_file)
  config = symbolize_keys(config)
  options = {
    :logger => Logger.new(parse_property(config, "log_file", String, :optional => true) || STDOUT, "daily"),
    # Following options are for Provisioner
    :version => config[:service][:version],
    :local_ip => 'localhost',
    :mbus => config[:mbus],
    # Following options are for AsynchronousServiceGateway
    :service => config[:service],
    :token => config[:token],
    :cloud_controller => config[:cloud_controller],
    # Following options are for Thin
    :host => 'localhost',
    :port => HTTP_PORT
  }
  options[:logger].level = Logger::FATAL
  options
end

def start_server(opts)
  sp = Provisioner.new(@opts)
  opts = opts.merge({:provisioner => sp})
  sg = VCAP::Services::AsynchronousServiceGateway.new(opts)
  Thin::Server.start(opts[:host], opts[:port], sg)
  sleep 5
rescue Exception => e
  $stderr.puts e
end
