# Copyright (c) 2012 VMware, Inc.

module VCAP
  module Services
    module Gemstone
      class GemstoneError < VCAP::Services::Base::Error::ServiceError
        # claim 700 range? (see vcap/services/base/lib/base/service_error.rb)
        GSS_LOCAL_DB_ERROR = [31701, HTTP_INTERNAL, 'Problem with CF database']
      end
    end
  end
end

