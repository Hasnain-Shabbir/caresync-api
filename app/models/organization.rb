class Organization < ApplicationRecord
  has_many :users, dependent: :restrict_with_exception
  has_many :patients, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: true
end
