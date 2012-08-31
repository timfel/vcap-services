# Copyright (c) 2012 VMware, Inc.
require 'gemstone_service/common'

class VCAP::Services::Gemstone::Provisioner < VCAP::Services::Base::Provisioner

  include VCAP::Services::Gemstone::Common

  def node_score(node)
    10 # > 0 for ~/cloudfoundry/vcap/services/base/lib/base/provisioner.rb
  end

end
