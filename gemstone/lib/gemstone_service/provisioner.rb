# Copyright (c) 2012 VMware, Inc.
# This minimilist approach is modeled on Postgresql
require 'gemstone_service/common'

class VCAP::Services::Gemstone::Provisioner < VCAP::Services::Base::Provisioner

  include VCAP::Services::Gemstone::Common

end
