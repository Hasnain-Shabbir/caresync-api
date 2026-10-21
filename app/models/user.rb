class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Allowlist

  devise :database_authenticatable, :validatable, :lockable, :recoverable, :jwt_authenticatable, jwt_revocation_strategy: self

  belongs_to :organization
  has_many :allowlisted_jwts, dependent: :destroy

  enum :role, {
    admin: "admin",
    provider: "provider",
    nurse: "nurse",
    front_desk: "front_desk"
  }, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :first_name, :last_name, presence: true
end
