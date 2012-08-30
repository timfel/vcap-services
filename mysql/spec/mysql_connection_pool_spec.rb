# Copyright (c) 2009-2011 VMware, Inc.
$:.unshift(File.dirname(__FILE__))
require 'spec_helper'
require 'logger'
require 'yajl'
require 'mysql_service/util'
require 'timeout'

module VCAP
  module Services
    module Mysql
      module Util
        class ConnectionPool
          attr_reader :connections
        end
      end
    end
  end
end

describe 'Mysql Connection Pool Test' do

  before :all do
    @opts = getNodeTestConfig
    @logger = @opts[:logger]
    @opts.freeze
    @mysql_config = @opts[:mysql]
    host, user, password, port, socket =  %w{host user pass port socket}.map { |opt| @mysql_config[opt] }
    @pool = connection_pool_klass.new(:host => host, :username => user, :password => password, :database => "mysql", :port => port.to_i, :socket => socket, :logger => @logger, :pool => 20)

  end

  it "should provide mysql connections" do
    @pool.with_connection do |conn|
      expect {conn.query("select 1")}.should_not raise_error
    end
  end

  it "should not provide the same connection to different threads" do
    THREADS = 20
    ITERATES = 10
    threads = []
    Thread.abort_on_exception = true
    THREADS.times do
      thread  = Thread.new do
        ITERATES.times do
          begin
            @pool.with_connection do |conn|
              sleep_time = rand(5).to_f/10
              # if multiple threads acquire the same connection, following query would fail.
              conn.query("select sleep(#{sleep_time})")
            end
          end
        end
      end
      threads << thread
    end
    threads.each {|t| t.join}
  end

  it "should verify a connection before checkout" do
    host, user, password, port, socket =  %w{host user pass port socket}.map { |opt| @mysql_config[opt] }
    pool = connection_pool_klass.new(:host => host, :username => user, :password => password, :database => "mysql", :port => port.to_i, :socket => socket, :pool => 1, :logger => @logger)

    pool.with_connection do |conn|
      conn.close
    end

    pool.with_connection do |conn|
      expect{conn.query("select 1")}.should_not raise_error
    end
  end

  it "should keep the pooled connection alive" do
    @pool.close
    # bypass checkout since it verifiy and reconnect the connection
    @pool.connections.each{|conn| conn.active?.should == nil }

    @pool.keep_alive
    @pool.connections.each{|conn| conn.active?.should == true}

    @pool.with_connection do |conn|
      conn.ping.should == true
    end
  end

  it "should report the mysql connection status" do
    mock_client = mock("client")
    mock_client.should_receive(:ping).and_return(true)
    mock_client.should_receive(:close).and_return(true)
    Mysql2::Client.should_receive(:new).and_return(mock_client)

    pool = connection_pool_klass.new(:logger => @logger, :pool => 1)
    pool.connected?.should == true

    error = Mysql2::Error.new("Can't connect to mysql")
    # Simulate mysql server is gone.
    mock_client.should_receive(:ping).and_return(nil)
    Mysql2::Client.should_receive(:new).and_raise(error)
    pool.connected?.should == nil
  end

  it "should not leak connection when can't connect to mysql" do
    mock_client = mock("client")
    mock_client.should_receive(:close).and_return(true)
    Mysql2::Client.should_receive(:new).and_return(mock_client)

    pool = connection_pool_klass.new(:logger => @logger, :pool => 1)

    # Simulate mysql server is gone.
    mock_client.should_receive(:ping).and_return(nil)
    error = Mysql2::Error.new("Can't connect to mysql")
    Mysql2::Client.should_receive(:new).and_raise(error)

    expect{ pool.with_connection{|conn| conn.query("select 1")} }.should raise_error(Mysql2::Error, /Can't connect to mysql/)

    # Ensure that we can still checkout from the pool
    mock_client.should_receive(:ping).and_return(true)
    mock_client.should_receive(:query).with("select 1").and_return(true)
    expect{ pool.with_connection{|conn| conn.query("select 1")} }.should_not raise_error
  end

  it "should raise error when pool is still empty after timeout second" do
    host, user, password, port, socket =  %w{host user pass port socket}.map { |opt| @mysql_config[opt] }
    # create a tiny pool with very short timeout
    pool = connection_pool_klass.new(:host => host, :username => user, :password => password, :database => "mysql",
                                     :port => port.to_i, :socket => socket, :pool => 1, :logger => @logger, :wait_timeout => 2)
    threads = []
    threads << Thread.new do
      # acquire connection for quite a long time.
      pool.with_connection do |conn|
        sleep 5
        conn.query("select 1")
      end
    end

    error = nil
    threads << Thread.new do
      begin
        sleep 1
        pool.with_connection do |conn|
          conn.query("select 1")
        end
      rescue => e
        error = e
      end
    end
    threads.each{|t| t.join}
    error.should_not == nil
    error.to_s.should match(/could not obtain a database connection/)
  end

end
