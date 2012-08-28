# Copyright (c) 2009-2011 VMware, Inc.
$:.unshift(File.dirname(__FILE__))
require 'spec_helper'

require 'gemstone_service/gemstone_node'

module VCAP
  module Services
    module Gemstone
      class Node

      end
    end
  end
end

module VCAP
  module Services
    module Gemstone
      class GemstoneError
          attr_reader :error_code
      end
    end
  end
end

describe "Gemstone service node" do
  include VCAP::Services::Gemstone

  before :all do
    @opts = get_node_test_config
    @opts.freeze
    @logger = @opts[:logger]
    # Setup code must be wrapped in EM.run
    EM.run do
      @node = Node.new(@opts)
      EM.add_timer(1) { EM.stop }
    end
  end

  before :each do
    @default_plan = "free"
    @default_opts = "default"
    @gemstoneer = @node.provision(@default_plan)
    @gemstoneer.should_not == nil
  end

  it "should provison a gemstone service with correct credential" do
    EM.run do
      @gemstoneer.should be_instance_of Hash
#     @gemstoneer["port"].should be 5002
      EM.stop
    end
  end

  it "should create a crediential when binding" do
    EM.run do
      binding = @node.bind(@gemstoneer["name"], @default_opts)
#     binding["port"].should be 5002
      EM.stop
    end
  end

  it "should supply different credentials when binding evoked with the same input" do
    EM.run do
      binding1 = @node.bind(@gemstoneer["name"], @default_opts)
      binding2 = @node.bind(@gemstoneer["name"], @default_opts)
      binding1.should_not be binding2
      EM.stop
    end
  end

  it "shoulde delete crediential after unbinding" do
    EM.run do
      binding = @node.bind(@gemstoneer["name"], @default_opts)
      @node.unbind(binding)
      EM.stop
    end
  end

  after :each do
    name = @gemstoneer["name"]
    @node.unprovision(name)
  end
end
