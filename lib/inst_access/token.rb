# frozen_string_literal: true

#
# Copyright (C) 2021 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

module InstAccess
  class Token
    ISSUER = 'instructure:inst_access'
    ENCRYPTION_ALGO = :'RSA-OAEP'
    ENCRYPTION_METHOD = :'A128CBC-HS256'

    attr_reader :jwt_payload

    def initialize(jwt_payload)
      @jwt_payload = jwt_payload.symbolize_keys
    end

    def user_uuid
      jwt_payload[:sub]
    end

    def account_uuid
      jwt_payload[:acct]
    end

    def canvas_domain
      jwt_payload[:canvas_domain]
    end

    def masquerading_user_uuid
      jwt_payload[:masq_sub]
    end

    def masquerading_user_shard_id
      jwt_payload[:masq_shard]
    end

    def region
      jwt_payload[:region]
    end

    def client_id
      jwt_payload[:client_id]
    end

    def instructure_service?
      jwt_payload[:instructure_service] == true
    end

    def canvas_shard_id
      jwt_payload[:canvas_shard_id]
    end

    def jti
      jwt_payload[:jti]
    end

    def to_token_string
      jwe = to_jws.encrypt(InstAccess.config.encryption_key, ENCRYPTION_ALGO, ENCRYPTION_METHOD)
      jwe.to_s
    end

    # only for testing purposes, or to do local dev w/o running a decrypting
    # service.  unencrypted tokens should not be released into the wild!
    def to_unencrypted_token_string
      to_jws.to_s
    end

    private

    def to_jws
      key = InstAccess.config.signing_key
      raise ConfigError, 'Private signing key needed to produce tokens' unless key.private?

      jwt = JSON::JWT.new(jwt_payload)
      jwt.sign(key)
    end

    class << self
      private :new

      # rubocop:disable Metrics/ParameterLists
      def for_user(
        user_uuid: nil,
        account_uuid: nil,
        canvas_domain: nil,
        real_user_uuid: nil,
        real_user_shard_id: nil,
        user_global_id: nil,
        real_user_global_id: nil,
        region: nil,
        client_id: nil,
        instructure_service: nil,
        canvas_shard_id: nil
      )
        raise ArgumentError, 'Must provide user uuid and account uuid' if user_uuid.blank? || account_uuid.blank?

        now = Time.now.to_i

        payload = {
          iss: ISSUER,
          jti: SecureRandom.uuid,
          iat: now,
          exp: now + 1.hour.to_i,
          sub: user_uuid,
          acct: account_uuid,
          canvas_domain: canvas_domain,
          masq_sub: real_user_uuid,
          masq_shard: real_user_shard_id,
          debug_user_global_id: user_global_id&.to_s,
          debug_masq_global_id: real_user_global_id&.to_s,
          region: region,
          client_id: client_id,
          instructure_service: instructure_service,
          canvas_shard_id: canvas_shard_id
        }.compact

        new(payload)
      end
      # rubocop:enable Metrics/ParameterLists

      # Takes an unencrypted (but signed) token string
      def from_token_string(jws)
        sig_key = InstAccess.config.signing_key
        jwt = begin
          JSON::JWT.decode(jws, sig_key)
        rescue StandardError => e
          raise InvalidToken, e
        end
        raise TokenExpired if jwt[:exp] < Time.now.to_i

        new(jwt.to_hash)
      end

      def token?(string)
        jwt = JSON::JWT.decode(string, :skip_verification)
        jwt[:iss] == ISSUER
      rescue StandardError
        false
      end
    end
  end
end
