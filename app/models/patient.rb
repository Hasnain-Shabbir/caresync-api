class Patient < ApplicationRecord
  belongs_to :organization

  validates :first_name, :last_name, :date_of_birth, presence: true
end
