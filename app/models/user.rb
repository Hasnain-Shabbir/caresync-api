class User < ApplicationRecord
  belongs_to :organization

  enum :role, {
    admin: "admin",
    provider: "provider",
    nurse: "nurse",
    front_desk: "front_desk"
  }, validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true,
                    uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true
end
