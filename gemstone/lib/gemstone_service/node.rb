# Copyright (c) 2012 VMware, Inc.
require "erb"
require "fileutils"
require "logger"
require "pp"
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
require "gemstone_service/error"

class VCAP::Services::Gemstone::Node
  include VCAP::Services::Gemstone::Common
  include VCAP::Services::Gemstone

  # ProvisionedService is the data stored by CloudFoundry for a provisioned
  # instance of the Gemstone service. This info is made available throughout
  # the system, e.g., at the time an app is staged / run.
  class ProvisionedService
    include DataMapper::Resource
    property :name, String,  :key => true
    # property plan is deprecated. The instances in one node have same plan.
    property :plan, Integer, :required => true
    property :user, String,  :required => true
    property :pass, String,  :required => true
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
  end

  def pre_send_announcement
    super
    start_local_db
    start_gemstone
  end

  def start_local_db
    DataMapper.setup(:default, @local_db)
    DataMapper::auto_upgrade!
  end

  def start_gemstone
    `#{@GEMSTONE}/bin/startstone`
  end

  def shutdown
    `#{@GEMSTONE}/bin/stopstone`
    super
  end
  
  def announcement
    a = {
      :some_random_data => 42,
    }
  end

  def provision(plan, credential=nil)
    provisioned_service = ProvisionedService.new
    provisioned_service.plan = plan
    if credential
      provisioned_service.name = credential[:name]
      provisioned_service.user = credential[:user]
      provisioned_service.pass = credential[:password]
    else
      provisioned_service.name = 'GS-' + UUIDTools::UUID.random_create.to_s.gsub(/-/, '')
      provisioned_service.user = 'CF-' + generate_credential
      provisioned_service.pass = generate_credential
    end

    `#{@GEMSTONE}/bin/topaz_dc <<EOF
#{@provision_template.result(binding)}
EOF`

    if not provisioned_service.save
      @logger.error("Could not save entry: #{provisoned_service.errors.inspect}")
      raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR)
    end

    response = {
      "name" => provisioned_service.name,
      "user" => provisioned_service.user,
      "pass" => provisioned_service.pass,
      "host" => @local_ip,
      "port" => 0,
    }
  end

  def unprovision(name, credentials)
    return if name.nil?
    provisioned_service = ProvisionedService.get(name)
    raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR) if provisioned_service.nil?

    `#{@GEMSTONE}/bin/topaz_dc <<EOF
#{@unprovision_template.result(binding)}
EOF`

    if not provisioned_service.destroy
      @logger.error("Could not delete service: #{provisioned_service.errors.inspect}")
      raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR)
    end
  end

  def bind(name, bind_opts, credential=nil)
    provisioned_service = ProvisionedService.get(name)
    raise GemstoneError.new(GemstoneError::GSS_LOCAL_DB_ERROR) if provisioned_service.nil?
    response = {
      "user" => provisioned_service.user,
      "pass" => provisioned_service.pass,
      "host" => @local_ip,
      "port" => 0,
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
