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

require 'spec_helper'
require 'timecop'

describe InstAccess::Token do
  let(:signing_keypair) { OpenSSL::PKey::RSA.new(2048) }
  let(:encryption_keypair) { OpenSSL::PKey::RSA.new(2048) }
  let(:signing_priv_key) { signing_keypair.to_s }
  let(:signing_pub_key) { signing_keypair.public_key.to_s }
  let(:encryption_priv_key) { encryption_keypair.to_s }
  let(:encryption_pub_key) { encryption_keypair.public_key.to_s }
  let(:issuers) {}
  let(:issuer) {}

  let(:a_token) { described_class.for_user(user_uuid: 'user-uuid', account_uuid: 'acct-uuid', issuer: issuer) }
  let(:unencrypted_token) do
    InstAccess.with_config(signing_key: signing_priv_key, issuers: issuers) do
      a_token.to_unencrypted_token_string
    end
  end

  describe '.token?' do
    it 'returns false for non-JWTs' do
      expect(described_class.token?('asdf1234stuff')).to eq(false)
    end

    it 'returns false for JWTs from an issuer not in the list' do
      jwt = JSON::JWT.new(iss: 'bridge').to_s
      expect(described_class.token?(jwt)).to eq(false)
    end

    it 'returns true for an InstAccess token' do
      expect(described_class.token?(unencrypted_token)).to eq(true)
    end

    context 'with issuers configured' do
      let(:issuers) { ['token_from_other_service'] }
      let(:issuer) { 'token_from_other_service' }

      it 'returns true for JWTs from an issuer in the list' do
        jwt = JSON::JWT.decode(unencrypted_token, :skip_verification)
        expect(jwt[:iss]).to eq('token_from_other_service')
        InstAccess.with_config(signing_key: signing_priv_key, issuers: issuers) do
          expect(described_class.token?(unencrypted_token)).to eq(true)
        end
      end

      it 'returns true for JWTs from the default issuer when issuers are configured' do
        token = described_class.for_user(user_uuid: 'user-uuid', account_uuid: 'acct-uuid')
        jws = InstAccess.with_config(signing_key: signing_priv_key) do
          token.to_unencrypted_token_string
        end
        jwt = JSON::JWT.decode(jws, :skip_verification)
        expect(jwt[:iss]).to eq(InstAccess::Token::ISSUER)
        InstAccess.with_config(signing_key: signing_priv_key, issuers: issuers) do
          expect(described_class.token?(jws)).to eq(true)
        end
      end
    end

    it 'returns true for an expired InstAccess token' do
      token = unencrypted_token # instantiate it to set the expiration
      Timecop.travel(3601) do
        expect(described_class.token?(token)).to eq(true)
      end
    end
  end

  describe '.for_user' do
    it 'blows up without a user uuid' do
      expect do
        described_class.for_user(user_uuid: '', account_uuid: 'acct-uuid')
      end.to raise_error(ArgumentError)
    end

    it 'blows up without an account uuid' do
      expect do
        described_class.for_user(user_uuid: 'user-uuid', account_uuid: '')
      end.to raise_error(ArgumentError)
    end

    it 'creates an instance for the given uuids' do
      id = described_class.for_user(user_uuid: 'user-uuid', account_uuid: 'acct-uuid')
      expect(id.user_uuid).to eq('user-uuid')
      expect(id.account_uuid).to eq('acct-uuid')
      expect(id.masquerading_user_uuid).to be_nil
    end

    it 'accepts other details' do
      id = described_class.for_user(
        user_uuid: 'user-uuid',
        account_uuid: 'acct-uuid',
        canvas_domain: 'z.instructure.com',
        real_user_uuid: 'masq-id',
        real_user_shard_id: 5,
        region: 'us-west-2',
        client_id: 'client-id',
        instructure_service: true,
        canvas_shard_id: 3
      )
      expect(id.canvas_domain).to eq('z.instructure.com')
      expect(id.masquerading_user_uuid).to eq('masq-id')
      expect(id.masquerading_user_shard_id).to eq(5)
      expect(id.region).to eq('us-west-2')
      expect(id.client_id).to eq('client-id')
      expect(id.instructure_service?).to eq true
      expect(id.canvas_shard_id).to eq(3)
    end

    it 'generates a unique jti' do
      uuid = SecureRandom.uuid

      allow(SecureRandom).to receive(:uuid).and_return uuid

      id = described_class.for_user(
        user_uuid: 'user-uuid',
        account_uuid: 'acct-uuid',
        canvas_domain: 'z.instructure.com',
        real_user_uuid: 'masq-id',
        real_user_shard_id: 5,
        region: 'us-west-2',
        client_id: 'client-id',
        instructure_service: true,
        canvas_shard_id: 3
      )

      expect(id.jti).to eq uuid
    end

    it 'includes global id debug info if given' do
      id = described_class.for_user(
        user_uuid: 'user-uuid',
        account_uuid: 'acct-uuid',
        user_global_id: 10_000_000_000_123,
        real_user_global_id: 10_000_000_000_456
      )

      expect(id.jwt_payload[:debug_user_global_id]).to eq('10000000000123')
      expect(id.jwt_payload[:debug_masq_global_id]).to eq('10000000000456')
    end

    it 'omits global id debug info if not given' do
      id = described_class.for_user(user_uuid: 'user-uuid', account_uuid: 'acct-uuid')
      expect(id.jwt_payload.keys).not_to include(:debug_user_global_id)
      expect(id.jwt_payload.keys).not_to include(:debug_masq_global_id)
    end
  end

  context 'without being configured' do
    it '#to_token_string blows up' do
      id = described_class.for_user(user_uuid: 'user-uuid', account_uuid: 'acct-uuid')
      expect do
        id.to_token_string
      end.to raise_error(InstAccess::ConfigError)
    end

    it '.from_token_string blows up' do
      expect do
        described_class.from_token_string(unencrypted_token)
      end.to raise_error(InstAccess::ConfigError)
    end
  end

  context 'when configured only for signature verification' do
    around do |example|
      InstAccess.with_config(signing_key: signing_pub_key) do
        example.run
      end
    end

    it '#to_token_string blows up' do
      id = described_class.for_user(user_uuid: 'user-uuid', account_uuid: 'acct-uuid')
      expect do
        id.to_token_string
      end.to raise_error(InstAccess::ConfigError)
    end

    it '.from_token_string decodes the given token' do
      id = described_class.from_token_string(unencrypted_token)
      expect(id.user_uuid).to eq('user-uuid')
    end

    it '.from_token_string blows up if the token is expired' do
      token = unencrypted_token # instantiate it to set the expiration
      Timecop.travel(3601) do
        expect do
          described_class.from_token_string(token)
        end.to raise_error(InstAccess::TokenExpired)
      end
    end

    it '.from_token_string blows up if the token has a bad signature' do
      # reconfigure with the wrong signing key so the signature doesn't match
      InstAccess.with_config(signing_key: encryption_pub_key) do
        expect do
          described_class.from_token_string(unencrypted_token)
        end.to raise_error(InstAccess::InvalidToken)
      end
    end

    it '.from_token_string decodes a token signed by a key in a configured JSON::JWK::Set' do
      jwk = JSON::JWK.new(kid: 'token_from_other_service/file_authorization', k: 'hmac_secret', kty: 'oct')
      payload = { sub: 'user-uuid', account_uuid: 'acct-uuid', issuer: 'other_service', exp: 5.minutes.from_now }
      jws = JSON::JWT.new(payload).sign(jwk).to_s
      jwk_set = JSON::JWK::Set.new([jwk])
      InstAccess.with_config(signing_key: signing_priv_key, issuers: ['other_service'], service_jwks: jwk_set) do
        token = described_class.from_token_string(jws)
        expect(token.user_uuid).to eq('user-uuid')
      end
    end
  end

  context 'when configured for token generation' do
    around do |example|
      InstAccess.with_config(
        signing_key: signing_priv_key, encryption_key: encryption_pub_key
      ) do
        example.run
      end
    end

    it '#to_token_string signs and encrypts the payload, returning a JWE' do
      id_token = a_token.to_token_string
      # JWEs have 5 base64-encoded sections, each separated by a dot
      expect(id_token).to match(/[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+\.[\w-]+/)
      # normally another service would need to decrypt this, but we'll do it
      # here ourselves to ensure it's been encrypted properly
      jws = JSON::JWT.decode(id_token, encryption_keypair)
      jwt = JSON::JWT.decode(jws.plain_text, signing_keypair)
      expect(jwt[:sub]).to eq('user-uuid')
    end

    it '.from_token_string still decodes the given token' do
      id = described_class.from_token_string(unencrypted_token)
      expect(id.user_uuid).to eq('user-uuid')
    end
  end
end
