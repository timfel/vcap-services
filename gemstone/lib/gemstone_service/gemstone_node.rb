# Copyright (c) 2012 VMware, Inc.
require "erb"
require "fileutils"
require "logger"
require "datamapper"	# included in echo demo
require "pp"		# not in echo demo
require "uuidtools"

module VCAP
  module Services
    module Gemstone
      class Node < VCAP::Services::Base::Node
      end
    end
  end
end

require "gemstone_service/common"
require "gemstone_service/gemstone_error"

class VCAP::Services::Gemstone::Node
  include VCAP::Services::Gemstone::Common
  include VCAP::Services::Gemstone

  # ProvisionedService is the data stored by CloudFoundry for a provisioned
  # instance of the Gemstone service. This info is made available throughout
  # the system, e.g., at the time an app is staged / run.
  class ProvisionedService
    include DataMapper::Resource
    property :name, String,  :key => true
    property :user, String,  :required => true
    property :pass, String,  :required => true
    property :gems, String,  :required => true
  end

  # +options+ includes the info in ../../config/gemstone_node.yml
  def initialize(options)
    super(options) # handles @node_id, @logger, @local_ip, @node_nats

    template_path = File.expand_path('../../resources/provision.tpz.erb', File.dirname(__FILE__))
    @provision_template = ERB.new(File.read(template_path))
    template_path = File.expand_path('../../resources/unprovision.tpz.erb', File.dirname(__FILE__))
    @unprovision_template = ERB.new(File.read(template_path))
    @GEMSTONE = options[:base_dir]
    @local_db = options[:local_db]
    @supported_versions = ["3.0.1"]
  end

  def pre_send_announcement
    super
    start_local_db
  end

  def start_local_db
    DataMapper.setup(:default, @local_db)
    DataMapper::auto_upgrade!
  end

  def announcement
    a = {
      :available_capacity => 42,
    }
  end

  def provision(plan, credential=nil, version=nil)
    @logger.debug("JGF-1-provision(#{plan.inspect}, #{credential.inspect}, #{version.inspect})")
    provisioned_service = ProvisionedService.new
    if credential
      provisioned_service.name = credential[:name]
      provisioned_service.user = credential[:user]
      provisioned_service.pass = credential[:password]
    else
      provisioned_service.name = 'GS-' + UUIDTools::UUID.random_create.to_s.gsub(/-/, '')
      provisioned_service.user = 'CF-' + generate_credential
      provisioned_service.pass = generate_credential
    end
    provisioned_service.gems = "!tcp@" + @local_ip + "#server!gs64stone"
    @logger.debug("JGF-2-#{provisioned_service.inspect}")

    `#{@GEMSTONE}/bin/topaz -I #{@GEMSTONE}/bin/datacurator.tpz > topaz.out <<EOF
#{@provision_template.result(binding)}
EOF`
    @logger.debug("JGF-3")

    if not provisioned_service.save
      @logger.error("Could not save entry: #{provisioned_service.errors.inspect}")
      raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR)
    end

    response = {
      "name" => provisioned_service.name,
      "user" => provisioned_service.user,
      "pass" => provisioned_service.pass,
      "host" => @local_ip,
      "port" => 0,
    }
    @logger.debug("JGF-4-#{response.inspect}")
  end

  def unprovision(name, credentials)
    return if name.nil?
    provisioned_service = ProvisionedService.get(name)
    raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR) if provisioned_service.nil?

    `#{@GEMSTONE}/bin/topaz -I #{@GEMSTONE}/bin/datacurator.tpz <<EOF
#{@unprovision_template.result(binding)}
EOF`

    if not provisioned_service.destroy
      @logger.error("Could not delete service: #{provisioned_service.errors.inspect}")
      raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR)
    end
  end

  def bind(name, bind_opts, credential=nil)
    provisioned_service = nil
    if credential
	    provisioned_service = ProvisionedService.get(credential["name"])
	else
	    provisioned_service = ProvisionedService.get(name)
	end
    raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR) if provisioned_service.nil?
    response = {
      "user" => provisioned_service.user,
      "pass" => provisioned_service.pass,
      "host" => @local_ip,
      "port" => 0,
      "gems" => provisioned_service.gems,
    }
  end

  def unbind(credentials)
  end

  CREDENTIAL_CHARACTERS = 
    ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a
  def generate_credential(length=12)
    Array.new(length) { 
      CREDENTIAL_CHARACTERS[rand(CREDENTIAL_CHARACTERS.length)] }.join
  end

end
